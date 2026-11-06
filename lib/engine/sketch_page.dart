import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// Finding the sketchbook page in a photograph of the drawing, and squaring
/// it up, so the drawing arrives straight and cropped to its page.
///
/// The page is taken to be the paper: lighter than whatever it lies on, and
/// bounded by four straight edges. A photograph without them, or one the
/// page runs out of, is left as it is.

/// The long side, in pixels, the photograph is shrunk to before the page is
/// looked for. Plenty to place the corners within a fraction of a percent.
const int kPageSearchSide = 512;

/// Looks for the page in [photo]. Its corners, as fractions of each side of
/// the photograph, clockwise on screen from the top left; null when no page
/// stands out from its surroundings.
Future<List<Offset>?> findPage(Image photo) async {
  final k = math.min(
    1.0,
    kPageSearchSide / math.max(photo.width, photo.height),
  );
  final width = math.max(1, (photo.width * k).round());
  final height = math.max(1, (photo.height * k).round());
  final recorder = PictureRecorder();
  Canvas(recorder).drawImageRect(
    photo,
    Offset.zero & Size(photo.width.toDouble(), photo.height.toDouble()),
    Offset.zero & Size(width.toDouble(), height.toDouble()),
    Paint()..filterQuality = FilterQuality.medium,
  );
  final picture = recorder.endRecording();
  final small = await picture.toImage(width, height);
  picture.dispose();
  final data = await small.toByteData(format: ImageByteFormat.rawRgba);
  small.dispose();
  if (data == null) return null;
  return findPageInPixels(data.buffer.asUint8List(), width, height);
}

/// [findPage] on raw RGBA pixels.
///
/// The page is found by its edges, not by how light it is: a shadow across
/// it can leave the paper in it darker than the lit table beside it, and
/// charcoal is darker than both, so no one level of brightness picks out
/// the paper. What a shadow leaves alone is the step at the edge of the
/// paper as a ratio, so brightness is taken as a logarithm, and the page is
/// the four straight lines along which it steps up the most, from outside
/// to in.
List<Offset>? findPageInPixels(Uint8List rgba, int width, int height) {
  final n = width * height;
  if (width < 16 || height < 16) return null;

  final logOf = Float32List(256);
  for (var i = 0; i < 256; i++) {
    logOf[i] = math.log(i + 8);
  }
  var lum = Float32List(n);
  for (var i = 0; i < n; i++) {
    lum[i] =
        logOf[(rgba[i * 4] * 77 +
                rgba[i * 4 + 1] * 150 +
                rgba[i * 4 + 2] * 29) >>
            8];
  }
  // Softened so grain, paper texture and the weave of a carpet do not read
  // as edges.
  lum = _boxBlur(_boxBlur(lum, width, height), width, height);
  final edges = _Edges(lum, width, height);

  final lines = _houghLines(edges);
  if (lines.length < 4) return null;

  final size = math.min(width, height);
  final margin = math.max(2.0, math.max(width, height) * 0.01);
  List<_Line>? best;
  var bestScore = 0.0;
  // Opposite sides: lines near enough parallel, well apart, each on the
  // light side of the other, facing each other across the page.
  final middle = Offset(width / 2, height / 2);
  final feet = [for (final l in lines) l.foot(middle)];
  final pairs = <(int, int)>[];
  for (var i = 0; i < lines.length; i++) {
    for (var j = i + 1; j < lines.length; j++) {
      if (math.cos(lines[i].theta - lines[j].theta) >
          -math.cos(25 * math.pi / 180)) {
        continue;
      }
      final across = lines[i].signedAt(feet[j]);
      if (across < size * 0.2 || lines[j].signedAt(feet[i]) < size * 0.2) {
        continue;
      }
      pairs.add((i, j));
    }
  }
  for (var p = 0; p < pairs.length; p++) {
    for (var q = p + 1; q < pairs.length; q++) {
      final (a, b) = pairs[p];
      final (c, d) = pairs[q];
      final turn = _angleBetween(lines[a], lines[c]);
      if (turn < 60) continue;
      final corners = [
        lines[a].meet(lines[c]),
        lines[a].meet(lines[d]),
        lines[b].meet(lines[d]),
        lines[b].meet(lines[c]),
      ];
      if (corners.any((c) => c == null)) continue;
      final quad = corners.cast<Offset>();
      if (!_fits(quad, width, height, margin) || !_convex(quad)) continue;
      final area = _area(quad).abs();
      if (area < n * 0.1) continue;
      final support = _support(quad, edges);
      if (support == null) continue;
      // Of pages backed about as well by their edges, the bigger: the
      // paper rather than a box drawn on it.
      final score = support + 0.15 * area / n;
      if (score > bestScore) {
        bestScore = score;
        // Its sides in turn, each running from the corner before.
        best = [lines[a], lines[d], lines[b], lines[c]];
      }
    }
  }
  if (best == null) return null;

  // The edge of the paper is the outermost of the straight edges that face
  // in: one just inside it and along it is on the paper, the holes of a
  // spiral binding, a border drawn round the drawing, or tape. Such an edge
  // can outvote the paper's own, half hidden as that may be behind the
  // binding, so each side is pushed out to the farthest line near it that
  // still shows along a good share of its length.
  final found = _pushOut(_corners(best), edges, size * 0.12);
  if (!_fits(found, width, height, margin) || !_convex(found)) return null;

  final refined = _refine(found, edges);
  if (!_fits(refined, width, height, margin) || !_convex(refined)) {
    return null;
  }
  return [
    for (final c in _clockwiseFromTopLeft(refined))
      Offset(c.dx / width, c.dy / height),
  ];
}

