import 'dart:typed_data';

import 'lstar.dart';

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
BandMap bandsFromRgba(
  ByteData rgba,
  int width,
  int height,
  int steps, {
  double bias = 0,
}) {
  final bytes = rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes);
  final bands = Uint8List(width * height);
  // A pixel is in band k or above once its L* reaches (k / steps − bias) ×
  // 100. Out of range either way, a threshold is always or never met.
  final thresholds = Float64List(steps - 1);
  for (var k = 1; k < steps; k++) {
    final l = (k / steps - bias) * 100;
    thresholds[k - 1] = l <= 0
        ? double.negativeInfinity
        : l > 100
        ? double.infinity
        : luminanceOfLstar(l);
  }
  for (var i = 0, p = 0; i < bands.length; i++, p += 4) {
    // The offscreen is opaque, so the premultiplied bytes are the colour.
    final y = luminance(
      _linear[bytes[p]],
      _linear[bytes[p + 1]],
      _linear[bytes[p + 2]],
    );
    var band = 0;
    while (band < thresholds.length && y >= thresholds[band]) {
      band++;
    }
    bands[i] = band;
  }
  return BandMap(bands, width, height);
}
