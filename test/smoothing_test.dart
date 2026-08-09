import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:askance/engine/engine.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// The two ways of simplifying a photograph differ in what they do to an edge.
/// A Gaussian softens across it; Kuwahara flattens up to it and leaves it
/// where it is.
void main() {
  /// A hard vertical edge with fine noise on both sides, so there is something
  /// for either method to simplify away.
  Future<ui.Image> edgeWithNoise(int side) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble()),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, side / 2, side.toDouble()),
      Paint()..color = const Color(0xFFE0E0E0),
    );
    canvas.drawRect(
      Rect.fromLTWH(side / 2, 0, side / 2, side.toDouble()),
      Paint()..color = const Color(0xFF303030),
    );
    final random = math.Random(3);
    for (var i = 0; i < 4000; i++) {
      final x = random.nextDouble() * side;
      final light = x < side / 2;
      final base = light ? 224 : 48;
      final v = (base + random.nextInt(48) - 24).clamp(0, 255);
      canvas.drawRect(
        Rect.fromLTWH(x, random.nextDouble() * side, 2, 2),
        Paint()..color = Color.fromARGB(255, v, v, v),
      );
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(side, side);
    picture.dispose();
    return image;
  }

  Future<List<int>> rowThrough(Smoothing smoothing) async {
    final source = await edgeWithNoise(256);
    const output = Size(256, 256);
    final result = await renderBlurredSource(
      source: source,
      outputPx: output,
      detail: 0.55,
      view: const ViewTransform(),
      smoothing: smoothing,
    );
    final bytes = (await result.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!.buffer.asUint8List();
    final width = result.width;
    final y = result.height ~/ 2;
    final row = [
      for (var x = 0; x < width; x++) bytes[(y * width + x) * 4],
    ];
    result.dispose();
    source.dispose();
    return row;
  }

  /// How many pixels the transition from light to dark is spread across.
  int edgeWidth(List<int> row) {
    final light = row.first;
    final dark = row.last;
    final high = light - (light - dark) * 0.15;
    final low = dark + (light - dark) * 0.15;
    var first = -1, last = -1;
    for (var i = 0; i < row.length; i++) {
      if (row[i] < high && first < 0) first = i;
      if (row[i] > low) last = i;
    }
    return last - first;
  }

  test('Kuwahara keeps the edge tighter than a Gaussian does', () async {
    final soft = await rowThrough(Smoothing.gaussian);
    final flat = await rowThrough(Smoothing.kuwahara);

    // Both are measured as a fraction of their own width, because the flat
    // pass returns a reduced copy.
    final softSpread = edgeWidth(soft) / soft.length;
    final flatSpread = edgeWidth(flat) / flat.length;

    expect(
      flatSpread,
      lessThan(softSpread),
      reason:
          'the whole point of the flat pass is that the boundary does not '
          'drift: soft ${softSpread.toStringAsFixed(3)}, '
          'flat ${flatSpread.toStringAsFixed(3)}',
    );
  });

  test('both flatten the noise either side of the edge', () async {
    for (final smoothing in Smoothing.values) {
      final row = await rowThrough(smoothing);
      // Sample well clear of the boundary.
      final quarter = row.length ~/ 4;
      final patch = row.sublist(quarter - 8, quarter + 8);
      final spread = patch.reduce(math.max) - patch.reduce(math.min);
      expect(
        spread,
        lessThan(24),
        reason: '$smoothing left the noise in: spread $spread',
      );
    }
  });

  test('the flat pass returns a reduced copy, as it is meant to', () async {
    final source = await edgeWithNoise(256);
    const output = Size(256, 256);
    final flat = await renderBlurredSource(
      source: source,
      outputPx: output,
      detail: 0.2,
      view: const ViewTransform(),
      smoothing: Smoothing.kuwahara,
    );
    expect(
      flat.width,
      lessThan(output.width),
      reason: 'a coarse setting has no business running at full resolution',
    );
    flat.dispose();
    source.dispose();
  });
}
