import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:typed_data/typed_data.dart' show Uint8Buffer;

import 'mqtt_factory_io.dart'
    if (dart.library.js_interop) 'mqtt_factory_web.dart';

/// The signalling channel for the QR transfer: a public MQTT broker carrying
/// nothing but two encrypted SDP blobs, roughly a kilobyte each.
///
/// The app runs no backend, so the handshake borrows infrastructure that
/// already exists and is offered freely. Everything published is AES-GCM
/// encrypted with a key that travels only inside the QR code, so the broker
/// carries ciphertext it has no key for — it learns that two parties spoke,
/// not what was said, and the photograph itself never touches it: that goes
/// peer to peer once the handshake completes.
class QrSignal {
  QrSignal._(this._client, this._topic, this._key);

  /// Tried in order; the first that connects carries the handshake. Both ends
  /// walk the same list, so a broker being down only costs a retry, not the
  /// transfer — as long as both parties can reach the *same* one.
  static const _brokers = [
    ('wss://broker.emqx.io/mqtt', 8084),
    ('wss://broker.hivemq.com/mqtt', 8884),
  ];

  final MqttClient _client;
  final String _topic;
  final SecretKey _key;
  final _cipher = AesGcm.with256bits();
  final _messages = StreamController<Map<String, Object?>>.broadcast();
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _sub;

  /// Everything decryptable arriving on the room's topic, own echoes included
  /// — callers filter by role.
  Stream<Map<String, Object?>> get messages => _messages.stream;

  /// A fresh room: 128-bit token naming the topic, 256-bit key for the
  /// payloads. [payload] is what belongs in the QR code.
  static ({String token, String keyB64, String payload}) newRoom() {
    final rng = Random.secure();
    List<int> bytes(int n) => List.generate(n, (_) => rng.nextInt(256));
    final token = base64UrlEncode(bytes(16)).replaceAll('=', '');
    final key = base64UrlEncode(bytes(32)).replaceAll('=', '');
    return (token: token, keyB64: key, payload: 'askance1:$token:$key');
  }

  /// Parses a scanned QR payload; null if it is not ours.
  static ({String token, String keyB64})? parse(String payload) {
    final parts = payload.split(':');
    if (parts.length != 3 || parts[0] != 'askance1') return null;
    return (token: parts[1], keyB64: parts[2]);
  }

  static Future<QrSignal> connect({
    required String token,
    required String keyB64,
    void Function(String note)? onAttempt,
  }) async {
    Object? lastError;
    for (final (url, port) in _brokers) {
      onAttempt?.call(
        url.replaceFirst(RegExp(r'^wss://'), '').split('/').first,
      );
      // Not 1 << 32: dart2js wraps shifts at 32 bits, making that 0.
      final id = 'askance-${Random.secure().nextInt(0x7fffffff)}';
      final client = createClient(url, port, id)
        ..keepAlivePeriod = 30
        ..setProtocolV311();
      try {
        final status = await client.connect().timeout(
          const Duration(seconds: 8),
        );
        if (status?.state != MqttConnectionState.connected) {
          throw StateError('broker state ${status?.state}');
        }
        final key = SecretKey(base64Url.decode(base64.normalize(keyB64)));
        final signal = QrSignal._(client, 'askance/qr/$token', key);
        signal._listen();
        return signal;
      } catch (e) {
        lastError = e;
        client.disconnect();
      }
    }
    throw StateError('No signalling broker reachable: $lastError');
  }

  void _listen() {
    _client.subscribe(_topic, MqttQos.atLeastOnce);
    _sub = _client.updates?.listen((events) async {
      for (final event in events) {
        final message = event.payload;
        if (message is! MqttPublishMessage) continue;
        try {
          final raw = utf8.decode(
            message.payload.message,
            allowMalformed: true,
          );
          final envelope = jsonDecode(raw) as Map<String, Object?>;
          final clear = await _decrypt(envelope);
          _messages.add(clear);
        } catch (_) {
          // Not ours, or not decryptable with our key: someone else's noise
          // on a public broker. Ignore rather than fail the handshake.
        }
      }
    });
  }

  /// [retain] asks the broker to hand the message to subscribers who arrive
  /// after it was published. The offer needs it: it is published before the
  /// QR is even on screen, so the scanning side always subscribes late.
  Future<void> publish(
    Map<String, Object?> message, {
    bool retain = false,
  }) async {
    final box = await _cipher.encrypt(
      utf8.encode(jsonEncode(message)),
      secretKey: _key,
    );
    final envelope = jsonEncode({
      'n': base64Encode(box.nonce),
      'c': base64Encode(box.cipherText),
      'm': base64Encode(box.mac.bytes),
    });
    final builder = MqttClientPayloadBuilder()..addUTF8String(envelope);
    _client.publishMessage(
      _topic,
      MqttQos.atLeastOnce,
      builder.payload!,
      retain: retain,
    );
  }

  /// Clears whatever the broker retained for this room, so the encrypted
  /// offer does not outlive the handshake.
  void clearRetained() {
    try {
      _client.publishMessage(
        _topic,
        MqttQos.atLeastOnce,
        Uint8Buffer(),
        retain: true,
      );
    } catch (_) {
      // Best effort: the payload is ciphertext on a random topic either way.
    }
  }

  Future<Map<String, Object?>> _decrypt(Map<String, Object?> envelope) async {
    final clear = await _cipher.decrypt(
      SecretBox(
        base64Decode(envelope['c']! as String),
        nonce: base64Decode(envelope['n']! as String),
        mac: Mac(base64Decode(envelope['m']! as String)),
      ),
      secretKey: _key,
    );
    return jsonDecode(utf8.decode(clear)) as Map<String, Object?>;
  }

  /// Waits for the first message with [role], e.g. the answer.
  Future<Map<String, Object?>> waitFor(
    String role, {
    Duration timeout = const Duration(minutes: 2),
  }) => messages.firstWhere((m) => m['role'] == role).timeout(timeout);

  void dispose() {
    _sub?.cancel();
    _messages.close();
    _client.disconnect();
  }
}

Uint8List randomBytes(int n) {
  final rng = Random.secure();
  return Uint8List.fromList(List.generate(n, (_) => rng.nextInt(256)));
}
