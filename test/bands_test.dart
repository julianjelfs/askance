import 'dart:math' as math;
import 'dart:typed_data';

import 'package:askance/engine/lstar.dart';
import 'package:askance/engine/regions.dart';
import 'package:askance/engine/tone.dart';
import 'package:flutter_test/flutter_test.dart';

/// The shader's own rule, written out longhand: `floor(curve(L*/100) ×
/// steps)`, clamped, where the curve is the picture's tone, [bias] the shift
/// and [contrast] the spread. The CPU band map feeds BLOCK and must agree
/// with it pixel for pixel, or a block would be painted in a value the
/// shader then reads as a different band.
int shaderBand(int r, int g, int b, int steps, double bias, double contrast) =>
    (toneCurve(lstarOfSrgb8(r, g, b) / 100, shift: bias, contrast: contrast) *
            steps)
        .floor()
        .clamp(0, steps - 1);

void main() {
  test('the band map puts every pixel in the band the shader would', () {
    final random = math.Random(7);
    const count = 20000;
    final rgba = Uint8List(count * 4);
    for (var i = 0; i < count; i++) {
      // Every grey, then random colours.
      final grey = i < 256;
      final v = i % 256;
      rgba[i * 4] = grey ? v : random.nextInt(256);
      rgba[i * 4 + 1] = grey ? v : random.nextInt(256);
      rgba[i * 4 + 2] = grey ? v : random.nextInt(256);
      rgba[i * 4 + 3] = 255;
    }
    for (final (steps, bias, contrast) in [
      for (var steps = 2; steps <= 7; steps++)
        for (final bias in [-0.25, -0.13, 0.0, 0.04, 0.25]) (steps, bias, 0.0),
      // Contrast both ways, alone and with a shift.
      for (final contrast in [-1.0, -0.4, 0.5, 1.0])
        for (final bias in [-0.1, 0.0, 0.2]) (5, bias, contrast),
    ]) {
      final map = bandsFromRgba(
        ByteData.sublistView(rgba),
        count,
        1,
        steps,
        bias: bias,
        contrast: contrast,
      );
      for (var i = 0; i < count; i++) {
        final expected = shaderBand(
          rgba[i * 4],
          rgba[i * 4 + 1],
          rgba[i * 4 + 2],
          steps,
          bias,
          contrast,
        );
        if (map.bands[i] != expected) {
          fail(
            'steps $steps bias $bias contrast $contrast pixel $i: '
            '${map.bands[i]} != $expected',
          );
        }
      }
    }
  });
}
