import 'dart:math' as math;
import 'dart:ui';

import 'sketch.dart';

/// Checking a drawing's proportions by points the artist picks: the top of
/// the head, the chin, the corner of an eye. Each is marked once on the
/// picture and once on the drawing.
///
/// The two sets are compared after the move, scale and turn that best lay
/// one on the other. Whatever is left over is the drawing's, not the lining
/// up's: a drawing shifted, larger or a little turned is not wrong, only
/// placed differently.
///
/// Distances are told as a share of the [LandmarkFit.span], the farthest
/// apart two picture points are, so a check reads the same at any size.

/// The most points a study holds. Plenty for a figure; past it, the labels
/// crowd the picture and the report runs long.
const int kMaxLandmarks = 12;

/// Within this share of the span, a point counts as in place.
const double kPointTolerance = 0.02;

/// Within this share, a distance between two points counts as right.
const double kRatioTolerance = 0.03;

/// Pairs of points closer than this share of the span are left out of the
/// distances: two points a finger's width apart make any slip look huge.
const double _kShortestPair = 0.2;

/// A point picked on the picture, as a fraction of each side of the whole
/// photograph, and what the artist called it, if anything.
class Landmark {
  const Landmark(this.at, [this.name]);

  final Offset at;
  final String? name;

  Landmark movedTo(Offset to) => Landmark(to, name);

  /// [name] given, or taken away by an empty one.
  Landmark named(String? name) {
    final trimmed = name?.trim();
    return Landmark(at, trimmed == null || trimmed.isEmpty ? null : trimmed);
  }

  /// Stored as `[x, y]`, or `[x, y, name]` when named.
  List<Object> toJson() => [at.dx, at.dy, ?name];

  /// Null for anything that is not two numbers, with a name or without.
  /// Held inside the photograph, which is where it was picked.
  static Landmark? fromJson(Object? json) {
    if (json is! List || json.length < 2 || json.length > 3) return null;
    final x = json[0];
    final y = json[1];
    if (x is! num || y is! num || !x.isFinite || !y.isFinite) return null;
    final name = json.length == 3 ? json[2] : null;
    return Landmark(
      Offset(x.toDouble().clamp(0.0, 1.0), y.toDouble().clamp(0.0, 1.0)),
    ).named(name is String ? name : null);
  }

  @override
  bool operator ==(Object other) =>
      other is Landmark && other.at == at && other.name == name;

  @override
  int get hashCode => Object.hash(at, name);
}

/// Names offered for a point, as an artist would call it. Left and right
/// are as the picture shows them, not the sitter's own.
const List<String> kLandmarkNames = [
  'Top of head',
  'Hairline',
  'Left eye',
  'Right eye',
  'Nose',
  'Mouth',
  'Chin',
  'Left ear',
  'Right ear',
  'Neck',
  'Left shoulder',
  'Right shoulder',
];

/// [name] in a sentence: "the chin" for one of [kLandmarkNames], as written
/// for any other, which may be a proper name; "point 3" for none. At the
/// start of a sentence with [start].
String landmarkLabel(String? name, int number, {bool start = false}) {
  final String label;
  if (name == null) {
    label = 'point $number';
  } else if (kLandmarkNames.contains(name)) {
    label = 'the ${name.toLowerCase()}';
  } else {
    return name;
  }
  return start ? label[0].toUpperCase() + label.substring(1) : label;
}

/// The move, scale and turn that best lay the drawn points on the picture's,
/// and what is left over.
class LandmarkFit {
  const LandmarkFit._({
    required this.picture,
    required this.drawn,
    required this.scale,
    required this.shift,
    required this.span,
    required this.numbers,
    required this.names,
  });

  /// What each point is called, if anything.
  final List<String?> names;

  /// The number each point is labelled with. Not always its place in the
  /// list plus one: points not yet marked on the drawing are left out of
  /// the fit.
  final List<int> numbers;

  /// The points on the picture, in pixels of it.
  final List<Offset> picture;

  /// The points on the drawing, in pixels of the drawing's photograph.
  final List<Offset> drawn;

  /// The best fit takes a drawn point `z` to `scale * z + shift`, [scale] a
  /// complex number.
  final Offset scale;
  final Offset shift;

  /// The farthest apart two of the picture's points are, in pixels.
  final double span;

  /// Drawn point [i] moved by the best fit.
  Offset fitted(int i) => _mul(scale, drawn[i]) + shift;

  /// How far, and which way, drawn point [i] is from where the picture puts
  /// it once the two are laid one on the other: where it would have to move
  /// to, as a share of [span].
  Offset error(int i) => (picture[i] - fitted(i)) / span;