/// How steeply, in log brightness per pixel, the light has to change for
/// the change to count as an edge.
const double _kEdge = 0.05;

/// Within how much, as the cosine of the angle, the light has to rise
/// straight into the page for an edge to count as one of its sides.
const double _kFacing = 0.9;

/// The gradient of log brightness at each pixel.
class _Edges {
  _Edges(Float32List lum, this.width, this.height)
    : gx = Float32List(width * height),
      gy = Float32List(width * height),
      mag = Float32List(width * height) {
    for (var y = 1; y < height - 1; y++) {
      for (var x = 1; x < width - 1; x++) {
        final i = y * width + x;
        final tl = lum[i - width - 1],
            t = lum[i - width],
            tr = lum[i - width + 1];
        final l = lum[i - 1], r = lum[i + 1];
        final bl = lum[i + width - 1],
            b = lum[i + width],
            br = lum[i + width + 1];
        final dx = ((tr + 2 * r + br) - (tl + 2 * l + bl)) / 8;
        final dy = ((bl + 2 * b + br) - (tl + 2 * t + tr)) / 8;
        gx[i] = dx;
        gy[i] = dy;
        mag[i] = math.sqrt(dx * dx + dy * dy);
      }
    }
  }

  final int width;
  final int height;
  final Float32List gx;
  final Float32List gy;
  final Float32List mag;

  /// Whether the light rises steeply toward [inward] at or within two
  /// pixels across of the pixel holding [p].
  bool facing(Offset p, Offset inward) {
    for (var k = -2; k <= 2; k++) {
      final q = p + inward * k.toDouble();
      final x = q.dx.floor(), y = q.dy.floor();
      if (x < 1 || y < 1 || x >= width - 1 || y >= height - 1) continue;
      final i = y * width + x;
      final m = mag[i];
      if (m < _kEdge) continue;
      if ((gx[i] * inward.dx + gy[i] * inward.dy) / m > _kFacing) return true;
    }
    return false;
  }
}

/// A straight line: the points p with p . (cos theta, sin theta) = rho.
class _Line {
  _Line(this.theta, this.rho) : c = math.cos(theta), s = math.sin(theta);

  /// The line through [a] and [b].
  factory _Line.through(Offset a, Offset b) {
    final theta = math.atan2(b.dx - a.dx, -(b.dy - a.dy));
    return _Line(theta, a.dx * math.cos(theta) + a.dy * math.sin(theta));
  }
  final double theta;
  final double rho;
  final double c;
  final double s;

