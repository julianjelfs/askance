import 'dart:math' as math;
import 'dart:ui';

import 'lines.dart';

/// A box drawn round something on the picture, to read its proportions:
/// how many times taller it is than wide, or the other way round.
///
/// Level and plumb, never turned, so its sides are the vertical and the
/// horizontal a drawing is measured against. Placed on the whole
/// photograph, as a [BoardLine] is, so re-cropping leaves it round the
/// thing it was drawn round.
class BoardBox {
  const BoardBox(this.rect);

  /// The box spanning [a] and [b], whichever corners they are.
  BoardBox.spanning(Offset a, Offset b) : rect = Rect.fromPoints(a, b);

  /// Fractions of each side of the photograph, left to right and top to
  /// bottom.
  final Rect rect;

  /// The corners in the order [cornerOf] numbers them: top left, top right,
  /// bottom right, bottom left.
  List<Offset> get corners => [
    rect.topLeft,
    rect.topRight,
    rect.bottomRight,
    rect.bottomLeft,
  ];

  /// The corner across from corner [i], which stays put while [i] is
  /// dragged.
  Offset opposite(int i) => corners[(i + 2) % 4];

  /// The box moved by [by], kept inside the photograph without changing its
  /// size.
  BoardBox movedBy(Offset by) {
    final dx = (rect.left + by.dx).clamp(0.0, 1 - rect.width) - rect.left;
    final dy = (rect.top + by.dy).clamp(0.0, 1 - rect.height) - rect.top;
    return BoardBox(rect.shift(Offset(dx, dy)));
  }

  List<double> toJson() => [rect.left, rect.top, rect.right, rect.bottom];

  /// Null for anything that is not four numbers. Held inside the
  /// photograph, which is where it was drawn.
  static BoardBox? fromJson(Object? json) {
    if (json is! List || json.length != 4) return null;
    if (json.any((v) => v is! num || !v.isFinite)) return null;
    double at(int i) => (json[i] as num).toDouble().clamp(0.0, 1.0);
    return BoardBox.spanning(Offset(at(0), at(1)), Offset(at(2), at(3)));
  }

  @override
  bool operator ==(Object other) => other is BoardBox && other.rect == rect;

  @override
  int get hashCode => rect.hashCode;
}

/// Width over height of [box] in pixels of a photograph [photo] in size.
/// Its sides are fractions of the photograph's, so on one that is not
/// square the same fraction across and down are different lengths. Null
/// for a box with no height.
double? boxAspect(BoardBox box, Size photo) {
  final h = box.rect.height * photo.height;
  if (h == 0) return null;
  return box.rect.width * photo.width / h;
}

/// The proportions of [box] as a label, width first and the shorter side
/// 1: "1 : 1.62" for a tall box, "1.62 : 1" for a wide one, "1 : 1" when
/// they round the same.
String? boxRatioLabel(BoardBox box, Size photo) {
  final aspect = boxAspect(box, photo);
  if (aspect == null || aspect == 0) return null;
  return aspect >= 1
      ? '${aspect.toStringAsFixed(2)} : 1'
      : '1 : ${(1 / aspect).toStringAsFixed(2)}';
}

/// Where the dragged corner of a box from [anchor] goes for the pointer at
/// [to] with shift held, on screen: square, as big as the longer of the two
/// ways the pointer has gone, and shrunk to stay within [area]. The picture
/// keeps its proportions on screen, so square here is square on the
/// photograph.
Offset squaredBoxCorner(Offset anchor, Offset to, Rect area) {
  final d = to - anchor;
  final sx = d.dx < 0 ? -1.0 : 1.0;
  final sy = d.dy < 0 ? -1.0 : 1.0;
  var side = math.max(d.dx.abs(), d.dy.abs());
  side = math.min(
    side,
    math.min(
      sx > 0 ? area.right - anchor.dx : anchor.dx - area.left,
      sy > 0 ? area.bottom - anchor.dy : anchor.dy - area.top,
    ),
  );
  return anchor + Offset(sx * math.max(side, 0), sy * math.max(side, 0));
}

/// The corner of one of [boxes] nearest [screen] and within [kLineReach] of
/// it. Later boxes win a tie, since they are drawn on top.
({int box, int corner})? boxCornerAt(
  List<BoardBox> boxes,
  Offset screen,
  Rect crop,
  Rect picture,
) {
  ({int box, int corner})? found;
  var best = kLineReach;
  for (var i = 0; i < boxes.length; i++) {
    final corners = boxes[i].corners;
    for (var c = 0; c < 4; c++) {
      final d = (lineToScreen(corners[c], crop, picture) - screen).distance;
      if (d <= best) {
        best = d;
        found = (box: i, corner: c);
      }
    }
  }
  return found;
}

/// The one of [boxes] with a side nearest [screen] and within [kLineReach]
/// of it. Only the sides: inside a box is free to draw another, a head
/// within a figure.
int? boxEdgeAt(List<BoardBox> boxes, Offset screen, Rect crop, Rect picture) {
  int? found;
  var best = kLineReach;
  for (var i = 0; i < boxes.length; i++) {
    final r = boxToScreen(boxes[i], crop, picture);
    final d = _distanceToOutline(screen, r);
    if (d <= best) {
      best = d;
      found = i;
    }
  }
  return found;
}

/// Where [box] lands on screen when the [crop] of the photograph is drawn
/// into [picture].
Rect boxToScreen(BoardBox box, Rect crop, Rect picture) => Rect.fromPoints(
  lineToScreen(box.rect.topLeft, crop, picture),
  lineToScreen(box.rect.bottomRight, crop, picture),
);

double _distanceToOutline(Offset p, Rect r) {
  final inside = r.contains(p);
  if (inside) {
    return math.min(
      math.min(p.dx - r.left, r.right - p.dx),
      math.min(p.dy - r.top, r.bottom - p.dy),
    );
  }
  final dx = math.max(math.max(r.left - p.dx, 0.0), p.dx - r.right);
  final dy = math.max(math.max(r.top - p.dy, 0.0), p.dy - r.bottom);
  return Offset(dx, dy).distance;
}

/// Draws [boxes] over the picture drawn into [picture] from [crop] of the
/// photograph, clipped to [visible], each side ticked at its middle and
/// quarters like a ruled line. Screen space, like the lines.
void paintBoxes(
  Canvas canvas,
  List<BoardBox> boxes,
  Rect crop,
  Rect picture,
  Rect visible, {
  required Paint paint,
}) {
  if (boxes.isEmpty || visible.isEmpty || picture.isEmpty) return;
  final stroke = Paint()
    ..color = paint.color
    ..strokeWidth = paint.strokeWidth
    ..style = PaintingStyle.stroke
    ..strokeJoin = StrokeJoin.miter;
  canvas.save();
  canvas.clipRect(visible);
  for (final box in boxes) {
    paintBoxOutline(canvas, boxToScreen(box, crop, picture), stroke, paint);
  }
  canvas.restore();
}

/// [r]'s outline in [stroke], with [paintTicks] across each side in
/// [ticks].
void paintBoxOutline(Canvas canvas, Rect r, Paint stroke, Paint ticks) {
  canvas.drawRect(r, stroke);
  paintTicks(canvas, r.topLeft, r.topRight, ticks);
  paintTicks(canvas, r.topRight, r.bottomRight, ticks);
  paintTicks(canvas, r.bottomRight, r.bottomLeft, ticks);
  paintTicks(canvas, r.bottomLeft, r.topLeft, ticks);
}
