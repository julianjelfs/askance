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
    await channel.send(
      RTCDataChannelMessage(
        jsonEncode({'bytes': imageBytes.length, 'settings': settingsJson}),
      ),
    );
    for (var offset = 0; offset < imageBytes.length; offset += _chunkSize) {
      final end = (offset + _chunkSize).clamp(0, imageBytes.length);
      await channel.send(
        RTCDataChannelMessage.fromBinary(imageBytes.sublist(offset, end)),
      );
      onProgress('Sending…', end / imageBytes.length);
      // Crude backpressure: SCTP buffers are finite and flutter_webrtc does
      // not surface bufferedAmount everywhere, so breathe every half MB.
      if (offset ~/ _chunkSize % 32 == 31) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
    }

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