  /// Positive on the side the normal points to: for an edge, the light
  /// side.
  double signedAt(Offset p) => p.dx * c + p.dy * s - rho;

  /// The point on the line nearest [p].
  Offset foot(Offset p) => p - Offset(c, s) * signedAt(p);
  double distanceTo(Offset p) => signedAt(p).abs();

  Offset? meet(_Line o) {
    final det = c * o.s - s * o.c;
    if (det.abs() < 1e-6) return null;
    return Offset((rho * o.s - s * o.rho) / det, (c * o.rho - rho * o.c) / det);
  }
}

/// The angle between two lines, in degrees, 0 to 90.
double _angleBetween(_Line a, _Line b) {
  var d = ((a.theta - b.theta) * 180 / math.pi).abs() % 180;
  if (d > 90) d = 180 - d;
  return d;
}

/// The strongest straight edges in [edges], at most [count], by a Hough
/// transform: each edge pixel votes for the lines through it running
/// across its gradient. Its vote grows with its steepness only up to a
/// point, so the hard edges of a dark drawing do not drown out the gentler
/// step from table to paper.
List<_Line> _houghLines(_Edges edges, {int count = 24}) {
  final width = edges.width, height = edges.height;
  // Oriented: a line is kept apart from one it overlies where the light
  // steps the other way, as the edge of a page from the edge of a drawing
  // just inside it.
  const bins = 360;
  final reach = math.sqrt(width * width + height * height).ceil();
  final span = 2 * reach + 1;
  final acc = Float32List(bins * span);
  final cos = Float64List(bins), sin = Float64List(bins);
  for (var t = 0; t < bins; t++) {
    cos[t] = math.cos(t * 2 * math.pi / bins);
    sin[t] = math.sin(t * 2 * math.pi / bins);
  }
  for (var y = 1; y < height - 1; y++) {
    for (var x = 1; x < width - 1; x++) {
      final i = y * width + x;
      final m = edges.mag[i];
      if (m < _kEdge) continue;
      final at = math.atan2(edges.gy[i], edges.gx[i]) * bins / (2 * math.pi);
      final centre = at.round();
      final vote = math.min(m, _kEdge * 3);
      for (var d = -2; d <= 2; d++) {
        final t = (centre + d) % bins;
        final rho = (x + 0.5) * cos[t] + (y + 0.5) * sin[t];
        acc[t * span + rho.round() + reach] += vote;
      }
    }
  }

  final lines = <_Line>[];
  var top = 0.0;
  while (lines.length < count) {
    var at = -1;
    var most = 0.0;
    for (var i = 0; i < acc.length; i++) {
      if (acc[i] > most) {
        most = acc[i];
        at = i;
      }
    }
    if (at < 0) break;
    if (lines.isEmpty) top = most;
    if (most < top * 0.08) break;
    final t = at ~/ span;
    final r = at % span - reach;
    final line = _Line(t * 2 * math.pi / bins, r.toDouble());
    // A long edge also gathers votes a few degrees either side of itself,
    // pivoting about its middle: those are the same edge again.
    final foot = line.foot(Offset(width / 2, height / 2));
    final again = lines.any(
      (l) =>
          math.cos(l.theta - line.theta) > math.cos(8 * math.pi / 180) &&
          l.distanceTo(foot) < 3,
    );
    if (!again) lines.add(line);
    // The same line, near enough, is not found twice.
    for (var dt = -4; dt <= 4; dt++) {
      final tt = (t + dt + bins) % bins;
      for (var dr = -4; dr <= 4; dr++) {
        final k = r + dr + reach;
        if (k >= 0 && k < span) acc[tt * span + k] = 0;
      }
    }
  }
  return lines;
}

