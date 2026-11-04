import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'signal.dart';

/// Streams a study — source photograph plus its settings — from the surface
/// showing the QR to the phone that scanned it, over a WebRTC data channel.
///
/// Signalling goes through [QrSignal]; the study itself travels peer to peer,
/// which in practice means across the room's Wi-Fi: scanning a QR off a
/// screen puts the two devices within eyeshot of each other, so the local
/// network path almost always exists. One public STUN server is listed for
/// the odd network where the direct route needs help.
const _iceConfig = {
  'iceServers': [
    {'urls': 'stun:stun.l.google.com:19302'},
  ],
};

/// Data channel messages stay under the safe SCTP threshold.
const _chunkSize = 16 * 1024;

/// What arrives on the phone.
typedef ReceivedStudy = ({Uint8List imageBytes, Map<String, Object?> settings});

typedef Progress = void Function(String stage, double? fraction);

void _log(String message) => debugPrint('[askance-qr] $message');

/// Waits for ICE gathering to finish so the published SDP carries every
/// candidate — non-trickle keeps the broker chatter to one message each way.
Future<RTCSessionDescription> _gathered(RTCPeerConnection pc) async {
  if (pc.iceGatheringState ==
      RTCIceGatheringState.RTCIceGatheringStateComplete) {
    return (await pc.getLocalDescription())!;
  }
  final done = Completer<void>();
  pc.onIceGatheringState = (state) {
    if (state == RTCIceGatheringState.RTCIceGatheringStateComplete &&
        !done.isCompleted) {
      done.complete();
    }
  };
  // Belt and braces: some stacks dawdle over the completion event; whatever
  // has gathered by then is almost always the useful set.
  await done.future.timeout(const Duration(seconds: 4), onTimeout: () {});
  return (await pc.getLocalDescription())!;
}

/// Sends [header] as text, then [bytes] in chunks the data channel can
/// carry. The header names the byte count, so the far side knows when it
/// has the lot.
Future<void> _sendChunked(
  RTCDataChannel channel,
  Map<String, Object?> header,
  Uint8List bytes,
  void Function(double fraction) onFraction,
) async {
  await channel.send(RTCDataChannelMessage(jsonEncode(header)));
  for (var offset = 0; offset < bytes.length; offset += _chunkSize) {
    final end = (offset + _chunkSize).clamp(0, bytes.length);
    await channel.send(
      RTCDataChannelMessage.fromBinary(bytes.sublist(offset, end)),
    );
    onFraction(end / bytes.length);
    // Crude backpressure: SCTP buffers are finite and flutter_webrtc does
    // not surface bufferedAmount everywhere, so breathe every half MB.
    if (offset ~/ _chunkSize % 32 == 31) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
  }
}

/// The sharing side: builds the offer, waits to be scanned, sends the study.
class QrSender {
  QrSender({required this.onProgress});

  final Progress onProgress;
  RTCPeerConnection? _pc;
  QrSignal? _signal;

  /// Returns the payload to draw as a QR, then runs the whole exchange when
  /// the other side turns up. Completes when the study has been delivered.
  Future<void> send({
    required Uint8List imageBytes,
    required Map<String, Object?> settingsJson,
    required void Function(String qrPayload) onQrReady,
  }) async {
    final room = QrSignal.newRoom();
    onProgress('Reaching the signalling broker…', null);
    final signal = _signal = await QrSignal.connect(
      token: room.token,
      keyB64: room.keyB64,
      onAttempt: (broker) => onProgress('Trying $broker…', null),
    );

    final pc = _pc = await createPeerConnection(_iceConfig);
    final channel = await pc.createDataChannel(
      'study',
      RTCDataChannelInit()..ordered = true,
    );

    await pc.setLocalDescription(await pc.createOffer());
    final offer = await _gathered(pc);
    await signal.publish({
      'role': 'offer',
      'sdp': offer.sdp,
      'type': offer.type,
    }, retain: true);
    onQrReady(room.payload);
    onProgress('Waiting for the phone to scan…', null);

    final answer = await signal.waitFor('answer');
    await pc.setRemoteDescription(
      RTCSessionDescription(
        answer['sdp']! as String,
        answer['type']! as String,
      ),
    );
    onProgress('Connecting…', null);

    final open = Completer<void>();
    channel.onDataChannelState = (state) {
      if (state == RTCDataChannelState.RTCDataChannelOpen &&
          !open.isCompleted) {
        open.complete();
      }
    };
    if (channel.state == RTCDataChannelState.RTCDataChannelOpen &&
        !open.isCompleted) {
      open.complete();
    }
    await open.future.timeout(const Duration(seconds: 30));

    // The far side confirms with a message; watch for it before sending so a
    // fast ack cannot be missed.
    final acked = Completer<void>();
    channel.onMessage = (message) {
      if (!acked.isCompleted) acked.complete();
    };

    onProgress('Sending…', 0);
    await _sendChunked(
      channel,
      {'bytes': imageBytes.length, 'settings': settingsJson},
      imageBytes,
      (fraction) => onProgress('Sending…', fraction),
    );

    await acked.future.timeout(const Duration(minutes: 2));
    signal.clearRetained();
    onProgress('Delivered', 1);
  }

