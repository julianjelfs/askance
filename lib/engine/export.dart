import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import '../model/study.dart';
import 'deferred_disposer.dart';
import 'engine.dart';
import 'regions.dart';
import 'value_painter.dart';

/// The two export sizes. Both 2:3, matching the shape a study is composed in.
enum ExportSize {
  screen('SCREEN', 1200, 1800),
  print('PRINT', 2480, 3720);

  const ExportSize(this.label, this.width, this.height);

  final String label;
  final int width;
  final int height;

  Size get size => Size(width.toDouble(), height.toDouble());

  String get note => label == 'PRINT'
      ? '$width × $height px · 300 dpi'
      : '$width × $height px';
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
  final size = target.size;

  // The view is resolution independent, so the same transform describes the
  // same crop at export size with nothing to convert.
  final exportView = view;

  RegionOverlay? overlay;
  if (settings.mode == ViewMode.skeleton && settings.numbers) {
    final found = await computeRegions(
      source: source,
      outputPx: size,
      detail: settings.detail,
      view: exportView,
      steps: settings.steps,
    );
    overlay = RegionOverlay(
      regions: found.regions,
      gridWidth: found.gridWidth,
      gridHeight: found.gridHeight,
    );
  }

  final blurred = await renderBlurredSource(
    source: source,
    outputPx: size,
    detail: settings.detail,
    view: exportView,
  );

  final disposer = DeferredDisposer();
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder, Offset.zero & size);
  final painter = ValuePainter(
    shader: shader,
    source: source,
    blurred: blurred,
    settings: settings,
    view: exportView,
    // The export canvas is already at output resolution, so one logical pixel
    // is one output pixel.
    devicePixelRatio: 1,
    peeking: false,
    splitPosition: splitPosition,
    regions: overlay,
    disposer: disposer,
    // In exports the grid is drawn into the image, dividing the exported frame.
    drawGrid: true,
  );
  painter.paint(canvas, size);

  final picture = recorder.endRecording();
  final image = await picture.toImage(target.width, target.height);
  picture.dispose();

  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  painter.disposeResources();
  disposer.disposeAll();
  blurred.dispose();
  return png?.buffer.asUint8List();
}

String exportFilename(String studyName, ExportSize target) =>
    '${slugify(studyName)}-${target.width}x${target.height}.png';
