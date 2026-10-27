import 'dart:ui';

/// A straight line ruled over the picture, for a proportion or an alignment
/// the grid does not give: a roofline, the tilt of a head, the run of a
/// shadow.
///
/// Its ends are fractions of each side of the whole photograph, not of the
/// crop: re-cropping changes what the study is of, and a line ruled along a
/// feature should stay on that feature rather than slide to wherever the
/// same fraction of the new crop lands.
class BoardLine {
  const BoardLine(this.a, this.b);

  final Offset a;
  final Offset b;

  /// The line with one end, 0 for [a] and 1 for [b], moved to [to].
  BoardLine withEnd(int end, Offset to) =>
      end == 0 ? BoardLine(to, b) : BoardLine(a, to);

  Offset end(int end) => end == 0 ? a : b;

  List<double> toJson() => [a.dx, a.dy, b.dx, b.dy];

  /// Null for anything that is not four numbers. The ends are held inside
  /// the photograph, which is where they were ruled.
  static BoardLine? fromJson(Object? json) {
    if (json is! List || json.length != 4) return null;
    if (json.any((v) => v is! num || !v.isFinite)) return null;
    double at(int i) => (json[i] as num).toDouble().clamp(0.0, 1.0);
    return BoardLine(Offset(at(0), at(1)), Offset(at(2), at(3)));
  }

  @override
  bool operator ==(Object other) =>
      other is BoardLine && other.a == a && other.b == b;

  @override
  int get hashCode => Object.hash(a, b);
}

/// Where a point on the photograph, as [BoardLine] measures it, lands when
/// the [crop] of it is drawn into [picture].
Offset lineToScreen(Offset point, Rect crop, Rect picture) => Offset(
  picture.left + (point.dx - crop.left) / crop.width * picture.width,
  picture.top + (point.dy - crop.top) / crop.height * picture.height,
);

/// The point on the photograph under [screen], the inverse of
/// [lineToScreen].
Offset screenToLine(Offset screen, Rect crop, Rect picture) => Offset(
  crop.left + (screen.dx - picture.left) / picture.width * crop.width,
  crop.top + (screen.dy - picture.top) / picture.height * crop.height,
);

/// How near, in logical pixels, a click has to be to an end or a line to
/// take hold of it.
const double kLineReach = 8;

/// The end of one of [lines] nearest [screen] and within [kLineReach] of it,
/// as the line's index and which end. Later lines win a tie, since they are
/// drawn on top.
({int line, int end})? lineEndAt(
  List<BoardLine> lines,
  Offset screen,
  Rect crop,
  Rect picture,
) {
  ({int line, int end})? found;
  var best = kLineReach;
  for (var i = 0; i < lines.length; i++) {
    for (var end = 0; end < 2; end++) {
      final d =
          (lineToScreen(lines[i].end(end), crop, picture) - screen).distance;
      if (d <= best) {
        best = d;
        found = (line: i, end: end);
      }
    }
  }
  return found;
}

/// The one of [lines] nearest [screen] and within [kLineReach] of it.
int? lineAt(List<BoardLine> lines, Offset screen, Rect crop, Rect picture) {
  int? found;
  var best = kLineReach;
  for (var i = 0; i < lines.length; i++) {
    final d = _distanceToSegment(
      screen,
      lineToScreen(lines[i].a, crop, picture),
      lineToScreen(lines[i].b, crop, picture),
    );
    if (d <= best) {
      best = d;
      found = i;
    }
  }
  return found;
}

double _distanceToSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final length2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (length2 == 0) return (p - a).distance;
  final ap = p - a;
  final t = ((ap.dx * ab.dx + ap.dy * ab.dy) / length2).clamp(0.0, 1.0);
  return (p - (a + ab * t)).distance;
}

/// Rules [lines] over the picture drawn into [picture] from [crop] of the
/// photograph, clipped to [visible]. Screen space, like the grid, so the
/// weight never rides the zoom.
void paintLines(
  Canvas canvas,
  List<BoardLine> lines,
  Rect crop,
  Rect picture,
  Rect visible, {
  required Paint paint,
}) {
  if (lines.isEmpty || visible.isEmpty || picture.isEmpty) return;
  canvas.save();
  canvas.clipRect(visible);
  for (final line in lines) {
    canvas.drawLine(
      lineToScreen(line.a, crop, picture),
      lineToScreen(line.b, crop, picture),
      paint,
    );
  }
  canvas.restore();
}
