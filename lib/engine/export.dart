import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import '../model/study.dart';
import 'crop.dart';
import 'deferred_disposer.dart';
import 'engine.dart';
import 'value_painter.dart';

/// The two export sizes, as the box the picture is fitted into: the long side
/// and the short side, turned to match the picture.
enum ExportSize {
  screen('Screen', 1200, 1800),
  print('Print', 2480, 3720);

  const ExportSize(this.label, this.short, this.long);

  final String label;
  final int short;
  final int long;

  /// The frame a [picture]-shaped study exports into: the picture's own
  /// shape, as large as fits. A fixed 2:3 frame letterboxed every picture of
  /// any other shape, and an A4 crop exported at print size would not have
  /// come out 2480 × 3507, which is A4 at 300 dpi.
  Size frameFor(Size picture) {
    if (picture.isEmpty) return Size(short.toDouble(), long.toDouble());
    final landscape = picture.width > picture.height;
    final box = landscape
        ? Size(long.toDouble(), short.toDouble())
        : Size(short.toDouble(), long.toDouble());
    final fitted = containRect(picture, box).size;
    return Size(
      fitted.width.round().clamp(1, box.width.toInt()).toDouble(),
      fitted.height.round().clamp(1, box.height.toInt()).toDouble(),
    );
  }

  String noteFor(Size picture) {
    final frame = frameFor(picture);
    final px = '${frame.width.toInt()} × ${frame.height.toInt()} px';
    return this == print ? '$px · 300 dpi' : px;
  }
}

/// Re-runs the engine at the target size from the original image — never an
/// upscale of the screen raster — and honours the current zoom, so an export
/// carries the passage being studied rather than the whole frame.
Future<Uint8List?> renderExport({
  required ValueShader shader,
  required ui.Image source,
  required StudySettings settings,
  required ViewTransform view,
  required ExportSize target,
  required double splitPosition,
}) async {
  final size = target.frameFor(
    croppedSize(
      Size(source.width.toDouble(), source.height.toDouble()),
      settings.crop,
    ),
  );

  // The view is resolution independent, so the same transform describes the
  // same crop at export size with nothing to convert.
  final exportView = view;

  final blurred = await renderBlurredSource(
    source: source,
    outputPx: size,
    detail: settings.detail,
    view: exportView,
    smoothing: settings.smoothing,
    lockDetail: settings.lockDetail,
    crop: settings.crop,
    steps: settings.steps,
    bias: settings.bias,
    tone: settings.tone,
  );
  final photoBlurred = switch (settings.photoBlurDetail) {
    final detail? => await renderBlurredSource(
      source: source,
      outputPx: size,
      detail: detail,
      view: exportView,
      crop: settings.crop,
    ),
    null => null,
  };

  final disposer = DeferredDisposer();
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder, Offset.zero & size);
  final painter = ValuePainter(
    shader: shader,
    source: source,
    blurred: blurred,
    photoBlurred: photoBlurred,
    settings: settings,
    view: exportView,
    // The export canvas is already at output resolution, so one logical pixel
    // is one output pixel.
    devicePixelRatio: 1,
    peeking: false,
    splitPosition: splitPosition,
    disposer: disposer,
    // In exports the grid is drawn into the image, dividing the exported frame.
    drawGrid: true,
  );
  painter.paint(canvas, size);

  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.toInt(), size.height.toInt());
  picture.dispose();

  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  painter.disposeResources();
  disposer.disposeAll();
  blurred.dispose();
  photoBlurred?.dispose();
  return png?.buffer.asUint8List();
}

String exportFilename(String studyName, Size frame) =>
    '${slugify(studyName)}-${frame.width.toInt()}x${frame.height.toInt()}.png';
