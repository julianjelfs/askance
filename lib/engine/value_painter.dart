import 'dart:math' as math;
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
      // zooming magnifies the cells with the picture — and, as they grow,
      // halves them again, so the grid keeps roughly the density chosen.
      paintGrid(
        canvas,
        dest,
        area,
        settings.grid,
        gridLevelAt(settings.gridLevel, view.zoom),
      );
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
///
/// The grid is built by halving. Depth 1 is the picture's two diagonals and
/// its two midlines; every further depth repeats that inside each cell of
/// the one before, so a cell is always the picture's own shape and each
/// depth only adds rules — none moves. Because the cells are alike and
/// aligned, a cell's diagonals chain corner to corner into unbroken rules.
///
/// [level] is continuous: the whole depths are drawn solid and the next one
/// fades in over the fraction, which is what lets the grid follow the zoom
/// without a rule ever appearing all at once. Depth is also attenuated —
/// the coarsest rules are full strength and each finer one lighter — so a
/// dense grid still reads as a hierarchy rather than a mesh.
void paintGrid(
  Canvas canvas,
  Rect image,
  Rect visible,
  GridMode mode,
  double level,
) {
  if (mode == GridMode.off || visible.isEmpty || image.isEmpty) return;
  final size = image.size;
  final deepest = level.ceil();

  canvas.save();
  canvas.clipRect(visible);
  canvas.translate(image.left, image.top);
  for (var depth = 1; depth <= deepest; depth++) {
    final alpha = gridRuleAlpha(depth, level);
    if (alpha <= 0) continue;
    final paint = Paint()
      ..color = AskanceColors.grid.withValues(
        alpha: AskanceColors.grid.a * alpha,
      )
      ..strokeWidth = kRule;

    // The midlines of every cell of the depth above: the rules at the odd
    // multiples of this depth's cell size, the even ones being already drawn.
    final n = StudySettings.divisionsAt(depth);
    final cell = Size(size.width / n, size.height / n);
    for (var i = 1; i < n; i += 2) {
      final x = i * cell.width;
      final y = i * cell.height;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    if (mode != GridMode.diagonals) continue;

    // The diagonals of every cell of the depth above, indexed by the corner
    // they leave the top or left edge from. The even-indexed ones coincide
    // with the coarser depth's diagonals, so only the odd ones are new —
    // except at depth 1, where the picture's own pair is all there is.
    final m = StudySettings.divisionsAt(depth - 1);
    final parent = Size(size.width / m, size.height / m);
    for (var k = -(m - 1); k < m; k++) {
      if (depth > 1 && k.isEven) continue;
      // Falling: x/parent.width - y/parent.height = k.
      canvas.drawLine(
        k >= 0 ? Offset(k * parent.width, 0) : Offset(0, -k * parent.height),
        k >= 0
            ? Offset(size.width, (m - k) * parent.height)
            : Offset((m + k) * parent.width, size.height),
        paint,
      );
      // Rising: x/parent.width + y/parent.height = m + k.
      canvas.drawLine(
        k <= 0
            ? Offset((m + k) * parent.width, 0)
            : Offset(size.width, k * parent.height),
        k <= 0
            ? Offset(0, (m + k) * parent.height)
            : Offset(k * parent.width, size.height),
        paint,
      );
    }
  }
  canvas.restore();
}

/// How deep the grid goes on screen: the chosen [level] at 1×, one depth
/// more for every doubling of [zoom], so a cell on screen stays between one
/// and two of the chosen size however far in the picture is taken.
double gridLevelAt(int level, double zoom) =>
    (level + math.log(zoom) / math.ln2).clamp(1.0, maxGridDepth.toDouble());

/// Deeper than any zoom reaches from the deepest chosen level; bounds the
/// rule count.
const int maxGridDepth = 7;

/// Strength of the rules at [depth] when the grid is drawn to [level], 0–1.
///
/// Two things at once. A rule that has just arrived is half strength and
/// gains as the zoom leaves it behind, so what the zoom has added is lighter
/// than what was there before; and a rule is never lighter than its place
/// from the top, so at 1× the coarsest is always full strength and the
/// chosen grid never looks tentative. The depth still arriving is eased in
/// over the fraction, from nothing.
double gridRuleAlpha(int depth, double level) {
  final behind = level - depth;
  if (behind <= -1) return 0;
  const gain = 1.5;
  final fromBelow = math.min(1.0, 0.5 * math.pow(gain, math.max(0, behind)));
  final fromTop = math.pow(gain, -(depth - 1)).toDouble();
  final settled = math.max(fromBelow, fromTop);
  if (behind >= 0) return settled;
  final t = behind + 1;
  return settled * t * t * (3 - 2 * t);
}