  void dispose() {
    _pc?.close();
    _signal?.dispose();
  }
}

/// The scanning side: answers the offer and collects the study.
class QrReceiver {
  QrReceiver({required this.onProgress});

  final Progress onProgress;
  RTCPeerConnection? _pc;
  QrSignal? _signal;

  Future<ReceivedStudy> receive(String qrPayload) async {
    final room = QrSignal.parse(qrPayload);
    if (room == null) {
      throw const FormatException('Not an askance code');
    }
    onProgress('Reaching the signalling broker…', null);
    _log('receiver: connecting to broker');
    final signal = _signal = await QrSignal.connect(
      token: room.token,
      keyB64: room.keyB64,
      onAttempt: (broker) {
        _log('receiver: trying $broker');
        onProgress('Trying $broker…', null);
      },
    );
    _log('receiver: broker connected');

    // The offer was published before the QR appeared, but grab the stream
    // first in case the broker replays it late.
    final offerFuture = signal.waitFor('offer');
    final pc = _pc = await createPeerConnection(_iceConfig);

    final study = Completer<ReceivedStudy>();
    var expected = 0;
    Map<String, Object?>? settings;
    final chunks = BytesBuilder(copy: false);
    RTCDataChannel? channel;

    pc.onDataChannel = (dc) {
      _log('receiver: data channel arrived');
      channel = dc;
      dc.onMessage = (message) {
        if (message.isBinary) {
          chunks.add(message.binary);
          if (expected > 0) {
            onProgress('Receiving…', chunks.length / expected);
          }
        } else {
          final header = jsonDecode(message.text) as Map<String, Object?>;
          expected = header['bytes']! as int;
          settings = (header['settings'] as Map?)?.cast<String, Object?>();
        }
        if (expected > 0 && chunks.length >= expected && !study.isCompleted) {
          dc.send(RTCDataChannelMessage(jsonEncode({'ok': true})));
          study.complete((
            imageBytes: chunks.takeBytes(),
            settings: settings ?? const {},
          ));
        }
      };
    };

    _log('receiver: waiting for offer');
    final offer = await offerFuture;
    _log('receiver: offer received, answering');
    await pc.setRemoteDescription(
      RTCSessionDescription(offer['sdp']! as String, offer['type']! as String),
    );
    await pc.setLocalDescription(await pc.createAnswer());
    final answer = await _gathered(pc);
    await signal.publish({
      'role': 'answer',
      'sdp': answer.sdp,
      'type': answer.type,
    });
    _log('receiver: answer published');
    onProgress('Connecting…', null);
    pc.onIceConnectionState = (state) => _log('receiver: ice $state');

    try {
      return await study.future.timeout(const Duration(minutes: 3));
    } finally {
      // Give the ack a moment to flush before the channel goes down.
      await Future<void>.delayed(const Duration(milliseconds: 250));
      channel?.close();
    }
  }

  void dispose() {
    _pc?.close();
    _signal?.dispose();
  }
}

/// Puts photographs back together from a data channel: a text header
/// naming the byte count, then binary chunks until there are that many.
/// Any number of photographs, one after another, down the same channel.
class PhotoAssembler {
  PhotoAssembler({required this.onPhoto, this.onFraction});

  final void Function(Uint8List bytes) onPhoto;
  final void Function(double fraction)? onFraction;

  int _expected = 0;
  BytesBuilder _chunks = BytesBuilder(copy: false);

  /// A header for the next photograph. A header arriving partway through
  /// one drops the rest of it: the sender gave up on it.
  void header(String text) {
    final decoded = jsonDecode(text);
    if (decoded is! Map || decoded['bytes'] is! int) return;
    _expected = decoded['bytes'] as int;
    _chunks = BytesBuilder(copy: false);
  }

  void chunk(Uint8List bytes) {
    if (_expected <= 0) return;
    _chunks.add(bytes);
    onFraction?.call((_chunks.length / _expected).clamp(0.0, 1.0));
    if (_chunks.length >= _expected) {
      final expected = _expected;
      final photo = _chunks.takeBytes();
      _expected = 0;
      onPhoto(
        photo.length == expected
            ? photo
            : Uint8List.sublistView(photo, 0, expected),
      );
    }
  }
}

/// The laptop's side of sending a sketch: offers a room, waits for the
/// phone to open the link, then takes every photograph the phone sends
/// until either side goes. The roles of the study transfer, reversed: the
/// side showing the code receives.
class SketchHost {
  SketchHost({
    required this.onConnected,
    required this.onFraction,
    required this.onPhoto,
    required this.onClosed,
  });

  final void Function() onConnected;
  final void Function(double fraction) onFraction;
  final void Function(Uint8List bytes) onPhoto;

  /// The phone went, or the connection did. Not called after [dispose].
  final void Function() onClosed;

  RTCPeerConnection? _pc;
  QrSignal? _signal;
  bool _disposed = false;

