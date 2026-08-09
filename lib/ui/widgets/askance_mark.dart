import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// The Askance mark: a disc split down the middle, the photograph still
/// continuous on the left and the same passage flattened into three values on
/// the right, with the accent rule on the boundary. It is the app's own output.
///
/// Drawn rather than bundled as an image so the header, the launcher icons and
/// anywhere else it appears cannot drift apart — `tool/generate_icons.dart`
/// paints every launcher icon with [paintAskanceMark] too.
abstract final class MarkColors {
  static const light = Color(0xFFF8F4F4);

  /// rgb(122,120,120): the Graphite three-step middle band.
  static const mid = Color(0xFF7A7878);
  static const dark = Color(0xFF111010);
  static const accent = Color(0xFFEC3013);
}

/// Width of the split rule as a fraction of the disc's diameter.
const double kMarkRuleFraction = 47 / 664;

/// Paints the mark to fill [disc].
///
/// [minimumRuleWidth] keeps the rule from disappearing at small sizes, where a
/// sub-pixel line would otherwise wash out to a pink smudge.
void paintAskanceMark(Canvas canvas, Rect disc, {double minimumRuleWidth = 1}) {
  canvas.save();
  canvas.clipPath(Path()..addOval(disc));

  final half = disc.width / 2;

  // Left: the photograph, still continuous.
  canvas.drawRect(
    Rect.fromLTWH(disc.left, disc.top, half, disc.height),
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [MarkColors.light, MarkColors.mid, MarkColors.dark],
        stops: [0, 0.5, 1],
      ).createShader(disc),
  );

  // Right: the same passage flattened into three values.
  final band = disc.height / 3;
  const bands = [MarkColors.light, MarkColors.mid, MarkColors.dark];
  for (var i = 0; i < bands.length; i++) {
    canvas.drawRect(
      // The half-pixel overlap stops a seam showing between bands.
      Rect.fromLTWH(disc.center.dx, disc.top + band * i, half, band + 0.5),
      Paint()..color = bands[i],
    );
  }

  final ruleWidth = math.max(disc.width * kMarkRuleFraction, minimumRuleWidth);
  canvas.drawRect(
    Rect.fromLTWH(
      disc.center.dx - ruleWidth / 2,
      disc.top,
      ruleWidth,
      disc.height,
    ),
    Paint()..color = MarkColors.accent,
  );

  canvas.restore();
}

/// The mark at a given size, with nothing behind it.
class AskanceMark extends StatelessWidget {
  const AskanceMark({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _MarkPainter());
}

class _MarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) =>
      paintAskanceMark(canvas, Offset.zero & size);

  @override
  bool shouldRepaint(covariant _MarkPainter oldDelegate) => false;
}
