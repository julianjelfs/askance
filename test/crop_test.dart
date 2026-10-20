import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:askance/engine/crop.dart';
import 'package:askance/engine/deferred_disposer.dart';
import 'package:askance/engine/engine.dart';
import 'package:askance/engine/export.dart';
import 'package:askance/engine/value_painter.dart';
import 'package:askance/model/study.dart';
import 'package:askance/state/canvas_session.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('crop geometry', () {
    const photo = Size(4000, 3000);

    test('a fitted crop has the asked-for shape and stays inside the '
        'photograph', () {
      for (final (aspect, centre, scale) in [
        (math.sqrt1_2, const Offset(0.5, 0.5), 1.0),
        (math.sqrt1_2, const Offset(0, 0), 0.4),
        (1 / math.sqrt1_2, const Offset(1, 1), 0.6),
        (1.0, const Offset(0.9, 0.2), 0.01),
      ]) {
        final crop = fitCrop(photo, aspect, centre: centre, scale: scale);
        final px = cropPixels(photo, crop);
        expect(px.width / px.height, closeTo(aspect, 1e-9));
        expect(crop.left, greaterThanOrEqualTo(0));
        expect(crop.top, greaterThanOrEqualTo(0));
        expect(crop.right, lessThanOrEqualTo(1 + 1e-12));
        expect(crop.bottom, lessThanOrEqualTo(1 + 1e-12));
      }
    });

    test('a crop is recognised as the shape it was cut to', () {
      final a4 = fitCrop(
        photo,
        CropShape.aSeries.aspect(landscape: false)!,
        scale: 0.5,
      );
      final found = cropShapeOf(photo, a4);
      expect(found?.shape, CropShape.aSeries);
      expect(found?.landscape, isFalse);
      expect(cropScaleOf(photo, a4), closeTo(0.5, 1e-9));
    });
  });

  group('a stored crop', () {
    test('survives saving and reopening a study', () {
      const settings = StudySettings(crop: Rect.fromLTRB(0.1, 0.2, 0.6, 0.9));
      expect(StudySettings.fromJson(settings.toJson()), settings);
    });

    test('that is missing or unusable opens as the whole photograph', () {
      for (final crop in [
        null,
        'a4',
        [0.1, 0.2],
        [-0.1, 0, 1, 1],
        [0, 0, 1.5, 1],
        [0.5, 0.5, 0.5, 0.9],
      ]) {
        expect(
          StudySettings.fromJson({'crop': crop}).crop,
          kWholeImage,
          reason: '$crop',
        );
      }
    });
  });

  test('cropping shows the new picture whole, not the old zoom', () {
    final session = CanvasSession()
      ..setView(const ViewTransform(zoom: 3, offset: Offset(-0.4, -0.2)));
    addTearDown(session.dispose);
    session.setCrop(const Rect.fromLTRB(0, 0, 0.5, 1));
    expect(session.view, const ViewTransform());
  });

  group('an export', () {
    test('of an A4 crop at print size is A4 at 300 dpi', () {
      final frame = ExportSize.print.frameFor(
        Size(1000, 1000 / CropShape.aSeries.shortOverLong!),
      );
      expect(frame, const Size(2480, 3507));
    });

    test('of a landscape picture lies the long side across', () {
      final frame = ExportSize.screen.frameFor(const Size(3000, 2000));
      expect(frame, const Size(1800, 1200));
    });
  });

  test('the study is only of the cropped part of the photograph', () async {
    // Light on the left half, dark on the right.
    const width = 800, height = 200;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, width / 2, height + 0.0),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    canvas.drawRect(
      const Rect.fromLTWH(width / 2, 0, width / 2, height + 0.0),
      Paint()..color = const Color(0xFF000000),
    );
    final picture = recorder.endRecording();
    final source = await picture.toImage(width, height);
    picture.dispose();
    addTearDown(source.dispose);

    // The light half alone, framed exactly.
    const crop = Rect.fromLTRB(0, 0, 0.5, 1);
    const output = Size(400, 200);
    const view = ViewTransform();
    final shader = await ValueShader.load();
    final blurred = await renderBlurredSource(
      source: source,
      outputPx: output,
      detail: 1,
      view: view,
      crop: crop,
    );
    addTearDown(blurred.dispose);

    final disposer = DeferredDisposer();
    final out = ui.PictureRecorder();
    final painter = ValuePainter(
      shader: shader,
      source: source,
      blurred: blurred,
      settings: const StudySettings(steps: 2, crop: crop),
      view: view,
      devicePixelRatio: 1,
      peeking: false,
      splitPosition: 0.5,
      disposer: disposer,
      drawGrid: false,
    )..paint(Canvas(out, Offset.zero & output), output);
    final rendered = await out.endRecording().toImage(400, 200);
    painter.disposeResources();
    disposer.disposeAll();
    final bytes = (await rendered.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!.buffer.asUint8List();
    rendered.dispose();

    int redAt(int x, int y) => bytes[(y * 400 + x) * 4];
    // Uncropped, the right of this frame would be the dark half.
    expect(redAt(10, 100), greaterThan(200));
    expect(redAt(390, 100), greaterThan(200));
  });
}
