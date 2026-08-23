import 'dart:math' as math;
import 'dart:ui' show Color;

import 'lstar.dart';
import 'value_scale.dart';

/// A ramp of arbitrary hues that keeps the scale's exact values.
///
/// Each band takes the same L* target the grey ramp solves for, then picks a
/// random hue and as much chroma as that luminance allows. Convert any band
/// back to greyscale and you get the grey ramp again — which is the lesson
/// the RANDOM mode exists to teach.
///
/// Deterministic in [seed], so a repaint shows the palette it showed last
/// frame and a saved study reopens with the colours it was kept with. A new
/// deal is a new seed, not a new call.
List<Color> randomRamp({
  required ValueScale scale,
  required int steps,
  required int seed,
}) {
  final rng = math.Random(seed);
  return [
    for (final target in scale.lstarTargets(steps)) _randomAtLstar(rng, target),
  ];
}

Color _randomAtLstar(math.Random rng, double target) {
  final y = luminanceOfLstar(target);

  // A fully saturated hue in linear light, scaled to the target luminance.
  // The scaling can push a channel past 1; the walk below stops short of that.
  final p = _linearOfHue(rng.nextDouble() * 360);
  final yp = luminance(p[0], p[1], p[2]);
  final q = [for (final c in p) c * (y / yp)];

  // Everything on the segment from grey(y) to q has luminance exactly y —
  // luminance is linear — so chroma is free to vary without touching the
  // value. tMax is where the segment leaves the gamut.
  var tMax = 1.0;
  for (final c in q) {
    if (c > 1) tMax = math.min(tMax, (1 - y) / (c - y));
  }

  // Biased towards vivid: a mode called RANDOM that mostly dealt grey would
  // look broken. Near black and white the gamut itself supplies the restraint.
  final t = tMax * (0.4 + 0.6 * rng.nextDouble());

  return Color.fromARGB(
    255,
    clampChannel8(y + t * (q[0] - y)),
    clampChannel8(y + t * (q[1] - y)),
    clampChannel8(y + t * (q[2] - y)),
  );
}

/// HSV (hue, 1, 1) in sRGB, then linearised — the most chromatic colour the
/// gamut has at each hue.
List<double> _linearOfHue(double hue) {
  final h = hue / 60;
  final x = 1 - ((h % 2) - 1).abs();
  final (r, g, b) = switch (h.floor() % 6) {
    0 => (1.0, x, 0.0),
    1 => (x, 1.0, 0.0),
    2 => (0.0, 1.0, x),
    3 => (0.0, x, 1.0),
    4 => (x, 0.0, 1.0),
    _ => (1.0, 0.0, x),
  };
  return [srgbToLinear(r), srgbToLinear(g), srgbToLinear(b)];
}