/// [quad] with each side moved out to the farthest line, within [reach]
/// at either end, along which the light steps up into it for at least a
/// quarter of its length, spread along it; then to whichever line within
/// three pixels of that the light rises across most steeply.
List<Offset> _pushOut(List<Offset> quad, _Edges edges, double reach) {
  final centre = (quad[0] + quad[1] + quad[2] + quad[3]) / 4;
  final sides = <_Line>[];
  final limit = reach.floor();
  for (var i = 0; i < 4; i++) {
    final a = quad[i], b = quad[(i + 1) % 4];
    final along = b - a;
    var out = Offset(-along.dy, along.dx) / along.distance;
    if ((centre - a).dx * out.dx + (centre - a).dy * out.dy > 0) out = -out;
    double share(int d0, int d1, {bool spread = false}) => _shareAlong(
      a + out * d0.toDouble(),
      b + out * d1.toDouble(),
      -out,
      edges,
      spread: spread,
    );

    var best = (0, 0);
    var bestOut = 0;
    for (var d0 = 0; d0 <= limit; d0++) {
      for (var d1 = 0; d1 <= limit; d1++) {
        if (d0 + d1 <= bestOut) continue;
        if (share(d0, d1, spread: true) < 0.25) continue;
        best = (d0, d1);
        bestOut = d0 + d1;
      }
    }
    // Settled on the steepest of the lines about it, which runs down the
    // middle of the blurred step rather than along its outer fringe.
    var (d0, d1) = best;
    var top = double.negativeInfinity;
    for (var e0 = d0 - 3; e0 <= d0 + 3; e0++) {
      for (var e1 = d1 - 3; e1 <= d1 + 3; e1++) {
        final s = _riseAlong(
          a + out * e0.toDouble(),
          b + out * e1.toDouble(),
          -out,
          edges,
        );
        if (s > top) {
          top = s;
          best = (e0, e1);
        }
      }
    }
    (d0, d1) = best;
    sides.add(_Line.through(a + out * d0.toDouble(), b + out * d1.toDouble()));
  }
  return _corners(sides);
}

/// How steeply, summed along the line from [a] to [b] away from its ends,
/// the light rises toward [inward] on the line itself.
double _riseAlong(Offset a, Offset b, Offset inward, _Edges edges) {
  final along = b - a;
  final steps = along.distance.floor();
  if (steps < 1) return 0;
  var rise = 0.0;
  for (var k = (steps * 0.05).ceil(); k <= steps * 0.95; k++) {
    final p = a + along * (k / steps);
    final x = p.dx.floor(), y = p.dy.floor();
    if (x < 1 || y < 1 || x >= edges.width - 1 || y >= edges.height - 1) {
      continue;
    }
    final i = y * edges.width + x;
    rise += math.max(0, edges.gx[i] * inward.dx + edges.gy[i] * inward.dy);
  }
  return rise / steps;
}

/// The share of the line from [a] to [b], away from its ends, along which
/// the light steps up toward [inward]. With [spread], nothing unless each
/// third of it shows the step for some of its length: a line that only
/// crosses an edge, pivoting off it at one end, is not that edge.
double _shareAlong(
  Offset a,
  Offset b,
  Offset inward,
  _Edges edges, {
  bool spread = false,
}) {
  final along = b - a;
  final steps = along.distance.floor();
  if (steps < 1) return 0;
  final hit = [0, 0, 0], seen = [0, 0, 0];
  for (var k = (steps * 0.05).ceil(); k <= steps * 0.95; k++) {
    final third = math.min(2, k * 3 ~/ steps);
    seen[third]++;
    if (edges.facing(a + along * (k / steps), inward)) hit[third]++;
  }
  final total = seen[0] + seen[1] + seen[2];
  if (total == 0) return 0;
  if (spread) {
    for (var t = 0; t < 3; t++) {
      if (seen[t] == 0 || hit[t] / seen[t] < 0.15) return 0;
    }
  }
  return (hit[0] + hit[1] + hit[2]) / total;
}

