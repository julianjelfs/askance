import 'dart:ui' show Color;

import 'lstar.dart';

/// The four scales, each a dark and a light endpoint in sRGB.
enum ValueScale {
  graphite('Graphite', 'grey', 0xFF111010, 0xFFF8F4F4),
  warm('Warm', 'warm', 0xFF2A0B05, 0xFFFFE0D9),
  cool('Cool', 'cool', 0xFF0D1520, 0xFFEEF2F7),
  sepia('Sepia', 'sepia', 0xFF241A10, 0xFFF6EFE2);

  const ValueScale(this.label, this.shortName, this._dark, this._light);

  final String label;

  /// How the scale reads in a shelf caption: "3 values · grey · 8 Aug".
  final String shortName;

  final int _dark;
  final int _light;

  Color get dark => Color(_dark);
  Color get light => Color(_light);

  /// The even L* each of [steps] bands aims for, darkest first. Shared with
  /// the random ramp, so RANDOM shows exactly the values VALUE does.
  List<double> lstarTargets(int steps) {
    final la = _lstarOfEndpoint(dark);
    final lz = _lstarOfEndpoint(light);
    return List<double>.generate(
      steps,
      (i) => steps == 1 ? la : la + (lz - la) * (i / (steps - 1)),
    );
  }

  static double _lstarOfEndpoint(Color c) => lstarOfLuminance(
    luminance(srgbToLinear(c.r), srgbToLinear(c.g), srgbToLinear(c.b)),
  );

  /// The ramp for [steps] bands, solved for **even L*** between the two
  /// endpoints rather than interpolated in sRGB. Band 0 is darkest.
  ///
  /// Sanity check the README calls out: Graphite at 3 steps must give a middle
  /// band of sRGB 122,120,120. Interpolating in the wrong space gives ~132.
  List<Color> ramp(int steps) {
    final ar = srgbToLinear(dark.r),
        ag = srgbToLinear(dark.g),
        ab = srgbToLinear(dark.b);
    final zr = srgbToLinear(light.r),
        zg = srgbToLinear(light.g),
        zb = srgbToLinear(light.b);

    final ya = luminance(ar, ag, ab);
    final yz = luminance(zr, zg, zb);
    final targets = lstarTargets(steps);

    return List<Color>.generate(steps, (i) {
      final s = yz == ya
          ? 0.0
          : ((luminanceOfLstar(targets[i]) - ya) / (yz - ya)).clamp(0.0, 1.0);
      return Color.fromARGB(
        255,
        clampChannel8(ar + (zr - ar) * s),
        clampChannel8(ag + (zg - ag) * s),
        clampChannel8(ab + (zb - ab) * s),
      );
    });
  }

  /// The four bands a swatch button shows, at 0/25/50/75%.
  ///
  /// These are the scale's own four-step ramp rather than a smooth blend, so
  /// the swatch shows colours the engine actually produces. (The HTML
  /// prototype hard-codes swatch hexes that match neither its own ramp nor an
  /// sRGB interpolation of the endpoints; they appear to be hand-picked.)
  List<Color> get swatchBands => ramp(4);
}
