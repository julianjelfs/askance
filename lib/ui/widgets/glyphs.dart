import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Symbols the design calls for that Archivo does not contain.
///
/// Archivo covers the arrows the buttons use (-> <- and the down arrow) but
/// not the star, the diagonal arrow, the copy mark, the split grip or the
/// command key. A browser silently falls back to another font for those; iOS,
/// Android and macOS do not agree on what to fall back to, and some render an
/// empty box. Drawing them keeps every surface identical.
enum Glyph { star, arrowUpRight, copy, splitGrip, command }

class GlyphIcon extends StatelessWidget {
  const GlyphIcon(this.glyph, {super.key, required this.size, required this.color});

  final Glyph glyph;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(glyph == Glyph.splitGrip ? size * 1.7 : size, size),
    painter: _GlyphPainter(glyph, color),
  );
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.glyph, this.color);

  final Glyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    switch (glyph) {
      case Glyph.star:
        _star(canvas, size);
      case Glyph.arrowUpRight:
        _arrowUpRight(canvas, size);
      case Glyph.copy:
        _copy(canvas, size);
      case Glyph.splitGrip:
        _splitGrip(canvas, size);
      case Glyph.command:
        _command(canvas, size);
    }
  }

  void _star(Canvas canvas, Size size) {
    final r = size.shortestSide / 2;
    final centre = Offset(size.width / 2, size.height / 2);
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final radius = i.isEven ? r : r * 0.42;
      final angle = -math.pi / 2 + i * math.pi / 5;
      final point = centre + Offset(math.cos(angle) * radius, math.sin(angle) * radius);
      i == 0 ? path.moveTo(point.dx, point.dy) : path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path..close(), Paint()..color = color);
  }

  void _arrowUpRight(Canvas canvas, Size size) {
    final u = size.shortestSide;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = u * 0.13
      ..strokeCap = StrokeCap.square;
    final from = Offset(u * 0.18, u * 0.82);
    final to = Offset(u * 0.82, u * 0.18);
    canvas.drawLine(from, to, stroke);
    canvas.drawPath(
      Path()
        ..moveTo(u * 0.36, u * 0.18)
        ..lineTo(to.dx, to.dy)
        ..lineTo(u * 0.82, u * 0.64),
      stroke,
    );
  }

  void _copy(Canvas canvas, Size size) {
    final u = size.shortestSide;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = u * 0.11;
    canvas.drawRect(Rect.fromLTWH(u * 0.08, u * 0.08, u * 0.62, u * 0.62), stroke);
    canvas.drawRect(Rect.fromLTWH(u * 0.3, u * 0.3, u * 0.62, u * 0.62), stroke);
  }

  void _splitGrip(Canvas canvas, Size size) {
    final h = size.height;
    final fill = Paint()..color = color;
    final mid = size.height / 2;
    final w = h * 0.5;
    final gap = h * 0.18;
    // Pointing outwards from the centre, which is the direction it drags.
    canvas.drawPath(
      Path()
        ..moveTo(size.width / 2 - gap, mid - w / 2)
        ..lineTo(size.width / 2 - gap, mid + w / 2)
        ..lineTo(size.width / 2 - gap - w * 0.8, mid)
        ..close(),
      fill,
    );
    canvas.drawPath(
      Path()
        ..moveTo(size.width / 2 + gap, mid - w / 2)
        ..lineTo(size.width / 2 + gap, mid + w / 2)
        ..lineTo(size.width / 2 + gap + w * 0.8, mid)
        ..close(),
      fill,
    );
  }

  void _command(Canvas canvas, Size size) {
    final u = size.shortestSide;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = u * 0.11;
    final r = u * 0.17;
    canvas.drawRect(Rect.fromLTWH(u * 0.3, u * 0.3, u * 0.4, u * 0.4), stroke);
    for (final centre in [
      Offset(u * 0.3, u * 0.3),
      Offset(u * 0.7, u * 0.3),
      Offset(u * 0.3, u * 0.7),
      Offset(u * 0.7, u * 0.7),
    ]) {
      canvas.drawCircle(centre, r, stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _GlyphPainter old) =>
      old.glyph != glyph || old.color != color;
}