/// Whether [quad] lies within the photograph, clear of its edges by
/// [margin]: a page running out of it has not all its corners there to be
/// squared up by.
bool _fits(List<Offset> quad, int width, int height, double margin) =>
    quad.every(
      (c) =>
          c.dx >= margin &&
          c.dy >= margin &&
          c.dx <= width - margin &&
          c.dy <= height - margin,
    );

/// The share of [quad]'s outline along which the light steps up into it,
/// or null if any side has too little of that to be an edge of a page.
/// Away from the corners, where paper is often rounded or dog-eared.
double? _support(List<Offset> quad, _Edges edges) {
  var total = 0.0;
  for (var i = 0; i < 4; i++) {
    final share = _sideShare(quad[i], quad[(i + 1) % 4], quad, edges);
    // A side can be hidden for much of its length, behind the binding or
    // lost in a shadow, so long as the page as a whole is plainly there.
    if (share == null || share < 0.15) return null;
    total += share;
  }
  return total / 4 < 0.5 ? null : total / 4;
}

/// The share of the side of [quad] from [a] to [b] along which the light
/// steps up into [quad].
double? _sideShare(Offset a, Offset b, List<Offset> quad, _Edges edges) {
  final centre = (quad[0] + quad[1] + quad[2] + quad[3]) / 4;
  final along = b - a;
  final length = along.distance;
  if (length < 1) return null;
  var inward = Offset(-along.dy, along.dx) / length;
  if ((centre - a).dx * inward.dx + (centre - a).dy * inward.dy < 0) {
    inward = -inward;
  }
  return _shareAlong(a, b, inward, edges);
}

/// The corners of the quadrilateral with [sides] in turn, each corner
/// where a side meets the one before it.
List<Offset> _corners(List<_Line> sides) => [
  for (var i = 0; i < 4; i++)
    sides[(i + 3) % 4].meet(sides[i]) ?? const Offset(-1, -1),
];

/// [quad] with each side fitted to the edge pixels along it, weighted by
/// steepness, and its corners put back where the fitted sides meet.
List<Offset> _refine(List<Offset> quad, _Edges edges) {
  final width = edges.width;
  final centre = (quad[0] + quad[1] + quad[2] + quad[3]) / 4;
  final sides = <_Line>[];
  for (var i = 0; i < 4; i++) {
    final a = quad[i], b = quad[(i + 1) % 4];
    final along = b - a;
    final length = along.distance;
    final dir = along / length;
    var inward = Offset(-dir.dy, dir.dx);
    if ((centre - a).dx * inward.dx + (centre - a).dy * inward.dy < 0) {
      inward = -inward;
    }
    var w = 0.0, sx = 0.0, sy = 0.0;
    final points = <(Offset, double)>[];
    for (var k = (length * 0.05).ceil(); k <= length * 0.95; k++) {
      final on = a + dir * k.toDouble();
      for (var d = -3; d <= 3; d++) {
        final p = on + inward * d.toDouble();
        final x = p.dx.floor(), y = p.dy.floor();
        if (x < 1 || y < 1 || x >= width - 1 || y >= edges.height - 1) {
          continue;
        }
        final j = y * width + x;
        final m = edges.mag[j];
        if (m < _kEdge) continue;
        if ((edges.gx[j] * inward.dx + edges.gy[j] * inward.dy) / m <
            _kFacing) {
          continue;
        }
        final c = Offset(x + 0.5, y + 0.5);
        points.add((c, m));
        w += m;
        sx += c.dx * m;
        sy += c.dy * m;
      }
    }
    final normal = Offset(-dir.dy, dir.dx);
    if (points.length < 10) {
      sides.add(
        _Line(
          math.atan2(normal.dy, normal.dx),
          a.dx * normal.dx + a.dy * normal.dy,
        ),
      );
      continue;
    }
    final cx = sx / w, cy = sy / w;
    var sxx = 0.0, syy = 0.0, sxy = 0.0;
    for (final (p, m) in points) {
      final dx = p.dx - cx, dy = p.dy - cy;
      sxx += m * dx * dx;
      syy += m * dy * dy;
      sxy += m * dx * dy;
    }
    // The fitted line runs along the principal direction; its normal is
    // square to that.
    final angle = 0.5 * math.atan2(2 * sxy, sxx - syy) + math.pi / 2;
    sides.add(_Line(angle, cx * math.cos(angle) + cy * math.sin(angle)));
  }
  final refined = <Offset>[];
  for (var i = 0; i < 4; i++) {
    final at = sides[(i + 3) % 4].meet(sides[i]);
    // Sides that will not meet near the corner they came from leave it.
    refined.add(at == null || (at - quad[i]).distance > 10 ? quad[i] : at);
  }
  return refined;
}