  /// Calls [onRoomReady] with the room once the offer is up for the phone
  /// to find, then waits for it. Completes once the phone is connected;
  /// photographs arrive through [onPhoto] after that.
  Future<void> open({
    required void Function(String token, String keyB64) onRoomReady,
  }) async {
    final room = QrSignal.newRoom();
    final signal = _signal = await QrSignal.connect(
      token: room.token,
      keyB64: room.keyB64,
    );
    final pc = _pc = await createPeerConnection(_iceConfig);
    final channel = await pc.createDataChannel(
      'sketch',
      RTCDataChannelInit()..ordered = true,
    );
    final assembler = PhotoAssembler(
      onFraction: onFraction,
      onPhoto: (bytes) {
        channel.send(RTCDataChannelMessage(jsonEncode({'ok': true})));
        onPhoto(bytes);
      },
    );
    channel.onMessage = (message) => message.isBinary
        ? assembler.chunk(message.binary)
        : assembler.header(message.text);

    await pc.setLocalDescription(await pc.createOffer());
    final offer = await _gathered(pc);
    await signal.publish({
      'role': 'offer',
      'sdp': offer.sdp,
      'type': offer.type,
    }, retain: true);
    onRoomReady(room.token, room.keyB64);

    // Long enough to find the phone, unlock it and point it at the screen.
    final answer = await signal.waitFor(
      'answer',
      timeout: const Duration(minutes: 10),
    );
    await pc.setRemoteDescription(
      RTCSessionDescription(
        answer['sdp']! as String,
        answer['type']! as String,
      ),
    );
    await _opened(channel).timeout(const Duration(seconds: 30));

    // One phone per code: nobody else can find the room now, and the
    // broker has nothing more to carry.
    signal.clearRetained();
    signal.dispose();
    _signal = null;

    channel.onDataChannelState = (state) {
      if (state == RTCDataChannelState.RTCDataChannelClosed) _close();
    };
    pc.onConnectionState = (state) {
      // Not on disconnected: that one often recovers by itself, as a phone
      // locks and wakes.
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        _close();
      }
    };
    onConnected();
  }

  void _close() {
    if (_disposed) return;
    dispose();
    onClosed();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _pc?.close();
    _signal?.dispose();
  }
}

/// The phone's side of sending a sketch: joins the room in the link it was
/// opened with, then sends photographs one at a time.
class SketchGuest {
  SketchGuest({required this.onClosed});

  /// The laptop went, or the connection did. Not called after [dispose].
  final void Function() onClosed;

  RTCPeerConnection? _pc;
  QrSignal? _signal;
  RTCDataChannel? _channel;
  Completer<void>? _ack;
  bool _disposed = false;

  Future<void> join({required String token, required String keyB64}) async {
    final signal = _signal = await QrSignal.connect(
      token: token,
      keyB64: keyB64,
    );
    final offerFuture = signal.waitFor('offer');
    final pc = _pc = await createPeerConnection(_iceConfig);
    final channel = Completer<RTCDataChannel>();
    pc.onDataChannel = (dc) {
      dc.onMessage = (message) {
        if (!message.isBinary && !(_ack?.isCompleted ?? true)) {
          _ack!.complete();
        }
      };
      if (!channel.isCompleted) channel.complete(dc);
    };

    final offer = await offerFuture;
    await pc.setRemoteDescription(
      RTCSessionDescription(offer['sdp']! as String, offer['type']! as String),
    );
    await pc.setLocalDescription(await pc.createAnswer());
    final answer = await _gathered(pc);
    await signal.publish({
      'role': 'answer',
      'sdp': answer.sdp,
      'type': answer.type,
    });

    final dc = _channel = await channel.future.timeout(
      const Duration(seconds: 30),
    );
    await _opened(dc).timeout(const Duration(seconds: 30));
    signal.dispose();
    _signal = null;

    dc.onDataChannelState = (state) {
      if (state == RTCDataChannelState.RTCDataChannelClosed) _close();
    };
    pc.onConnectionState = (state) {
      // Not on disconnected: that one often recovers by itself, as a phone
      // locks and wakes.
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        _close();
      }
    };
  }

  /// Sends one photograph and waits for the laptop to say it has it.
  Future<void> send(
    Uint8List bytes, {
    required void Function(double fraction) onFraction,
  }) async {
    final channel = _channel;
    if (channel == null) throw StateError('not connected');
    final ack = _ack = Completer<void>();
    await _sendChunked(channel, {'bytes': bytes.length}, bytes, onFraction);
    await ack.future.timeout(const Duration(minutes: 2));
  }

  void _close() {
    if (_disposed) return;
    dispose();
    onClosed();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _channel?.close();
    _pc?.close();
    _signal?.dispose();
  }
}

/// Completes once [channel] is open, at once if it already is.
Future<void> _opened(RTCDataChannel channel) {
  final open = Completer<void>();
  if (channel.state == RTCDataChannelState.RTCDataChannelOpen) {
    open.complete();
    return open.future;
  }
  final previous = channel.onDataChannelState;
  channel.onDataChannelState = (state) {
    previous?.call(state);
    if (state == RTCDataChannelState.RTCDataChannelOpen && !open.isCompleted) {
      open.complete();
    }
  };
  return open.future;
}
