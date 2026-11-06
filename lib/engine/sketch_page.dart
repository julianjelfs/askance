import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// Finding the sketchbook page in a photograph of the drawing, and squaring
/// it up, so the drawing arrives straight and cropped to its page.
///
/// The page is taken to be the paper: lighter than whatever it lies on. A
/// photograph without that contrast, or one the page already fills, is left
/// as it is.

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
List<Offset>? findPageInPixels(Uint8List rgba, int width, int height) {
  final n = width * height;
  if (n < 64) return null;

  // Luminance, softened so grain and paper texture do not speckle the split.
  final raw = Uint8List(n);
  for (var i = 0; i < n; i++) {
    raw[i] =
        (rgba[i * 4] * 77 + rgba[i * 4 + 1] * 150 + rgba[i * 4 + 2] * 29) >> 8;
  }
  final grey = _boxBlur(raw, width, height);

  // Paper from not-paper, split where the two are told apart best.
  final split = _otsu(grey);
  if (split == null) return null;
  var bright = Uint8List(n);
  for (var i = 0; i < n; i++) {
    bright[i] = grey[i] > split ? 1 : 0;
  }
  // Closed over the drawing, so a stroke run to the edge of the paper does
  // not cut the page in two.
  final r = math.max(2, (math.max(width, height) / 170).round());
  bright = _erode(_dilate(bright, width, height, r), width, height, r);

  // Whatever dark reaches the border is what the page lies on. The rest is
  // the page, the drawing on it, and anything else lying about.
  final outside = Uint8List(n);
  final stack = <int>[];
  void seed(int i) {
    if (bright[i] == 0 && outside[i] == 0) {
      outside[i] = 1;
      stack.add(i);
    }
  }

  for (var x = 0; x < width; x++) {
    seed(x);
    seed((height - 1) * width + x);
  }
  for (var y = 0; y < height; y++) {
    seed(y * width);
    seed(y * width + width - 1);
  }
  _flood(stack, width, height, (i) => bright[i] == 0 && outside[i] == 0, (i) {
    outside[i] = 1;
  });

  // The page is the biggest piece of what is left.
  final label = Int32List(n);
  var best = 0;
  var bestArea = 0;
  var next = 0;
  for (var i = 0; i < n; i++) {
    if (outside[i] == 1 || label[i] != 0) continue;
    final id = ++next;
    label[i] = id;
    var area = 0;
    stack.add(i);
    _flood(stack, width, height, (j) => outside[j] == 0 && label[j] == 0, (j) {
      label[j] = id;
    }, onVisit: () => area++);
    if (area > bestArea) {
      bestArea = area;
      best = id;
    }
  }
  if (best == 0 || bestArea < n * 0.1) return null;

  // Its outline, from the extremes of each row and column, and its area
  // with any holes in it filled.
  final rowMin = Int32List(height)..fillRange(0, height, -1);
  final rowMax = Int32List(height);
  final colMin = Int32List(width)..fillRange(0, width, -1);
  final colMax = Int32List(width);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      if (label[y * width + x] != best) continue;
      if (rowMin[y] < 0) rowMin[y] = x;
      rowMax[y] = x;
      if (colMin[x] < 0) colMin[x] = y;
      colMax[x] = y;
    }
  }
  final edge = <Offset>[];
  var filled = 0.0;
  for (var y = 0; y < height; y++) {
    if (rowMin[y] < 0) continue;
    edge
      ..add(Offset(rowMin[y].toDouble(), y + 0.5))
      ..add(Offset(rowMax[y] + 1.0, y + 0.5));
    filled += rowMax[y] - rowMin[y] + 1;
  }
  for (var x = 0; x < width; x++) {
    if (colMin[x] < 0) continue;
    edge
      ..add(Offset(x + 0.5, colMin[x].toDouble()))
      ..add(Offset(x + 0.5, colMax[x] + 1.0));
  }

  final hull = _hull(edge);
  if (hull.length < 4) return null;
  final rough = _fourCorners(hull);
  final tolerance = math.max(3.0, math.max(width, height) * 0.02);
  final corners = _fitSides(rough, edge, tolerance);
  if (!_convex(corners)) return null;

  // A page is a quadrilateral: a shape that fills too little of its four
  // corners is something else.
  final area = _area(corners).abs();
  if (area < n * 0.1 || filled / area < 0.85) return null;

  final ordered = _clockwiseFromTopLeft(corners);
  final page = [
    for (final c in ordered)
      Offset((c.dx / width).clamp(0.0, 1.0), (c.dy / height).clamp(0.0, 1.0)),
  ];
  // Already the whole photograph: nothing to straighten.
  const whole = [Offset(0, 0), Offset(1, 0), Offset(1, 1), Offset(0, 1)];
  var fills = true;
  for (var i = 0; i < 4; i++) {
    final d = page[i] - whole[i];
    if (d.dx.abs() > 0.02 || d.dy.abs() > 0.02) fills = false;
  }
  return fills ? null : page;
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

