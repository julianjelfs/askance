import 'dart:math' as math;
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

/// The length of [line] in pixels of a photograph [photo] in size. Its ends
/// are fractions of each side, so on a photograph that is not square the
/// same fraction across and down are different lengths.
double lineLength(BoardLine line, Size photo) {
  final d = line.b - line.a;
  return Offset(d.dx * photo.width, d.dy * photo.height).distance;
}

/// How long each of [lines] is as a multiple of the one at [unit], measured
/// on a photograph [photo] in size. Null when [unit] is out of range or has
/// no length to measure by.
List<double>? lengthsIn(List<BoardLine> lines, int unit, Size photo) {
  if (unit < 0 || unit >= lines.length) return null;
  final by = lineLength(lines[unit], photo);
  if (by == 0) return null;
  return [for (final line in lines) lineLength(line, photo) / by];
}

/// How near, in logical pixels, a click has to be to an end or a line to
/// take hold of it.
const double kLineReach = 8;

/// The angles, in radians, a line snaps to with shift held: every 15
/// degrees, so level and plumb among them.
const double kLineSnap = math.pi / 12;

/// Where the end of a line from [from] towards [to] goes with shift held,
/// in screen space: turned to the nearest multiple of [kLineSnap], as far
/// along as [to] reaches in that direction, and pulled back along it to stay
/// within [area]. The picture keeps its proportions on screen, so an angle
/// here is the same angle on the photograph.
Offset snappedLineEnd(Offset from, Offset to, Rect area) {
  final d = to - from;
  if (d == Offset.zero) return to;
  final angle = (d.direction / kLineSnap).round() * kLineSnap;
  final u = Offset(math.cos(angle), math.sin(angle));
  var t = d.dx * u.dx + d.dy * u.dy;
  if (area.contains(from)) {
    double reach(double p, double v, double lo, double hi) => v > 1e-9
        ? (hi - p) / v
        : v < -1e-9
        ? (lo - p) / v
        : double.infinity;
    t = math.min(
      t,
      math.min(
        reach(from.dx, u.dx, area.left, area.right),
        reach(from.dy, u.dy, area.top, area.bottom),
      ),
    );
  }
  // Level and plumb land exactly so, not a rounding off.
  final along = Offset(
    u.dx.abs() < 1e-9 ? 0 : u.dx * t,
    u.dy.abs() < 1e-9 ? 0 : u.dy * t,
  );
  return from + along;
}

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
    final a = lineToScreen(line.a, crop, picture);
    final b = lineToScreen(line.b, crop, picture);
    canvas.drawLine(a, b, paint);
    paintTicks(canvas, a, b, paint);
  }
  canvas.restore();
}

/// Half the length, in logical pixels, of the tick across the middle of a
/// ruled line.
const double kMidTickReach = 5;

/// Half the length, in logical pixels, of the ticks across a ruled line a
/// quarter of the way from each end.
const double kQuarterTickReach = 4;

/// How much thinner the quarter ticks are than the line, so the middle
/// still reads first.
const double kQuarterTickWeight = 0.6;

/// Short ticks square across the line from [a] to [b] on screen: one at the
/// middle, and thinner ones at each quarter, so halves and quarters can be
/// read off it when judging proportions. Left off a line too short for them
/// to read as marks on it; the quarters need twice the length the middle
/// does.
void paintTicks(Canvas canvas, Offset a, Offset b, Paint paint) {
  final along = b - a;
  final length = along.distance;
  if (length < kMidTickReach * 4) return;
  final normal = Offset(-along.dy / length, along.dx / length);
  void tick(double t, double reach, Paint p) {
    final at = a + along * t;
    canvas.drawLine(at - normal * reach, at + normal * reach, p);
  }

  tick(0.5, kMidTickReach, paint);
  if (length < kMidTickReach * 8) return;
  final thin = Paint()
    ..color = paint.color
    ..strokeWidth = paint.strokeWidth * kQuarterTickWeight
    ..strokeCap = paint.strokeCap;
  tick(0.25, kQuarterTickReach, thin);
  tick(0.75, kQuarterTickReach, thin);
}