  /// [error] as it lies on the drawing, in pixels of the drawing's
  /// photograph: undoes the fit's own turn and scale, so an arrow from the
  /// drawn point points at where it belongs on the drawing.
  Offset errorOnDrawing(int i) => _div(picture[i] - fitted(i), scale);

  /// How much longer the drawn distance between points [i] and [j] is than
  /// the picture's, once the fit has scaled it: 0.05 for five percent too
  /// long.
  double stretch(int i, int j) =>
      (fitted(i) - fitted(j)).distance / (picture[i] - picture[j]).distance - 1;

  String _label(int i, {bool start = false}) =>
      landmarkLabel(names[i], numbers[i], start: start);

  /// Whether the picture's points [i] and [j] are far enough apart for the
  /// distance between them to say anything.
  bool _apart(int i, int j) =>
      (picture[i] - picture[j]).distance >= span * _kShortestPair;

  /// Plain sentences for the panel, in the order to read them.
  ///
  /// First how many points are in place. Then each point that is out,
  /// worst first, with the distance to a point in place it throws off
  /// most: one chin drawn high makes every distance through it wrong, and
  /// listing each of those would bury the one mistake under its effects.
  /// Last, distances between points that are each in place yet still
  /// wrong: a span drawn too long or short with both its ends close to
  /// right.
  List<String> describe() {
    final n = picture.length;
    final out = [
      for (var i = 0; i < n; i++)
        if (error(i).distance >= kPointTolerance) i,
    ]..sort((a, b) => error(b).distance.compareTo(error(a).distance));
    if (out.isEmpty) {
      final pairs = _wrongPairs(const {});
      if (pairs.isEmpty) {
        return [
          'All $n points are within ${_percent(kPointTolerance)} of where '
              'the picture puts them.',
        ];
      }
    }
    final lines = <String>[
      out.isEmpty
          ? 'All $n points are where the picture puts them, but some '
                'distances between them are not.'
          : '${n - out.length} of $n points are where the picture puts them.',
    ];
    final outSet = out.toSet();
    for (final i in out.take(4)) {
      var line = '${_label(i, start: true)} is drawn ${_direction(error(i))}';
      int? worst;
      for (var j = 0; j < n; j++) {
        if (outSet.contains(j) || !_apart(i, j)) continue;
        if (stretch(i, j).abs() < kRatioTolerance) continue;
        if (worst == null || stretch(i, j).abs() > stretch(i, worst).abs()) {
          worst = j;
        }
      }
      if (worst != null) {
        final s = stretch(i, worst);
        line +=
            ', which makes the distance from ${_label(worst)} to '
            '${_label(i)} ${_percent(s.abs())} too '
            '${s > 0 ? 'long' : 'short'}';
      }
      lines.add('$line.');
    }
    for (final (i, j) in _wrongPairs(outSet).take(2)) {
      final s = stretch(i, j);
      lines.add(
        'From ${_label(i)} to ${_label(j)} is ${_percent(s.abs())} too '
        '${s > 0 ? 'long' : 'short'}.',
      );
    }
    return lines;
  }

  /// Distances between points not in [out] that are wrong, worst first.
  List<(int, int)> _wrongPairs(Set<int> out) =>
      <(int, int)>[
        for (var i = 0; i < picture.length; i++)
          for (var j = i + 1; j < picture.length; j++)
            if (!out.contains(i) &&
                !out.contains(j) &&
                _apart(i, j) &&
                stretch(i, j).abs() >= kRatioTolerance)
              (i, j),
      ]..sort(
        (a, b) =>
            stretch(b.$1, b.$2).abs().compareTo(stretch(a.$1, a.$2).abs()),
      );

  /// [sketch] placed over the picture as the fit lays the drawing on it,
  /// for [drawn] points in pixels of the drawing's photograph, [drawing] in
  /// size. Its proportions are its own, so only its place, size and turn
  /// change.
  SketchOverlay overlay(SketchOverlay sketch, Size photo, Size drawing) {
    // The overlay lays a point q pixels from the middle of the drawing at
    // its centre plus a turned and scaled q; the fit lays the same point,
    // q plus half the drawing from its corner, at scale times that plus
    // shift. The two agree when the turn and scale are the fit's and the
    // centre is where the fit puts the middle of the drawing.
    final center =
        _mul(scale, Offset(drawing.width / 2, drawing.height / 2)) + shift;
    return sketch.copyWith(
      center: Offset(
        (center.dx / photo.width).clamp(0.0, 1.0),
        (center.dy / photo.height).clamp(0.0, 1.0),
      ),
      width: (scale.distance * drawing.width / photo.width).clamp(
        SketchOverlay.minWidth,
        SketchOverlay.maxWidth,
      ),
      rotation: math.atan2(scale.dy, scale.dx),
    );
  }
}