Uint8List _boxBlur(Uint8List src, int width, int height) {
  final out = Uint8List(src.length);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      var sum = 0;
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
      out[y * width + x] = sum ~/ count;
    }
  }
  return out;
}

/// The level that best splits [grey] in two, or null when the two halves
/// are too alike to be paper and what it lies on.
int? _otsu(Uint8List grey) {
  final hist = List<int>.filled(256, 0);
  for (final g in grey) {
    hist[g]++;
  }
  final total = grey.length;
  var sum = 0.0;
  for (var i = 0; i < 256; i++) {
    sum += i * hist[i];
  }
  var sumB = 0.0;
  var wB = 0;
  var best = -1.0;
  int? split;
  var gap = 0.0;
  for (var i = 0; i < 256; i++) {
    wB += hist[i];
    if (wB == 0) continue;
    final wF = total - wB;
    if (wF == 0) break;
    sumB += i * hist[i];
    final mB = sumB / wB;
    final mF = (sum - sumB) / wF;
    final between = wB.toDouble() * wF * (mB - mF) * (mB - mF);
    if (between > best) {
      best = between;
      split = i;
      gap = mF - mB;
    }
  }
  return gap < 40 ? null : split;
}

Uint8List _dilate(Uint8List m, int width, int height, int r) =>
    _morph(m, width, height, r, 1);

Uint8List _erode(Uint8List m, int width, int height, int r) =>
    _morph(m, width, height, r, 0);

/// Grows the [hit] value of [m] by [r] pixels each way, a square at a time:
/// across, then down.
Uint8List _morph(Uint8List m, int width, int height, int r, int hit) {
  final across = Uint8List(m.length);
  for (var y = 0; y < height; y++) {
    final row = y * width;
    var last = -r - 1;
    // The nearest [hit] at or right of x, found scanning back.
    final ahead = Int32List(width);
    var near = width + r + 1;
    for (var x = width - 1; x >= 0; x--) {
      if (m[row + x] == hit) near = x;
      ahead[x] = near;
    }
    for (var x = 0; x < width; x++) {
      if (m[row + x] == hit) last = x;
      across[row + x] = (x - last <= r || ahead[x] - x <= r) ? hit : 1 - hit;
    }
  }
  final out = Uint8List(m.length);
  final ahead = Int32List(height);
  for (var x = 0; x < width; x++) {
    var near = height + r + 1;
    for (var y = height - 1; y >= 0; y--) {
      if (across[y * width + x] == hit) near = y;
      ahead[y] = near;
    }
    var last = -r - 1;
    for (var y = 0; y < height; y++) {
      if (across[y * width + x] == hit) last = y;
      out[y * width + x] = (y - last <= r || ahead[y] - y <= r) ? hit : 1 - hit;
    }
  }
  return out;
}

/// Spreads from the pixels on [stack] to their four neighbours that
/// [takes], marking each with [mark].
void _flood(
  List<int> stack,
  int width,
  int height,
  bool Function(int) takes,
  void Function(int) mark, {
  void Function()? onVisit,
}) {
  while (stack.isNotEmpty) {
    final i = stack.removeLast();
    onVisit?.call();
    final x = i % width;
    void visit(int j) {
      if (takes(j)) {
        mark(j);
        stack.add(j);
      }
    }

    if (x > 0) visit(i - 1);
    if (x < width - 1) visit(i + 1);
    if (i >= width) visit(i - width);
    if (i < width * (height - 1)) visit(i + width);
  }
}

