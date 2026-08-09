import 'dart:ui' as ui;

import 'package:askance/engine/deferred_disposer.dart';
import 'package:askance/engine/engine.dart';
import 'package:askance/engine/value_painter.dart';
import 'package:askance/model/study.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// A landscape photograph in a tall frame is shown whole, with the ground
/// left showing above and below rather than the sides being cropped away.
///
/// This renders the real shader, because the pass it samples now covers only
/// the part of the frame the picture occupies, and the fragment coordinates
/// have to be made relative to that rect. Getting it wrong shifts or smears
/// the picture in a way only pixels will show.
void main() {
  /// Landscape, light on the left half and dark on the right.
  Future<ui.Image> halfAndHalf(int width, int height) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width / 2, height.toDouble()),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    canvas.drawRect(
      Rect.fromLTWH(width / 2, 0, width / 2, height.toDouble()),
      Paint()..color = const Color(0xFF000000),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    picture.dispose();
    return image;
  }

  test(
    'the whole of a landscape photograph is shown, and nothing else',
    () async {
      final shader = await ValueShader.load();
      final source = await halfAndHalf(800, 200);
      addTearDown(source.dispose);

      // A tall frame, as on a phone.
      const output = Size(400, 800);
      const view = ViewTransform();
      final sourceSize = Size(
        source.width.toDouble(),
        source.height.toDouble(),
      );
      final area = view.visible(sourceSize, output);

      expect(
        area.width,
        closeTo(output.width, 0.001),
        reason: 'a wide photograph should meet the sides',
      );
      expect(
        area.height,
        closeTo(100, 0.001),
        reason: '800x200 into a 400 wide frame is 400x100',
      );

      final blurred = await renderBlurredSource(
        source: source,
        outputPx: output,
        detail: 1,
        view: view,
      );
      addTearDown(blurred.dispose);

      final disposer = DeferredDisposer();
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Offset.zero & output);
      final painter = ValuePainter(
        shader: shader,
        source: source,
        blurred: blurred,
        settings: const StudySettings(steps: 2),
        view: view,
        devicePixelRatio: 1,
        peeking: false,
        splitPosition: 0.5,
        regions: null,
        disposer: disposer,
        drawGrid: false,
      )..paint(canvas, output);

      final picture = recorder.endRecording();
      final rendered = await picture.toImage(
        output.width.round(),
        output.height.round(),
      );
      picture.dispose();
      painter.disposeResources();
      disposer.disposeAll();

      final bytes = (await rendered.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      rendered.dispose();

      ({int r, int g, int b, int a}) at(int x, int y) {
        final i = (y * output.width.round() + x) * 4;
        return (r: bytes[i], g: bytes[i + 1], b: bytes[i + 2], a: bytes[i + 3]);
      }

      // Above and below the picture nothing is painted at all, so whichever
      // ground the surface supplies shows through.
      expect(at(200, 20).a, 0, reason: 'the band above the picture');
      expect(at(200, 780).a, 0, reason: 'the band below the picture');

      // Inside it, the two halves of the photograph land on the two ends of the
      // scale, on the correct sides. A wrong origin would slide or mirror these.
      final left = at(60, 400);
      final right = at(340, 400);
      expect(left.a, 255, reason: 'the picture itself is opaque');
      expect(
        left.r,
        greaterThan(200),
        reason: 'the light half should read light',
      );
      expect(right.r, lessThan(60), reason: 'the dark half should read dark');
    },
  );
}