/// A phone's main camera, about 26mm in 35mm terms: its focal length as a
/// share of the photograph's diagonal.
const double kPhoneFocal = 0.6;

/// The width over the height of the page whose corners, clockwise from the
/// top left, lie at [corners] in a photograph of [size] (both in pixels).
///
/// Read through the perspective the photograph was taken at, after Zhang
/// and He, "Whiteboard scanning and image enhancement" (2007): a page shot
/// at a slant looks shorter along the slant than it is, and the drawing
/// laid over the picture must keep its true proportions. The corners alone
/// rarely pin down the lens, so a phone's is assumed: a guess a quarter out
/// costs a few percent at a steep slant, where the sides alone are out by
/// over ten.
double pageAspect(List<Offset> corners, Size size) {
  final centre = size.center(Offset.zero);
  List<double> h(Offset p) => [p.dx - centre.dx, p.dy - centre.dy, 1];
  final m1 = h(corners[0]);
  final m2 = h(corners[1]);
  final m4 = h(corners[2]);
  final m3 = h(corners[3]);

  final top = (corners[1] - corners[0]).distance;
  final bottom = (corners[2] - corners[3]).distance;
  final left = (corners[3] - corners[0]).distance;
  final right = (corners[2] - corners[1]).distance;
  final sides = (top + bottom) / (left + right);

  final c14 = _cross(m1, m4);
  final k2 = _dot(c14, m3) / _dot(_cross(m2, m4), m3);
  final k3 = _dot(c14, m2) / _dot(_cross(m3, m4), m2);
  if (!k2.isFinite || !k3.isFinite) return sides;
  final n2 = [for (var i = 0; i < 3; i++) k2 * m2[i] - m1[i]];
  final n3 = [for (var i = 0; i < 3; i++) k3 * m3[i] - m1[i]];
  final f2 =
      kPhoneFocal *
      kPhoneFocal *
      (size.width * size.width + size.height * size.height);
  final across = (n2[0] * n2[0] + n2[1] * n2[1]) / f2 + n2[2] * n2[2];
  final down = (n3[0] * n3[0] + n3[1] * n3[1]) / f2 + n3[2] * n3[2];
  final aspect = math.sqrt(across / down);
  return aspect.isFinite && aspect > 0 ? aspect : sides;
}

/// The page of [photo] whose corners are [page] (as [findPage] gives them),
/// squared up into an image of its own proportions, its long side no more
/// than [maxSide].
Future<Image> straightenPage(
  Image photo,
  List<Offset> page, {
  int maxSide = 2400,
}) async {
  final size = Size(photo.width.toDouble(), photo.height.toDouble());
  final corners = [
    for (final c in page) Offset(c.dx * size.width, c.dy * size.height),
  ];
  final aspect = pageAspect(corners, size);
  // About as many pixels as the page covers in the photograph.
  final across =
      ((corners[1] - corners[0]).distance +
          (corners[2] - corners[3]).distance) /
      2;
  final down =
      ((corners[3] - corners[0]).distance +
          (corners[2] - corners[1]).distance) /
      2;
  var height = math.sqrt(across * down / aspect);
  var width = height * aspect;
  final k = math.min(1.0, maxSide / math.max(width, height));
  width = math.max(1, (width * k).roundToDouble());
  height = math.max(1, (height * k).roundToDouble());

  final h = _homography(corners, [
    Offset.zero,
    Offset(width, 0),
    Offset(width, height),
    Offset(0, height),
  ]);
  final recorder = PictureRecorder();
  final canvas = Canvas(recorder)
    ..transform(
      Float64List.fromList([
        h[0], h[3], 0, h[6], //
        h[1], h[4], 0, h[7], //
        0, 0, 1, 0, //
        h[2], h[5], 0, h[8], //
      ]),
    );
  canvas.drawImage(
    photo,
    Offset.zero,
    Paint()..filterQuality = FilterQuality.medium,
  );
  final picture = recorder.endRecording();
  final straight = await picture.toImage(width.round(), height.round());
  picture.dispose();
  return straight;
}