/// The best fit of [drawn] onto [picture], pair by pair, both in pixels of
/// the picture. Null under three pairs: two can always be laid exactly one
/// on the other, so nothing would be left over to report. [numbers] are
/// the labels the points are shown with, 1, 2, 3 and on if not given, and
/// [names] what they are called.
LandmarkFit? fitLandmarks(
  List<Offset> picture,
  List<Offset> drawn, {
  List<int>? numbers,
  List<String?>? names,
}) {
  assert(picture.length == drawn.length);
  final n = picture.length;
  if (n < 3) return null;
  var span = 0.0;
  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      span = math.max(span, (picture[i] - picture[j]).distance);
    }
  }
  if (span == 0) return null;

  // Each pair weighted by one over how far out it is, again and again: a
  // least squares fit that ends up close to the least total distance. Plain
  // least squares spreads one bad point's error over all the others, so a
  // chin drawn too high would also read as a nose drawn too low. This fit
  // instead puts the error on as few points as it can.
  final weights = List<double>.filled(n, 1);
  final floor = span * 1e-4;
  ({Offset scale, Offset shift})? fit;
  for (var round = 0; round < 60; round++) {
    final next = _weightedFit(picture, drawn, weights);
    if (next == null) return null;
    fit = next;
    for (var i = 0; i < n; i++) {
      final r = picture[i] - (_mul(next.scale, drawn[i]) + next.shift);
      weights[i] = 1 / math.max(r.distance, floor);
    }
  }
  return LandmarkFit._(
    picture: picture,
    drawn: drawn,
    scale: fit!.scale,
    shift: fit.shift,
    span: span,
    numbers: numbers ?? [for (var i = 1; i <= n; i++) i],
    names: names ?? List.filled(n, null),
  );
}

/// The move, turn and scale minimising the sum of `weight * |a * z + b -
/// w|²` over drawn points `z` and picture points `w`, `a` a complex number.
/// Null when the drawn points all sit on one spot.
({Offset scale, Offset shift})? _weightedFit(
  List<Offset> picture,
  List<Offset> drawn,
  List<double> weights,
) {
  var total = 0.0;
  var zc = Offset.zero;
  var wc = Offset.zero;
  for (var i = 0; i < picture.length; i++) {
    total += weights[i];
    zc += drawn[i] * weights[i];
    wc += picture[i] * weights[i];
  }
  zc /= total;
  wc /= total;
  var re = 0.0;
  var im = 0.0;
  var norm = 0.0;
  for (var i = 0; i < picture.length; i++) {
    final z = drawn[i] - zc;
    final w = picture[i] - wc;
    final k = weights[i];
    // conj(z) * w
    re += k * (z.dx * w.dx + z.dy * w.dy);
    im += k * (z.dx * w.dy - z.dy * w.dx);
    norm += k * (z.dx * z.dx + z.dy * z.dy);
  }
  if (norm == 0) return null;
  final scale = Offset(re / norm, im / norm);
  return (scale: scale, shift: wc - _mul(scale, zc));
}

Offset _mul(Offset a, Offset b) =>
    Offset(a.dx * b.dx - a.dy * b.dy, a.dx * b.dy + a.dy * b.dx);

Offset _div(Offset a, Offset b) {
  final d = b.dx * b.dx + b.dy * b.dy;
  return Offset(
    (a.dx * b.dx + a.dy * b.dy) / d,
    (a.dy * b.dx - a.dx * b.dy) / d,
  );
}

String _percent(double share) {
  final p = share * 100;
  return p < 10 ? '${p.toStringAsFixed(1)}%' : '${p.round()}%';
}

/// Which way a drawn point is out, given [error], the way it would have to
/// move: a point that belongs lower was drawn too high.
String _direction(Offset error) {
  final parts = <String>[];
  if (error.dy.abs() >= kPointTolerance / 2) {
    parts.add(
      '${_percent(error.dy.abs())} too ${error.dy > 0 ? 'high' : 'low'}',
    );
  }
  if (error.dx.abs() >= kPointTolerance / 2) {
    parts.add(
      '${_percent(error.dx.abs())} too far '
      '${error.dx > 0 ? 'left' : 'right'}',
    );
  }
  return parts.isEmpty ? 'a little out' : parts.join(' and ');
}
