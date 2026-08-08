import 'dart:math' as math;

/// CIE L* conversions, shared by the ramp solver, the export path and the
/// tests. The shader carries its own copy of the same maths in GLSL.
///
/// L* is used rather than a luma of the gamma-encoded channels because
/// L* ~= 10 x Munsell V, which is what makes the output line up with the
/// printed value scale on an artist's desk.
double srgbToLinear(double c) =>
    c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double linearToSrgb(double v) =>
    v <= 0.0031308 ? v * 12.92 : 1.055 * math.pow(v, 1 / 2.4) - 0.055;

/// Relative luminance of a linear-light RGB triple.
double luminance(double r, double g, double b) =>
    0.2126 * r + 0.7152 * g + 0.0722 * b;

double lstarOfLuminance(double y) =>
    y > 0.008856 ? 116 * math.pow(y, 1 / 3).toDouble() - 16 : 903.3 * y;

/// Inverse of [lstarOfLuminance].
double luminanceOfLstar(double l) =>
    l > 8 ? math.pow((l + 16) / 116, 3).toDouble() : l / 903.3;

/// L* of an 8-bit sRGB triple, 0..100.
double lstarOfSrgb8(int r, int g, int b) => lstarOfLuminance(
  luminance(srgbToLinear(r / 255), srgbToLinear(g / 255), srgbToLinear(b / 255)),
);

int clampChannel8(double linear) =>
    (linearToSrgb(linear) * 255).round().clamp(0, 255);
