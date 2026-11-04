import 'dart:convert';
import 'dart:typed_data';

import 'package:askance/data/qr_transfer/signal.dart';
import 'package:askance/data/qr_transfer/transfer.dart';
import 'package:askance/state/sketch_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the sketch link', () {
    final base = Uri.parse('https://askance.julianjelfs.co.uk/');

    test('carries the room in its fragment and nowhere a server sees it', () {
      final room = QrSignal.newRoom();
      final link = QrSignal.sketchLink(base, room.token, room.keyB64);
      final uri = Uri.parse(link);
      expect(uri.query, isEmpty);
      expect(uri.path, isNot(contains(room.keyB64)));
      expect(uri.fragment, contains(room.keyB64));
      expect(QrSignal.parseSketchLink(link), (
        token: room.token,
        keyB64: room.keyB64,
      ));
    });

    test('is not mistaken for anything else', () {
      final study = QrSignal.newRoom().payload;
      expect(QrSignal.parseSketchLink(study), isNull);
      expect(QrSignal.parseSketchLink('https://example.com/#/'), isNull);
      expect(QrSignal.parseSketchLink('https://example.com/#sketch='), isNull);
    });

    test('sends the phone to the published app from a page on this machine '
        'or a native app, and to this app from anywhere else', () {
      expect(sketchLinkBase(page: null), base);
      expect(sketchLinkBase(page: Uri.parse('http://localhost:8000/')), base);
      expect(
        sketchLinkBase(page: Uri.parse('http://192.168.1.20:8000/#/')),
        Uri.parse('http://192.168.1.20:8000/'),
      );
    });
  });

  test('photographs come back whole from their chunks, one after another, '
      'and one abandoned partway is dropped', () {
    final photos = <Uint8List>[];
    final assembler = PhotoAssembler(onPhoto: photos.add);
    void send(List<int> bytes, {int? cutAt}) {
      assembler.header(jsonEncode({'bytes': bytes.length}));
      final end = cutAt ?? bytes.length;
      for (var i = 0; i < end; i += 7) {
        assembler.chunk(
          Uint8List.fromList(bytes.sublist(i, (i + 7).clamp(0, end))),
        );
      }
    }

    final first = List.generate(50, (i) => i);
    final abandoned = List.generate(30, (i) => 200 - i);
    final second = List.generate(21, (i) => i * 3);
    send(first);
    send(abandoned, cutAt: 14);
    send(second);
    expect(photos.map((p) => p.toList()), [first, second]);
  });
}
