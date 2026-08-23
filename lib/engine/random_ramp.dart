import 'dart:math' as math;
import 'dart:ui' show Color;

import 'value_scale.dart';

/// A ramp of arbitrary hues that keeps the scale's exact values.
///
/// Each band takes the same L* target the grey ramp solves for, then picks a
/// random hue and a healthy fraction of whatever chroma that luminance
/// allows. Convert any band back to greyscale and you get the grey ramp again
/// — which is the lesson the RANDOM mode exists to teach.
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
    for (final target in scale.lstarTargets(steps))
      colourAtLstar(
        hue: rng.nextDouble() * 360,
        lstar: target,
        // Biased towards vivid: a mode called RANDOM that mostly dealt grey
        // would look broken. Near black and white the gamut itself supplies
        // the restraint.
        saturation: 0.4 + 0.6 * rng.nextDouble(),
      ),
  ];
}
