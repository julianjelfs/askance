import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'regions.dart';
import 'tone.dart';

/// The straight-edged shapes of a band map: for each threshold, the outline of
/// everything darker than it, reduced to a few straight runs.
///
/// Thresholds rather than bands, because the masks they make nest — whatever
/// is darker than the second threshold is also darker than the third — so
/// painting them lightest first, each over the last, leaves every boundary
/// drawn by exactly one polygon. Simplifying each band's own outline instead
/// would straighten the two sides of a shared boundary differently, and the
/// picture would fill with slivers and gaps where they disagree.
///
/// [masks] is darkest first: masks[0] is everything in band 0, masks[k] is
/// everything below band k + 1. Each mask is a list of closed loops in the
/// band map's pixel space, meant to be filled even-odd so holes stay holes.
class BlockShapes {
  const BlockShapes(this.masks, this.width, this.height);

  final List<List<List<Offset>>> masks;
  final int width;
  final int height;
}

/// What [blockShapes] needs, as one value so it can cross to an isolate.
typedef BlockInput = ({
  Uint8List rgba,
  int width,
  int height,
  int steps,
  double bias,
  bool mono,
  double brightness,
  double contrast,
  double tolerance,
});

BlockShapes blockShapes(BlockInput input) {
  final map = bandsFromRgba(
    ByteData.sublistView(input.rgba),
    input.width,
    input.height,
    input.steps,
    bias: input.bias,
    tone: PhotoTone(
      mono: input.mono,
      brightness: input.brightness,
      contrast: input.contrast,
    ),
  );
  final masks = <List<List<Offset>>>[];
  final mask = Uint8List(map.width * map.height);
  // A shape that reaches the side of the picture has to keep reaching it, or
  // straightening its outline pulls it in off the edge and the band beneath
  // shows through as a sliver along the frame.
  bool onFrame(Offset p) =>
      p.dx <= 0 || p.dy <= 0 || p.dx >= map.width || p.dy >= map.height;
  for (var k = 1; k < input.steps; k++) {
    var any = false;
    for (var i = 0; i < mask.length; i++) {
      final inside = map.bands[i] < k;
      mask[i] = inside ? 1 : 0;
      any |= inside;
    }
    masks.add(
      any
          ? [
              for (final loop in traceMask(mask, map.width, map.height))
                if (simplifyLoop(loop, input.tolerance, pinned: onFrame)
                    case final s when s.length >= 3)
                  s,
            ]
          : const [],
    );
  }
  return BlockShapes(masks, map.width, map.height);
}

/// The outlines of a 0/1 [mask], as closed loops through the midpoints
/// between pixel centres (marching squares).
///
/// Pixel (x, y) is centred at (x + 0.5, y + 0.5). The mask is treated as
/// surrounded by zeros, so a shape touching the side of the picture is closed
/// along that side, exactly on it.
List<List<Offset>> traceMask(Uint8List mask, int width, int height) {
  // Padded by one sample all round, so every loop closes.
  final pw = width + 2;
  final ph = height + 2;
  int at(int i, int j) {
    final x = i - 1, y = j - 1;
    if (x < 0 || y < 0 || x >= width || y >= height) return 0;
    return mask[y * width + x];
  }

  // Edge midpoints, keyed by the padded sample they leave from and which way:
  // even is the horizontal edge to the right, odd the vertical edge below.
  int h(int i, int j) => (j * pw + i) * 2;
  int v(int i, int j) => (j * pw + i) * 2 + 1;

  // Every midpoint on an outline lies on exactly two segments. Flat arrays
  // indexed by the midpoint's key rather than maps: this runs over every
  // pixel for every value, and on the web it runs on the only thread there
  // is.
  final size = pw * ph * 2;
  final first = Int32List(size)..fillRange(0, size, -1);
  final second = Int32List(size)..fillRange(0, size, -1);
  void link(int a, int b) {
    if (first[a] < 0) {
      first[a] = b;
    } else {
      second[a] = b;
    }
    if (first[b] < 0) {
      first[b] = a;
    } else {
      second[b] = a;
    }
  }

  for (var j = 0; j < ph - 1; j++) {
    for (var i = 0; i < pw - 1; i++) {
      final tl = at(i, j), tr = at(i + 1, j);
      final br = at(i + 1, j + 1), bl = at(i, j + 1);
      final index = tl << 3 | tr << 2 | br << 1 | bl;
      if (index == 0 || index == 15) continue;
      final t = h(i, j), b = h(i, j + 1);
      final l = v(i, j), r = v(i + 1, j);
      switch (index) {
        case 1 || 14:
          link(l, b);
        case 2 || 13:
          link(b, r);
        case 3 || 12:
          link(l, r);
        case 4 || 11:
          link(t, r);
        case 6 || 9:
          link(t, b);
        case 7 || 8:
          link(t, l);
        // Diagonal pairs: kept apart, so shapes that only touch at a corner
        // stay two shapes.
        case 5:
          link(t, r);
          link(l, b);
        case 10:
          link(t, l);
          link(b, r);
      }
    }
  }

  Offset position(int key) {
    final cell = key >> 1;
    final i = cell % pw, j = cell ~/ pw;
    // Padded sample (i, j) is pixel (i - 1, j - 1), centred half a pixel in.
    final x = i - 0.5, y = j - 0.5;
    return key.isEven ? Offset(x + 0.5, y) : Offset(x, y + 0.5);
  }

  final loops = <List<Offset>>[];
  final visited = Uint8List(size);
  for (var start = 0; start < size; start++) {
    if (first[start] < 0 || visited[start] != 0) continue;
    visited[start] = 1;
    final loop = <Offset>[position(start)];
    var previous = start;
    var current = first[start];
    while (current != start) {
      visited[current] = 1;
      loop.add(position(current));
      final a = first[current];
      final next = a != previous ? a : second[current];
      previous = current;
      current = next;
    }
    loops.add(loop);
  }
  return loops;
}

