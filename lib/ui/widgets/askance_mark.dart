import 'package:flutter/widgets.dart';

/// The Askance mark: four steps climbing from graphite to the accent, the
/// value scale the app is built on. The same staircase is the Values tab's
/// icon.
///
/// Drawn rather than bundled as an image so the header, the launcher icons and
/// anywhere else it appears cannot drift apart — `tool/generate_icons.dart`
/// paints every launcher icon with [paintAskanceMark] too.
abstract final class MarkColors {
  static const dark = Color(0xFF1C1B1A);
  static const mid = Color(0xFF5E5A55);
  static const light = Color(0xFFA39E96);
  static const accent = Color(0xFFE2471F);
}

/// Paints the mark to fill [box].
///
/// [minimumRuleWidth] is kept for the icon generator's signature; the steps
/// have no hairline to protect.
void paintAskanceMark(Canvas canvas, Rect box, {double minimumRuleWidth = 1}) {
  const colours = [
    MarkColors.dark,
    MarkColors.mid,
    MarkColors.light,
    MarkColors.accent,
  ];
  // Each step a quarter of the width, each a quarter taller than the last.
  final w = box.width / 4;
  for (var i = 0; i < colours.length; i++) {
    final h = box.height * (i + 1) / 4;
    canvas.drawRect(
      // The quarter-pixel overlap stops a seam showing between steps.
      Rect.fromLTWH(box.left + w * i, box.bottom - h, w + 0.25, h),
      Paint()..color = colours[i],
    );
  }
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
