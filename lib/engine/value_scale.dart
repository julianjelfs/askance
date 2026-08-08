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
    final la = lstarOfLuminance(ya);
    final lz = lstarOfLuminance(yz);

    return List<Color>.generate(steps, (i) {
      final target = steps == 1 ? la : la + (lz - la) * (i / (steps - 1));
      final s = yz == ya
          ? 0.0
          : ((luminanceOfLstar(target) - ya) / (yz - ya)).clamp(0.0, 1.0);
      return Color.fromARGB(
        255,
        clampChannel8(ar + (zr - ar) * s),
        clampChannel8(ag + (zg - ag) * s),
        clampChannel8(ab + (zb - ab) * s),
      );
    });
  }

  /// The four-stop gradient a swatch button shows, sampled at 0/25/50/75%.
  List<Color> get swatchStops {
    final ar = srgbToLinear(dark.r),
        ag = srgbToLinear(dark.g),
        ab = srgbToLinear(dark.b);
    final zr = srgbToLinear(light.r),
        zg = srgbToLinear(light.g),
        zb = srgbToLinear(light.b);
    return [0.0, 0.25, 0.5, 0.75]
        .map(
          (t) => Color.fromARGB(
            255,
            clampChannel8(ar + (zr - ar) * t),
            clampChannel8(ag + (zg - ag) * t),
            clampChannel8(ab + (zb - ab) * t),
          ),
        )
        .toList();
  }
}
