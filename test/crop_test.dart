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

  test('cropping lays the grid over the whole new picture', () {
    final session = CanvasSession()
      ..settings = const StudySettings(
        gridFrame: Rect.fromLTRB(0.25, 0.25, 0.75, 0.75),
      );
    addTearDown(session.dispose);
    session.setCrop(const Rect.fromLTRB(0, 0, 0.5, 1));
    expect(session.settings.gridFrame, kWholeImage);
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

  test('zooming stays inside the crop, panned as far as it will go', () async {
    // Light on the left half, dark on the right; the study is cropped to the
    // light half, so nothing dark may ever show, however far in or across.
    const width = 800, height = 400;
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

    const crop = Rect.fromLTRB(0, 0, 0.5, 1);
    const output = Size(300, 300);
    const cropped = Size(400, 400);
    // 3x, pushed hard right and down; the clamp decides where it stops.
    final view = const ViewTransform(zoom: 3, offset: Offset(-5, -5)).copyWith(
      offset: const ViewTransform(
        zoom: 3,
        offset: Offset(-5, -5),
      ).clampedOffset(cropped, output),
    );

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
    final rendered = await out.endRecording().toImage(300, 300);
    painter.disposeResources();
    disposer.disposeAll();
    final bytes = (await rendered.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!.buffer.asUint8List();
    rendered.dispose();

    for (final (x, y) in [(295, 150), (295, 295), (150, 295), (5, 5)]) {
      expect(bytes[(y * 300 + x) * 4], greaterThan(200), reason: '($x, $y)');
    }
  });

  test('zooming keeps the picture in its frame, the board shape and size it '
      'is shown at whole', () async {
    // An A4 crop on a phone: gutters top and bottom at 1x, and the same
    // gutters, the same A4 frame, however far in the pinch goes.
    const output = Size(400, 800);
    final a4 = Size(2100, 2100 / math.sqrt1_2);
    final frame = containRect(a4, output);
    for (final view in [
      const ViewTransform(),
      const ViewTransform().zoomedAt(const Offset(200, 300), 3, a4, output),
      const ViewTransform(zoom: 6, offset: Offset(9, -9)),
    ]) {
      final area = view.visible(a4, output);
      expect(area.left, closeTo(frame.left, 1e-6));
      expect(area.top, closeTo(frame.top, 1e-6));
      expect(area.right, closeTo(frame.right, 1e-6));
      expect(area.bottom, closeTo(frame.bottom, 1e-6));
    }

    // And nothing is painted in the gutters, photograph or study.
    final w = a4.width.round(), h = a4.height.round();
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    final picture = recorder.endRecording();
    final source = await picture.toImage(w, h);
    picture.dispose();
    addTearDown(source.dispose);
    final shader = await ValueShader.load();
    const zoomed = ViewTransform(zoom: 3);
    final blurred = await renderBlurredSource(
      source: source,
      outputPx: output,
      detail: 1,
      view: zoomed,
    );
    addTearDown(blurred.dispose);
    for (final mode in [ViewMode.photo, ViewMode.value]) {
      final disposer = DeferredDisposer();
      final out = ui.PictureRecorder();
      final painter = ValuePainter(
        shader: shader,
        source: source,
        blurred: blurred,
        settings: StudySettings(steps: 2, mode: mode),
        view: zoomed,
        devicePixelRatio: 1,
        peeking: false,
        splitPosition: 0.5,
        disposer: disposer,
        drawGrid: false,
      )..paint(Canvas(out, Offset.zero & output), output);
      final rendered = await out.endRecording().toImage(400, 800);
      painter.disposeResources();
      disposer.disposeAll();
      final bytes = (await rendered.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      rendered.dispose();
      int alphaAt(int x, int y) => bytes[(y * 400 + x) * 4 + 3];
      expect(alphaAt(200, (frame.top / 2).round()), 0, reason: '$mode top');
      expect(
        alphaAt(200, (frame.bottom + 40).round()),
        0,
        reason: '$mode bottom',
      );
      expect(alphaAt(200, 400), 255, reason: '$mode middle');
    }
  });
}
