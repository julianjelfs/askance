import 'dart:math' as math;
import 'dart:ui' show Color;

import 'lstar.dart';

/// The root of the scale: neutral grey, or a tint of any single hue.
///
/// This began as four presets — graphite, warm, cool, sepia — which were one
/// idea sampled at four arbitrary points: a subtle cast over the same value
/// ramp. The hue is now continuous, and the presets survive only as the fixed
/// hues old manifests map onto, so a study saved before the change opens
/// looking like itself.
class ValueScale {
  const ValueScale._(this.hue);

  /// A scale tinted with [hue], in degrees around the sRGB hue circle.
  ValueScale.tinted(double hue)
    : this._(hue - 360 * (hue / 360).floorToDouble());

  /// Hue in degrees, or null for the neutral grey scale.
  final double? hue;

  static const grey = ValueScale._(null);

  /// The old presets, fixed at the hues their endpoint pairs actually had.
  static const warm = ValueScale._(10.0);
  static const sepia = ValueScale._(33.0);
  static const cool = ValueScale._(214.0);

  /// The neutral endpoints are the old graphite pair, kept bit-for-bit: the
  /// README's 122,120,120 sanity check still holds.
  static const Color _greyDark = Color(0xFF111010);
  static const Color _greyLight = Color(0xFFF8F4F4);

  /// Every scale shares the neutral endpoints' L*, so moving the tint never
  /// moves a value. The old presets each picked their own endpoints and
  /// drifted several L* apart; nothing in the picture could justify that.
  static final double _darkL = _lstarOfColor(_greyDark);
  static final double _lightL = _lstarOfColor(_greyLight);

  /// How much of the available chroma every tinted band takes, of the gamut
  /// at its own luminance. Deliberately strong: the choice on offer is grey
  /// or colour, and a tint too subtle to see is a worse grey. Near black and
  /// white the gamut supplies the restraint whatever this is set to.
  static const double _tint = 0.8;

  static double _lstarOfColor(Color c) => lstarOfLuminance(
    luminance(srgbToLinear(c.r), srgbToLinear(c.g), srgbToLinear(c.b)),
  );

  Color get dark => hue == null
      ? _greyDark
      : colourAtLstar(hue: hue!, lstar: _darkL, saturation: _tint);

  Color get light => hue == null
      ? _greyLight
      : colourAtLstar(hue: hue!, lstar: _lightL, saturation: _tint);

  /// How the scale reads in a shelf caption: "3 values · grey · 8 Aug".
  String get shortName {
    final h = hue;
    if (h == null) return 'grey';
    if (h < 20 || h >= 345) return 'red';
    if (h < 50) return 'sepia';
    if (h < 75) return 'yellow';
    if (h < 150) return 'green';
    if (h < 195) return 'teal';
    if (h < 255) return 'blue';
    if (h < 300) return 'violet';
    return 'pink';
  }

  /// The even L* each of [steps] bands aims for, darkest first. Shared with
  /// the random ramp, so RANDOM shows exactly the values VALUE does.
  List<double> lstarTargets(int steps) => List<double>.generate(
    steps,
    (i) =>
        steps == 1 ? _darkL : _darkL + (_lightL - _darkL) * (i / (steps - 1)),
  );

  /// The ramp for [steps] bands, solved for **even L***. Band 0 is darkest.
  ///
  /// A tinted ramp is not an interpolation between its endpoints: that gave
  /// the middle bands almost no chroma, because a colour interpolated between
  /// two near-greys is a near-grey, however wide the gamut is where it sits.
  /// Each band takes its own slice of the gamut at its own luminance instead,
  /// so the colour is at its most visible in the middle values — where there
  /// is room for it — and tapers into the endpoints as the gamut closes.
  ///
  /// Sanity check the README calls out: the grey scale at 3 steps must give a
  /// middle band of sRGB 122,120,120. Interpolating in the wrong space gives
  /// ~132.
  List<Color> ramp(int steps) {
    final h = hue;
    if (h != null) {
      return [
        for (final target in lstarTargets(steps))
          colourAtLstar(hue: h, lstar: target, saturation: _tint),
      ];
    }

    final a = dark, z = light;
    final ar = srgbToLinear(a.r),
        ag = srgbToLinear(a.g),
        ab = srgbToLinear(a.b);
    final zr = srgbToLinear(z.r),
        zg = srgbToLinear(z.g),
        zb = srgbToLinear(z.b);

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

  /// The four bands a swatch shows, at 0/25/50/75%: the scale's own four-step
  /// ramp, so the swatch shows colours the engine actually produces.
  List<Color> get swatchBands => ramp(4);

  /// Grey serialises as a name, a tint as its hue in degrees. The old enum
  /// names are still readable so an existing shelf survives the change.
  Object toJson() => hue ?? 'grey';

  static ValueScale fromJson(Object? value) {
    if (value is num) return ValueScale.tinted(value.toDouble());
    return switch (value) {
      'warm' => warm,
      'sepia' => sepia,
      'cool' => cool,
      // 'grey', 'graphite', and anything unrecognisable.
      _ => grey,
    };
  }

  @override
  bool operator ==(Object other) => other is ValueScale && other.hue == hue;

  @override
  int get hashCode => hue.hashCode;
}

/// A colour of exactly [lstar], at [saturation] of the widest chroma the sRGB
/// gamut allows at that luminance and [hue].
///
/// Works by walking from the grey of that luminance towards the hue's most
/// chromatic colour scaled to the same luminance: luminance is linear, so
/// every point on the walk holds the value exactly, and the walk is cut where
/// a channel would leave the gamut. Near black and white that room shrinks to
/// nothing, which is the gamut telling the truth: vivid colour only exists in
/// the middle values.
Color colourAtLstar({
  required double hue,
  required double lstar,
  required double saturation,
}) {
  final y = luminanceOfLstar(lstar);
  final p = _linearOfHue(hue);
  final yp = luminance(p[0], p[1], p[2]);
  final q = [for (final c in p) c * (y / yp)];

  var tMax = 1.0;
  for (final c in q) {
    if (c > 1) tMax = math.min(tMax, (1 - y) / (c - y));
  }
  final t = tMax * saturation;

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
