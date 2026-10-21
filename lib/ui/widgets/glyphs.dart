import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Every icon in the app, drawn rather than taken from a font.
///
/// A browser silently falls back to another font for a symbol the typeface
/// lacks; iOS, Android and macOS do not agree on what to fall back to, and
/// some render an empty box. Drawing them keeps every surface identical, and
/// keeps them all at one stroke weight.
enum Glyph {
  star,
  arrowUpRight,
  copy,
  splitGrip,
  command,
  trash,
  expand,
  back,
  close,
  share,
  camera,
  staircase,
  shapes,
  tint,
  board,
  tone,
  fill,
  dice,
  mono,
}

class GlyphIcon extends StatelessWidget {
  const GlyphIcon(
    this.glyph, {
    super.key,
    required this.size,
    required this.color,
  });

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
      case Glyph.trash:
        _trash(canvas, size);
      case Glyph.expand:
        _expand(canvas, size);
      case Glyph.back:
        _back(canvas, size);
      case Glyph.close:
        _close(canvas, size);
      case Glyph.share:
        _share(canvas, size);
      case Glyph.camera:
        _camera(canvas, size);
      case Glyph.staircase:
        _staircase(canvas, size);
      case Glyph.shapes:
        _shapes(canvas, size);
      case Glyph.tint:
        _tint(canvas, size);
      case Glyph.board:
        _board(canvas, size);
      case Glyph.tone:
        _tone(canvas, size);
      case Glyph.fill:
        _fill(canvas, size);
      case Glyph.dice:
        _dice(canvas, size);
      case Glyph.mono:
        _mono(canvas, size);
    }
  }

  /// The line icons share one weight and round ends.
  Paint _line(double u) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = u * 0.075
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  void _back(Canvas canvas, Size size) {
    final u = size.shortestSide;
    canvas.drawPath(
      Path()
        ..moveTo(u * 0.62, u * 0.2)
        ..lineTo(u * 0.33, u * 0.5)
        ..lineTo(u * 0.62, u * 0.8),
      _line(u),
    );
  }

  void _close(Canvas canvas, Size size) {
    final u = size.shortestSide;
    final p = _line(u);
    canvas.drawLine(Offset(u * 0.25, u * 0.25), Offset(u * 0.75, u * 0.75), p);
    canvas.drawLine(Offset(u * 0.75, u * 0.25), Offset(u * 0.25, u * 0.75), p);
  }

  /// An arrow leaving a tray: the share sheet's own symbol.
  void _share(Canvas canvas, Size size) {
    final u = size.shortestSide;
    final p = _line(u);
    canvas.drawLine(Offset(u * 0.5, u * 0.62), Offset(u * 0.5, u * 0.12), p);
    canvas.drawPath(
      Path()
        ..moveTo(u * 0.3, u * 0.32)
        ..lineTo(u * 0.5, u * 0.12)
        ..lineTo(u * 0.7, u * 0.32),
      p,
    );
    canvas.drawPath(
      Path()
        ..moveTo(u * 0.2, u * 0.54)
        ..lineTo(u * 0.2, u * 0.86)
        ..lineTo(u * 0.8, u * 0.86)
        ..lineTo(u * 0.8, u * 0.54),
      p,
    );
  }

  void _camera(Canvas canvas, Size size) {
    final u = size.shortestSide;
    final p = _line(u);
    canvas.drawPath(
      Path()
        ..moveTo(u * 0.14, u * 0.32)
        ..lineTo(u * 0.3, u * 0.32)
        ..lineTo(u * 0.38, u * 0.2)
        ..lineTo(u * 0.62, u * 0.2)
        ..lineTo(u * 0.7, u * 0.32)
        ..lineTo(u * 0.86, u * 0.32)
        ..lineTo(u * 0.86, u * 0.8)
        ..lineTo(u * 0.14, u * 0.8)
        ..close(),
      p,
    );
    canvas.drawCircle(Offset(u * 0.5, u * 0.55), u * 0.14, p);
  }

  /// Four steps climbing: the value scale, and the app's own mark.
  void _staircase(Canvas canvas, Size size) {
    final u = size.shortestSide;
    final fill = Paint()..color = color;
    const steps = [0.25, 0.42, 0.6, 0.78];
    for (var i = 0; i < steps.length; i++) {
      canvas.drawRect(
        Rect.fromLTRB(
          u * (0.12 + i * 0.2),
          u * (0.88 - steps[i]),
          u * (0.28 + i * 0.2),
          u * 0.88,
        ),
        fill,
      );
    }
  }

  /// A soft-edged mass, the thing the shape controls form.
  void _shapes(Canvas canvas, Size size) {
    final u = size.shortestSide;
    canvas.drawPath(
      Path()
        ..moveTo(u * 0.12, u * 0.78)
        ..cubicTo(u * 0.2, u * 0.3, u * 0.5, u * 0.2, u * 0.62, u * 0.45)
        ..cubicTo(u * 0.72, u * 0.62, u * 0.86, u * 0.6, u * 0.88, u * 0.78)
        ..close(),
      _line(u),
    );
  }

  /// A disc half filled: one hue laid over the greys.
  void _tint(Canvas canvas, Size size) {
    final u = size.shortestSide;
    final centre = Offset(u * 0.5, u * 0.5);
    final r = u * 0.34;
    canvas.drawCircle(centre, r, _line(u));
    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: r),
      -1.5707963,
      3.1415926,
      true,
      Paint()..color = color,
    );
  }

  /// A board ruled into quarters.
  void _board(Canvas canvas, Size size) {
    final u = size.shortestSide;
    final p = _line(u);
    canvas.drawRect(Rect.fromLTRB(u * 0.24, u * 0.12, u * 0.76, u * 0.88), p);
    canvas.drawLine(Offset(u * 0.5, u * 0.12), Offset(u * 0.5, u * 0.88), p);
    canvas.drawLine(Offset(u * 0.24, u * 0.5), Offset(u * 0.76, u * 0.5), p);
  }

  /// A sun: brightness and contrast.
  void _tone(Canvas canvas, Size size) {
    final u = size.shortestSide;
    final p = _line(u);
    final centre = Offset(u * 0.5, u * 0.5);
    canvas.drawCircle(centre, u * 0.17, p);
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      final d = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(centre + d * u * 0.3, centre + d * u * 0.4, p);
    }
  }

  /// A square filled from the bottom: values blocked in over the edges.
  void _fill(Canvas canvas, Size size) {
    final u = size.shortestSide;
    final box = Rect.fromLTRB(u * 0.18, u * 0.18, u * 0.82, u * 0.82);
    canvas.drawRect(
      Rect.fromLTRB(box.left, u * 0.52, box.right, box.bottom),
      Paint()..color = color,
    );
    canvas.drawRect(box, _line(u));
  }

  /// A circle, half dark: colour or black and white.
  void _mono(Canvas canvas, Size size) {
    final u = size.shortestSide;
    final circle = Rect.fromCircle(
      center: Offset(u * 0.5, u * 0.5),
      radius: u * 0.32,
    );
    canvas.drawArc(circle, math.pi / 2, math.pi, true, Paint()..color = color);
    canvas.drawOval(circle, _line(u));
  }

  /// A die showing three: another deal of colours.
  void _dice(Canvas canvas, Size size) {
    final u = size.shortestSide;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(u * 0.16, u * 0.16, u * 0.84, u * 0.84),
        Radius.circular(u * 0.14),
      ),
      _line(u),
    );
    final pip = Paint()..color = color;
    for (final f in const [0.34, 0.5, 0.66]) {
      canvas.drawCircle(Offset(u * f, u * f), u * 0.06, pip);
    }
  }

  /// Four corner brackets pointing outwards: Lucide `maximize`.
  void _expand(Canvas canvas, Size size) {
    final u = size.shortestSide;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = u * 0.13
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.miter;
    const inset = 0.12;
    const arm = 0.28;
    Path corner(double x, double y, double dx, double dy) => Path()
      ..moveTo(u * (x + dx * arm), u * y)
      ..lineTo(u * x, u * y)
      ..lineTo(u * x, u * (y + dy * arm));
    canvas.drawPath(corner(inset, inset, 1, 1), stroke);
    canvas.drawPath(corner(1 - inset, inset, -1, 1), stroke);
    canvas.drawPath(corner(inset, 1 - inset, 1, -1), stroke);
    canvas.drawPath(corner(1 - inset, 1 - inset, -1, -1), stroke);
  }

  void _star(Canvas canvas, Size size) {
    final r = size.shortestSide / 2;
    final centre = Offset(size.width / 2, size.height / 2);
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final radius = i.isEven ? r : r * 0.42;
      final angle = -math.pi / 2 + i * math.pi / 5;
      final point =
          centre + Offset(math.cos(angle) * radius, math.sin(angle) * radius);
      i == 0
          ? path.moveTo(point.dx, point.dy)
          : path.lineTo(point.dx, point.dy);
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
    canvas.drawRect(
      Rect.fromLTWH(u * 0.08, u * 0.08, u * 0.62, u * 0.62),
      stroke,
    );
    canvas.drawRect(
      Rect.fromLTWH(u * 0.3, u * 0.3, u * 0.62, u * 0.62),
      stroke,
    );
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

  void _trash(Canvas canvas, Size size) {
    final u = size.shortestSide;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = u * 0.1
      ..strokeCap = StrokeCap.square;

    // Lid, then handle, then the body tapering slightly, then two ribs.
    canvas.drawLine(
      Offset(u * 0.14, u * 0.26),
      Offset(u * 0.86, u * 0.26),
      stroke,
    );
    canvas.drawPath(
      Path()
        ..moveTo(u * 0.38, u * 0.26)
        ..lineTo(u * 0.38, u * 0.14)
        ..lineTo(u * 0.62, u * 0.14)
        ..lineTo(u * 0.62, u * 0.26),
      stroke,
    );
    canvas.drawPath(
      Path()
        ..moveTo(u * 0.24, u * 0.26)
        ..lineTo(u * 0.3, u * 0.88)
        ..lineTo(u * 0.7, u * 0.88)
        ..lineTo(u * 0.76, u * 0.26),
      stroke,
    );
    canvas.drawLine(
      Offset(u * 0.42, u * 0.4),
      Offset(u * 0.44, u * 0.74),
      stroke,
    );
    canvas.drawLine(
      Offset(u * 0.58, u * 0.4),
      Offset(u * 0.56, u * 0.74),
      stroke,
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
