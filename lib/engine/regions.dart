import 'dart:typed_data';

import 'lstar.dart';
import 'tone.dart';

/// The band map, plus the grid it was sampled on. This mirrors the shader's
/// quantisation exactly; the tests hold the two to the same answers.
/// A free line between the light and shadow families: the darkest [shadow]
/// bands share the toned lightness below [at], the rest the lightness above
/// it, each family split evenly. Without one the bands share 0..1 evenly.
typedef FamilySplit = ({int shadow, double at});

/// The toned lightness band [k] starts at, for k in 1..steps - 1: k / steps,
/// or with a [split], the shadow family's share of 0..at or the light
/// family's of at..1. A split at shadow / steps is the plain ladder.
double toneCut(int k, int steps, FamilySplit? split) {
  if (split == null) return k / steps;
  final (:shadow, :at) = split;
  return k <= shadow
      ? at * k / shadow
      : at + (1 - at) * (k - shadow) / (steps - shadow);
}

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
/// The shader's rule is `floor((L*/100 + bias) × steps)`, or with a
/// [split], the same within each family. L* only rises with
/// luminance, so rather than take the L* of every pixel — three powers and a
/// cube root each, the bulk of a BLOCK pass on a phone — the band thresholds
/// are turned into luminances once and each pixel's luminance, three table
/// lookups, is compared against them. Same answer, a fraction of the work.
///
/// The lightness is banded through the picture's tone curve, [bias] the
/// shift and [contrast] the spread. The curve only ever rises with the
/// lightness, so it folds into the thresholds too.
BandMap bandsFromRgba(
  ByteData rgba,
  int width,
  int height,
  int steps, {
  double bias = 0,
  double contrast = 0,
  FamilySplit? split,
}) {
  final bytes = rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes);
  final bands = Uint8List(width * height);
  // A pixel is in band k or above once its toned lightness reaches the k-th
  // cut: once its L* reaches that, taken back through the curve, × 100.
  // Out of range either way, a threshold is always or never met.
  final thresholds = Float64List(steps - 1);
  for (var k = 1; k < steps; k++) {
    final l =
        toneUncurve(toneCut(k, steps, split), shift: bias, contrast: contrast) *
        100;
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
