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

/// Converts an RGBA byte buffer into absolute value bands.
BandMap bandsFromRgba(
  ByteData rgba,
  int width,
  int height,
  int steps, {
  double bias = 0,
}) {
  final bytes = rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes);
  final bands = Uint8List(width * height);
  for (var i = 0, p = 0; i < bands.length; i++, p += 4) {
    // The offscreen is opaque, so the premultiplied bytes are the colour.
    final l = lstarOfSrgb8(bytes[p], bytes[p + 1], bytes[p + 2]) / 100 + bias;
    var band = (l * steps).floor();
    if (band >= steps) band = steps - 1;
    if (band < 0) band = 0;
    bands[i] = band;
  }
  return BandMap(bands, width, height);
}