/// The 3x3 projective map, row by row, taking each of [from] to the same
/// place in [to].
List<double> _homography(List<Offset> from, List<Offset> to) {
  final a = List.generate(8, (_) => List<double>.filled(9, 0));
  for (var i = 0; i < 4; i++) {
    final x = from[i].dx, y = from[i].dy, u = to[i].dx, v = to[i].dy;
    a[i * 2].setAll(0, [x, y, 1, 0, 0, 0, -u * x, -u * y, u]);
    a[i * 2 + 1].setAll(0, [0, 0, 0, x, y, 1, -v * x, -v * y, v]);
  }
  for (var col = 0; col < 8; col++) {
    var pivot = col;
    for (var row = col + 1; row < 8; row++) {
      if (a[row][col].abs() > a[pivot][col].abs()) pivot = row;
    }
    final swap = a[col];
    a[col] = a[pivot];
    a[pivot] = swap;
    final p = a[col][col];
    for (var row = 0; row < 8; row++) {
      if (row == col) continue;
      final f = a[row][col] / p;
      for (var k = col; k < 9; k++) {
        a[row][k] -= f * a[col][k];
      }
    }
  }
  return [for (var i = 0; i < 8; i++) a[i][8] / a[i][i], 1];
}

List<double> _cross(List<double> a, List<double> b) => [
  a[1] * b[2] - a[2] * b[1],
  a[2] * b[0] - a[0] * b[2],
  a[0] * b[1] - a[1] * b[0],
];

double _dot(List<double> a, List<double> b) =>
    a[0] * b[0] + a[1] * b[1] + a[2] * b[2];

Float32List _boxBlur(Float32List src, int width, int height) {
  final out = Float32List(src.length);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      var sum = 0.0;
      var count = 0;
      for (var dy = -1; dy <= 1; dy++) {
        final yy = y + dy;
        if (yy < 0 || yy >= height) continue;
        for (var dx = -1; dx <= 1; dx++) {
          final xx = x + dx;
          if (xx < 0 || xx >= width) continue;
          sum += src[yy * width + xx];
          count++;
        }
      }
      out[y * width + x] = sum / count;
    }
  }
  return out;
}

double _turn(Offset o, Offset a, Offset b) =>
    (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);

double _area(List<Offset> p) {
  var a = 0.0;
  for (var i = 0; i < p.length; i++) {
    final q = p[(i + 1) % p.length];
    a += p[i].dx * q.dy - q.dx * p[i].dy;
  }
  return a / 2;
}

bool _convex(List<Offset> p) {
  var sign = 0;
  for (var i = 0; i < p.length; i++) {
    final t = _turn(p[i], p[(i + 1) % p.length], p[(i + 2) % p.length]);
    if (t == 0) return false;
    final s = t > 0 ? 1 : -1;
    if (sign == 0) sign = s;
    if (s != sign) return false;
  }
  return true;
}

/// [p] clockwise on screen (y down), starting at the corner nearest the
/// top left, so the page comes out the way up it was photographed.
List<Offset> _clockwiseFromTopLeft(List<Offset> p) {
  final q = _area(p) < 0 ? p.reversed.toList() : [...p];
  var start = 0;
  for (var i = 1; i < 4; i++) {
    if (q[i].dx + q[i].dy < q[start].dx + q[start].dy) start = i;
  }
  return [for (var i = 0; i < 4; i++) q[(start + i) % 4]];
}
