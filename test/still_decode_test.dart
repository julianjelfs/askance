import 'dart:ui' as ui;

import 'package:askance/data/qr_transfer/still_decode.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr/qr.dart';

/// The still-photo fallback must read back exactly what the share panel
/// draws: paint a code the same way, photograph it in the loosest sense, and
/// decode it.
void main() {
  test('a painted code round-trips through the photo decoder', () async {
    const payload = 'askance1:c29tZS10b2tlbg:c29tZS1rZXktYnl0ZXMtaGVyZQ';
    final qr = QrImage(
      QrCode.fromData(data: payload, errorCorrectLevel: QrErrorCorrectLevel.M),
    );

    const cell = 8.0;
    final side = (qr.moduleCount + 8) * cell; // quiet zone either side
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, side, side));
    canvas.drawRect(
      Rect.fromLTWH(0, 0, side, side),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    final ink = Paint()..color = const Color(0xFF000000);
    for (var y = 0; y < qr.moduleCount; y++) {
      for (var x = 0; x < qr.moduleCount; x++) {
        if (qr.isDark(y, x)) {
          canvas.drawRect(
            Rect.fromLTWH((x + 4) * cell, (y + 4) * cell, cell, cell),
            ink,
          );
        }
      }
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(side.round(), side.round());
    picture.dispose();
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();

    final decoded = await decodeQrFromPhoto(png!.buffer.asUint8List());
    expect(decoded, payload);
  });

  test('a photograph of nothing in particular decodes to null', () async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder, const Rect.fromLTWH(0, 0, 64, 64)).drawRect(
      const Rect.fromLTWH(0, 0, 64, 64),
      Paint()..color = const Color(0xFF808080),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(64, 64);
    picture.dispose();
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();

    expect(await decodeQrFromPhoto(png!.buffer.asUint8List()), isNull);
  });
}
