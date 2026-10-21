import 'dart:math' as math;
import 'dart:typed_data';

import 'package:askance/engine/lstar.dart';
import 'package:askance/engine/regions.dart';
import 'package:askance/engine/tone.dart';
import 'package:flutter_test/flutter_test.dart';

/// The shader's own rule, written out longhand: `floor((L*/100 + bias) ×
/// steps)`, clamped, of the pixel as the tone shows it. The CPU band map
/// feeds BLOCK and must agree with it pixel for pixel, or a block would be
/// painted in a value the shader then reads as a different band.
int shaderBand(int r, int g, int b, int steps, double bias, PhotoTone tone) {
  final double l;
  if (tone.mono) {
    l = tone.curve(lstarOfSrgb8(r, g, b) / 100);
  } else {
    // The curve per channel, in floating point as the shader has it.
    final lin = [
      for (final v in [r, g, b]) srgbToLinear(tone.curve(v / 255)),
    ];
    l = lstarOfLuminance(luminance(lin[0], lin[1], lin[2])) / 100;
  }
  return ((l + bias) * steps).floor().clamp(0, steps - 1);
}

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
    for (final (steps, bias, tone) in [
      for (var steps = 2; steps <= 7; steps++)
        for (final bias in [-0.25, -0.13, 0.0, 0.04, 0.25])
          (steps, bias, const PhotoTone()),
      // Brightness and contrast, both ways, on the lightness and on each
      // channel.
      for (final tone in const [
        PhotoTone(mono: true, brightness: 0.4, contrast: 0.6),
        PhotoTone(mono: true, brightness: -0.7, contrast: -0.5),
        PhotoTone(brightness: -0.3, contrast: 0.8),
        PhotoTone(brightness: 0.5, contrast: -1),
      ])
        for (final bias in [-0.1, 0.0, 0.2]) (5, bias, tone),
    ]) {
      {
        final map = bandsFromRgba(
          ByteData.sublistView(rgba),
          count,
          1,
          steps,
          bias: bias,
          tone: tone,
        );
        for (var i = 0; i < count; i++) {
          final expected = shaderBand(
            rgba[i * 4],
            rgba[i * 4 + 1],
            rgba[i * 4 + 2],
            steps,
            bias,
            tone,
          );
          if (map.bands[i] != expected) {
            fail(
              'steps $steps bias $bias $tone pixel $i: ${map.bands[i]} != '
              '$expected',
            );
          }
        }
      }
    }
  });
}