/// [loop] with every point dropped that lies within [tolerance] of a straight
/// run between its neighbours (Douglas–Peucker, closed).
///
/// A point [pinned] says must stay is always kept, and the runs between such
/// points are straightened separately, so nothing moves off them.
List<Offset> simplifyLoop(
  List<Offset> loop,
  double tolerance, {
  bool Function(Offset)? pinned,
}) {
  if (loop.length < 4) return loop;
  final pins = [
    if (pinned != null)
      for (var i = 0; i < loop.length; i++)
        if (pinned(loop[i])) i,
  ];
  if (pins.isNotEmpty) {
    final kept = <Offset>[];
    for (var p = 0; p < pins.length; p++) {
      final from = pins[p];
      final to = p + 1 < pins.length ? pins[p + 1] : pins[0] + loop.length;
      final run = [for (var i = from; i <= to; i++) loop[i % loop.length]];
      final straight = _simplifyLine(run, tolerance);
      // Each run ends where the next begins.
      kept.addAll(straight.sublist(0, straight.length - 1));
    }
    return kept;
  }
  // Split the loop at its first point and the point furthest from it, and
  // simplify each half as an open line.
  var far = 0;
  var best = -1.0;
  for (var i = 1; i < loop.length; i++) {
    final d = (loop[i] - loop[0]).distanceSquared;
    if (d > best) {
      best = d;
      far = i;
    }
  }
  final a = _simplifyLine([...loop.sublist(0, far + 1)], tolerance);
  final b = _simplifyLine([...loop.sublist(far), loop[0]], tolerance);
  return [...a.sublist(0, a.length - 1), ...b.sublist(0, b.length - 1)];
}

List<Offset> _simplifyLine(List<Offset> line, double tolerance) {
  if (line.length < 3) return line;
  final keep = List<bool>.filled(line.length, false)
    ..[0] = true
    ..[line.length - 1] = true;
  // An explicit stack: a long outline would recurse thousands deep.
  final stack = <(int, int)>[(0, line.length - 1)];
  while (stack.isNotEmpty) {
    final (from, to) = stack.removeLast();
    var index = -1;
    var furthest = tolerance;
    for (var i = from + 1; i < to; i++) {
      final d = _distanceToSegment(line[i], line[from], line[to]);
      if (d > furthest) {
        furthest = d;
        index = i;
      }
    }
    if (index < 0) continue;
    keep[index] = true;
    stack
      ..add((from, index))
      ..add((index, to));
  }
  return [
    for (var i = 0; i < line.length; i++)
      if (keep[i]) line[i],
  ];
}

double _distanceToSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final length = ab.distanceSquared;
  if (length == 0) return (p - a).distance;
  final t = (((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / length).clamp(
    0.0,
    1.0,
  );
  return (p - (a + ab * t)).distance;
}

/// The L* a block of [band] is filled with: the middle of the part of the
/// band the shader can reach once [bias] has slid the thresholds, so the
/// shader puts it straight back in the band it came from.
double bandCentreLstar(int band, int steps, double bias) {
  final low = math.max(0.0, band / steps - bias);
  final high = math.min(1.0, (band + 1) / steps - bias);
  return (low + high) / 2 * 100;
}
