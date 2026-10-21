import 'dart:typed_data';

import 'lstar.dart';
import 'tone.dart';

/// The band map, plus the grid it was sampled on. This mirrors the shader's
/// quantisation exactly; the tests hold the two to the same answers.
class BandMap {
  const BandMap(this.bands, this.width, this.height);

  final Uint8List bands;
  final int width;
  final int height;
}

/// Linear light of every 8-bit sRGB channel value.
final Float64List _linear = Float64List.fromList([
  for (var v = 0; v < 256; v++) srgbToLinear(v / 255),
]);

/// Converts an RGBA byte buffer into absolute value bands.
///
/// The shader's rule is `floor((L*/100 + bias) × steps)`. L* only rises with
/// luminance, so rather than take the L* of every pixel — three powers and a
/// cube root each, the bulk of a BLOCK pass on a phone — the band thresholds
/// are turned into luminances once and each pixel's luminance, three table
/// lookups, is compared against them. Same answer, a fraction of the work.
///
/// The pixel is banded as [tone] shows it. In colour its curve is applied to
/// each channel, which folds into the table; in black and white it is
/// applied to the lightness, and only ever rises with it, so it folds into
/// the thresholds instead.
BandMap bandsFromRgba(
  ByteData rgba,
  int width,
  int height,
  int steps, {
  double bias = 0,
  PhotoTone tone = const PhotoTone(),
}) {
  final bytes = rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes);
  final bands = Uint8List(width * height);
  final linear = tone.mono || tone.keepsValues
      ? _linear
      : Float64List.fromList([
          for (var v = 0; v < 256; v++) srgbToLinear(tone.curve(v / 255)),
        ]);
  // A pixel is in band k or above once its L* reaches (k / steps − bias) ×
  // 100. Out of range either way, a threshold is always or never met.
  final thresholds = Float64List(steps - 1);
  for (var k = 1; k < steps; k++) {
    final toned = k / steps - bias;
    final l = tone.mono
        // The curve is clamped, so a toned threshold at or below 0 is met by
        // everything and one above 1 by nothing, wherever it maps back to.
        ? (toned <= 0
              ? 0.0
              : toned > 1
              ? 101.0
              : tone.uncurve(toned) * 100)
        : toned * 100;
    thresholds[k - 1] = l <= 0
        ? double.negativeInfinity
        : l > 100
        ? double.infinity
        : luminanceOfLstar(l);
  }
  for (var i = 0, p = 0; i < bands.length; i++, p += 4) {
    // The offscreen is opaque, so the premultiplied bytes are the colour.
    final y = luminance(
      linear[bytes[p]],
      linear[bytes[p + 1]],
      linear[bytes[p + 2]],
    );
    var band = 0;
    while (band < thresholds.length && y >= thresholds[band]) {
      band++;
    }
    bands[i] = band;
  }
  return BandMap(bands, width, height);
}
