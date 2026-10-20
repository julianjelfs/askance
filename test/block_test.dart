import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:askance/engine/blocks.dart';
import 'package:askance/engine/engine.dart';
import 'package:askance/engine/lstar.dart';
import 'package:askance/model/study.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every block is filled with a grey the shader reads back as its own '
      'band, whatever the bias', () {
    for (
      var steps = StudySettings.minSteps;
      steps <= StudySettings.maxSteps;
      steps++
    ) {
      for (final bias in [-StudySettings.maxBias, -0.1, 0.0, 0.07, 0.25]) {
        for (var band = 0; band < steps; band++) {
          // A band the bias has pushed off the scale has no pixels to fill.
          if (band / steps - bias >= 1 || (band + 1) / steps - bias <= 0) {
            continue;
          }
          final v = clampChannel8(
            luminanceOfLstar(bandCentreLstar(band, steps, bias)),
          );
          final l = lstarOfSrgb8(v, v, v) / 100 + bias;
          final back = (l * steps).floor().clamp(0, steps - 1);
          expect(back, band, reason: 'steps $steps bias $bias band $band');
        }
      }
    }
  });

  test('a round shape comes out as a few straight edges that still follow '
      'it', () {
    const side = 200, radius = 70.0;
    final mask = Uint8List(side * side);
    for (var y = 0; y < side; y++) {
      for (var x = 0; x < side; x++) {
        final d = math.sqrt(
          math.pow(x + 0.5 - 100, 2) + math.pow(y + 0.5 - 100, 2),
        );
        mask[y * side + x] = d < radius ? 1 : 0;
      }
    }
    final loops = traceMask(mask, side, side);
    expect(loops, hasLength(1));
    const tolerance = 3.0;
    final polygon = simplifyLoop(loops.single, tolerance);
    expect(polygon.length, lessThan(30));
    expect(polygon.length, greaterThan(6));
    for (final p in polygon) {
      expect(
        ((p - const Offset(100, 100)).distance - radius).abs(),
        lessThan(tolerance + 1),
      );
    }
  });

  test('a shape with a hole keeps its hole', () {
    const side = 60;
    final mask = Uint8List(side * side);
    for (var y = 10; y < 50; y++) {
      for (var x = 10; x < 50; x++) {
        final inHole = x >= 25 && x < 35 && y >= 25 && y < 35;
        mask[y * side + x] = inHole ? 0 : 1;
      }
    }
    expect(traceMask(mask, side, side), hasLength(2));
  });

  test('a BLOCK pass holds nothing but the band greys: no slivers of other '
      'values along the edges', () async {
    // Dark ring on a light ground, over a gradient, so there are three bands
    // and boundaries in every direction.
    const side = 240;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, side + 0.0, side + 0.0),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          const Offset(side + 0.0, 0),
          [const Color(0xFFFFFFFF), const Color(0xFF777777)],
        ),
    );
    canvas.drawCircle(
      const Offset(120, 120),
      80,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 30
        ..color = const Color(0xFF101010),
    );
    final picture = recorder.endRecording();
    final source = await picture.toImage(side, side);
    picture.dispose();
    addTearDown(source.dispose);

    const steps = 3;
    final result = await renderBlurredSource(
      source: source,
      outputPx: const Size(side + 0.0, side + 0.0),
      detail: 0.3,
      view: const ViewTransform(),
      smoothing: Smoothing.block,
      steps: steps,
    );
    final bytes = (await result.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!.buffer.asUint8List();
    result.dispose();

    final greys = {
      for (var band = 0; band < steps; band++)
        clampChannel8(luminanceOfLstar(bandCentreLstar(band, steps, 0))),
    };
    final seen = <int>{};
    for (var i = 0; i < bytes.length; i += 4) {
      seen.add(bytes[i]);
    }
    expect(seen.difference(greys), isEmpty);
    // The ring is dark and its middle is not.
    int at(int x, int y) => bytes[(y * side + x) * 4];
    expect(at(120, 40), greys.reduce(math.min));
    expect(at(120, 120), isNot(greys.reduce(math.min)));
  });

  test('a shape that reaches the side of the picture keeps reaching it: '
      'no sliver of another value along the frame', () async {
    // Rings of value centred off the picture, so every boundary meets the
    // frame on a curve, at an angle — the case straightening pulls inward.
    const side = 300;
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, side + 0.0, side + 0.0),
      Paint()
        ..shader = ui.Gradient.radial(
          const Offset(-40, -60),
          520,
          const [Color(0xFF000000), Color(0xFFFFFFFF)],
          null,
          TileMode.mirror,
        ),
    );
    final picture = recorder.endRecording();
    final source = await picture.toImage(side, side);
    picture.dispose();
    addTearDown(source.dispose);

    final result = await renderBlurredSource(
      source: source,
      outputPx: const Size(side + 0.0, side + 0.0),
      detail: 0.3,
      view: const ViewTransform(),
      smoothing: Smoothing.block,
      steps: 5,
    );
    final bytes = (await result.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!.buffer.asUint8List();
    result.dispose();

    int at(int x, int y) => bytes[(y * side + x) * 4];
    // Each side of the frame against the line two pixels in from it: they
    // may differ only right where a boundary really crosses.
    final sides = <(int Function(int), int Function(int))>[
      ((i) => at(i, 0), (i) => at(i, 2)),
      ((i) => at(i, side - 1), (i) => at(i, side - 3)),
      ((i) => at(0, i), (i) => at(2, i)),
      ((i) => at(side - 1, i), (i) => at(side - 3, i)),
    ];
    for (final (frame, inside) in sides) {
      final crossings = [
        for (var i = 1; i < side; i++)
          if (inside(i) != inside(i - 1)) i,
      ];
      for (var i = 0; i < side; i++) {
        if (crossings.any((c) => (c - i).abs() <= 3)) continue;
        expect(frame(i), inside(i), reason: 'at $i along the frame');
      }
    }
  });
}
