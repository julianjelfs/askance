import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import '../model/study.dart';
import '../theme.dart';
import 'deferred_disposer.dart';
import 'engine.dart';
import 'random_ramp.dart';

/// Paints the study: the quantised value map, the untouched photograph, the
/// split of the two, or the skeleton — plus the grid, which is always drawn
/// last in screen space so it never rides the zoom transform.
class ValuePainter extends CustomPainter {
  ValuePainter({
    required this.shader,
    required this.source,
    required this.blurred,
    required this.settings,
    required this.view,
    required this.devicePixelRatio,
    required this.peeking,
    required this.splitPosition,
    required this.disposer,
    required this.drawGrid,
    super.repaint,
  });

  final ValueShader shader;
  final ui.Image source;

  /// The pre-rendered blurred offscreen, or null until the first one lands.
  final ui.Image? blurred;
  final StudySettings settings;
  final ViewTransform view;
  final double devicePixelRatio;

  /// Press and hold peeks the untouched photograph whatever the mode.
  final bool peeking;

  /// Live during a drag; written back to the study when the drag ends.
  final double splitPosition;

  final DeferredDisposer disposer;
  final bool drawGrid;

  ui.FragmentShader? _fragment;

  Size get _sourceSize =>
      Size(source.width.toDouble(), source.height.toDouble());

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    disposer.tick();

    final dest = view.destination(_sourceSize, size);
    // What the photograph actually occupies. Shown whole it is less than the
    // frame, and the ground shows on the short pair of edges.
    final area = view.visible(_sourceSize, size);
    final devicePx = Size(
      area.width * devicePixelRatio,
      area.height * devicePixelRatio,
    );
    final showPhoto = peeking || settings.mode == ViewMode.photo;

    // Nothing is painted outside the picture: each surface supplies its own
    // ground behind this, and they differ — ink on the canvas, the lighter
    // surface on the desktop stage and on a shelf card.
    if (showPhoto || blurred == null) {
      _paintPhoto(canvas, size, dest);
    } else {
      _paintProcessed(canvas, area, devicePx);
      if (settings.mode == ViewMode.split) {
        final x = splitPosition * size.width;
        canvas.save();
        canvas.clipRect(Rect.fromLTWH(0, 0, x, size.height));
        _paintPhoto(canvas, size, dest);
        canvas.restore();
        // The 2px rule sits on the boundary itself.
        canvas.drawRect(
          Rect.fromLTWH(x - kRule / 2, 0, kRule, size.height),
          Paint()..color = AskanceColors.accent,
        );
      }
    }

    if (drawGrid && settings.grid != GridMode.off) {
      // Divides the photograph, not the view: the grid is drawn across the
      // whole image at its current size and clipped to what shows, so
      // zooming magnifies the squares with the picture instead of quietly
      // re-dividing whatever happens to be on screen.
      paintGrid(canvas, dest, area, settings.grid, settings.gridDivisions);
    }
  }

  void _paintPhoto(Canvas canvas, Size size, Rect dest) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawImageRect(
      source,
      Offset.zero & _sourceSize,
      dest,
      Paint()..filterQuality = FilterQuality.medium,
    );
    canvas.restore();
  }

  void _paintProcessed(Canvas canvas, Rect area, Size devicePx) {
    final source = blurred;
    if (source == null || area.isEmpty) return;

    // A fresh shader every paint. Reusing one across two recorded pictures
    // renders the second as an empty sampler — the picture appears to take
    // ownership of it — so caching the shader between paints is not safe even
    // though nothing about its uniforms has changed. Building one is cheap:
    // a native handle plus 28 floats.
    final old = _fragment;
    if (old != null) disposer.retire(old.dispose);
    _fragment = shader.build(
      area: area,
      devicePx: devicePx,
      steps: settings.steps,
      ramp:
          settings.mode == ViewMode.random ||
              ((settings.mode == ViewMode.split ||
                      settings.mode == ViewMode.skeleton) &&
                  settings.splitBase == ViewMode.random)
          ? randomRamp(
              scale: settings.scale,
              steps: settings.steps,
              seed: settings.randomSeed,
            )
          : settings.scale.ramp(settings.steps),
      skeleton: settings.mode == ViewMode.skeleton,
      // Clamped so a steps change never asks for bands that no longer exist.
      skeletonFill: settings.skeletonFill.clamp(0, settings.steps),
      bias: settings.bias,
    )..setImageSampler(0, source);

    canvas.drawRect(area, Paint()..shader = _fragment!);
  }

  /// Releases the shader. Only safe once the frame that used it has been
  /// rasterised — exports await their image first.
  void disposeResources() {
    _fragment?.dispose();
    _fragment = null;
  }

  @override
  bool shouldRepaint(covariant ValuePainter old) {
    // Carry the in-flight shader across so the disposer, not the garbage
    // collector, decides when it goes.
    _fragment = old._fragment;
    return old.settings != settings ||
        old.blurred != blurred ||
        old.view != view ||
        old.peeking != peeking ||
        old.splitPosition != splitPosition ||
        old.source != source ||
        old.drawGrid != drawGrid ||
        old.devicePixelRatio != devicePixelRatio;
  }
}

/// The grid, over everything, anchored to the photograph: [image] is the
/// destination rect of the whole picture at the current zoom and pan, and the
/// rules divide it, clipped to [visible]. Drawn in screen space rather than
/// baked into the processed raster so the rule weight never rides the zoom —
/// but the spacing does, which is what makes the grid a division of the
/// picture rather than of whatever is on screen.
void paintGrid(
  Canvas canvas,
  Rect image,
  Rect visible,
  GridMode mode,
  int divisions,
) {
  if (mode == GridMode.off || visible.isEmpty || image.isEmpty) return;
  final paint = Paint()
    ..color = AskanceColors.grid
    ..strokeWidth = kRule;
  final spacing = image.width / divisions;
  final size = image.size;

  canvas.save();
  canvas.clipRect(visible);
  canvas.translate(image.left, image.top);
  if (mode == GridMode.square) {
    for (var x = spacing; x < size.width - 0.01; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = spacing; y < size.height - 0.01; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  } else {
    // Rules at +/-45 degrees, at the same spacing measured perpendicular to
    // the lines, so a diamond grid reads at the same density as a square one.
    final step = spacing * 1.41421356;
    final extent = size.width + size.height;
    for (var c = -extent; c <= extent; c += step) {
      canvas.drawLine(
        Offset(c, 0),
        Offset(c + size.height, size.height),
        paint,
      );
      canvas.drawLine(
        Offset(c, 0),
        Offset(c - size.height, size.height),
        paint,
      );
    }
  }
  canvas.restore();
}