double _turn(Offset o, Offset a, Offset b) =>
    (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);

List<Offset> _hull(List<Offset> points) {
  final p = [
    ...points,
  ]..sort((a, b) => a.dx != b.dx ? a.dx.compareTo(b.dx) : a.dy.compareTo(b.dy));
  if (p.length < 3) return p;
  final lower = <Offset>[];
  for (final q in p) {
    while (lower.length >= 2 &&
        _turn(lower[lower.length - 2], lower.last, q) <= 0) {
      lower.removeLast();
    }
    lower.add(q);
  }
  final upper = <Offset>[];
  for (final q in p.reversed) {
    while (upper.length >= 2 &&
        _turn(upper[upper.length - 2], upper.last, q) <= 0) {
      upper.removeLast();
    }
    upper.add(q);
  }
  return [...lower..removeLast(), ...upper..removeLast()];
}

/// The convex [hull] cut down to four corners, dropping each time the
/// corner whose loss costs least area.
List<Offset> _fourCorners(List<Offset> hull) {
  final p = [...hull];
  while (p.length > 4) {
    var drop = 0;
    var least = double.infinity;
    for (var i = 0; i < p.length; i++) {
      final cost = _turn(
        p[(i - 1 + p.length) % p.length],
        p[i],
        p[(i + 1) % p.length],
      ).abs();
      if (cost < least) {
        least = cost;
        drop = i;
      }
    }
    p.removeAt(drop);
  }
  return p;
}

/// The four sides of [rough] fitted to the outline [edge] near them, away
/// from the corners where paper is often rounded or dog-eared, and the
/// corners put back where the fitted sides meet.
List<Offset> _fitSides(
  List<Offset> rough,
  List<Offset> edge,
  double tolerance,
) {
  final lines = <(Offset, Offset)>[];
  for (var i = 0; i < 4; i++) {
    final a = rough[i];
    final b = rough[(i + 1) % 4];
    final length = (b - a).distance;
    final dir = (b - a) / length;
    final normal = Offset(-dir.dy, dir.dx);
    final near = <Offset>[];
    for (final p in edge) {
      final d = p - a;
      final t = (d.dx * dir.dx + d.dy * dir.dy) / length;
      final off = (d.dx * normal.dx + d.dy * normal.dy).abs();
      if (t > 0.1 && t < 0.9 && off < tolerance) near.add(p);
    }
    if (near.length < 6) {
      lines.add((a, dir));
      continue;
    }
    var cx = 0.0, cy = 0.0;
    for (final p in near) {
      cx += p.dx;
      cy += p.dy;
    }
    cx /= near.length;
    cy /= near.length;
    var sxx = 0.0, syy = 0.0, sxy = 0.0;
    for (final p in near) {
      final dx = p.dx - cx, dy = p.dy - cy;
      sxx += dx * dx;
      syy += dy * dy;
      sxy += dx * dy;
    }
    final angle = 0.5 * math.atan2(2 * sxy, sxx - syy);
    lines.add((Offset(cx, cy), Offset(math.cos(angle), math.sin(angle))));
  }
  return [
    for (var i = 0; i < 4; i++)
      _meet(lines[(i + 3) % 4], lines[i], rough[i], tolerance * 3),
  ];
}

/// Where lines [a] and [b] cross, or [fallback] if they do not cross near
/// it.
Offset _meet(
  (Offset, Offset) a,
  (Offset, Offset) b,
  Offset fallback,
  double reach,
) {
  final (p, r) = a;
  final (q, s) = b;
  final denom = r.dx * s.dy - r.dy * s.dx;
  if (denom.abs() < 1e-9) return fallback;
  final t = ((q.dx - p.dx) * s.dy - (q.dy - p.dy) * s.dx) / denom;
  final at = p + r * t;
  return (at - fallback).distance > reach ? fallback : at;
}

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
