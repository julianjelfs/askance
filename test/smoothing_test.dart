import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:askance/engine/engine.dart';
import 'package:askance/engine/regions.dart';
import 'package:askance/model/study.dart';
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
      // Far enough down the control that there is real simplifying to
      // compare; the ramp is geometric, so 0.55 barely blurs at all.
      detail: 0.2,
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

  /// Structure at several scales across the whole tonal range, the way a
  /// photograph has it. Uniform fine noise will not do: everything in it is
  /// below the flattening window, so ROUGH loses all of it and the two modes
  /// look incomparable for a reason no real picture would reproduce.
  Future<ui.Image> detailLadder(int side) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble()),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble()),
      Paint()..color = const Color(0xFF808080),
    );
    final random = math.Random(7);
    for (final radius in [side / 5, side / 14, side / 40]) {
      final count = (side * side / (radius * radius * 4)).round();
      for (var i = 0; i < count; i++) {
        final v = random.nextInt(256);
        canvas.drawCircle(
          Offset(random.nextDouble() * side, random.nextDouble() * side),
          radius,
          Paint()..color = Color.fromARGB(255, v, v, v),
        );
      }
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(side, side);
    picture.dispose();
    return image;
  }

  /// Kuwahara preserves edges by design,  /// Kuwahara preserves edges by design, so when it was the thing doing the
  /// merging the detail control barely moved the result: the shapes coarsened
  /// but their number stayed put across the whole slider. The blur does the
  /// merging in both modes now, and this is what pins that.
  test('the detail control changes how much is merged, in both modes', () async {
    Future<int> transitions(Smoothing smoothing, double detail) async {
      final source = await detailLadder(256);
      final result = await renderBlurredSource(
        source: source,
        outputPx: const Size(256, 256),
        detail: detail,
        view: const ViewTransform(),
        smoothing: smoothing,
      );
      final bytes = (await result.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final map = bandsFromRgba(bytes, result.width, result.height, 4);
      final y = map.height ~/ 2;
      var changes = 0;
      for (var x = 1; x < map.width; x++) {
        if (map.bands[y * map.width + x] != map.bands[y * map.width + x - 1]) {
          changes++;
        }
      }
      result.dispose();
      source.dispose();
      return changes;
    }

    for (final smoothing in Smoothing.values) {
      final merged = await transitions(smoothing, 0.1);
      final kept = await transitions(smoothing, 0.95);
      expect(
        kept,
        greaterThan(merged * 3),
        reason:
            '$smoothing barely responded to the detail control: '
            '$merged transitions at 0.1 against $kept at 0.95',
      );
    }
  });

  /// The detail control has to mean one thing, not two. Toggling the mode
  /// should change how the shapes read, not how much of the photograph is
  /// left — which it did badly: Kuwahara's window was fixed, so it went on
  /// flattening after the blur had stopped, and ROUGH stalled around 92% of
  /// the picture however far the control was pushed while SMOOTH ran to 100%.
  test('both modes keep about as much of the picture at a given setting', () async {
    final source = await detailLadder(256);
    const output = Size(256, 256);

    Future<BandMap> bandsAt(Smoothing smoothing, double detail) async {
      final result = await renderBlurredSource(
        source: source,
        outputPx: output,
        detail: detail,
        view: const ViewTransform(),
        smoothing: smoothing,
      );
      final bytes = (await result.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final map = bandsFromRgba(bytes, result.width, result.height, 4);
      result.dispose();
      return map;
    }

    // What the picture itself quantises to, with nothing taken away.
    final truth = await bandsAt(Smoothing.gaussian, 1);
    Future<double> kept(Smoothing smoothing, double detail) async {
      final map = await bandsAt(smoothing, detail);
      var same = 0;
      for (var i = 0; i < map.bands.length; i++) {
        if (map.bands[i] == truth.bands[i]) same++;
      }
      return same / map.bands.length;
    }

    for (final detail in [0.25, 0.5, 0.75]) {
      final smooth = await kept(Smoothing.gaussian, detail);
      final rough = await kept(Smoothing.kuwahara, detail);
      expect(
        (smooth - rough).abs(),
        lessThan(0.1),
        reason:
            'at detail $detail the modes are not the same setting: SMOOTH '
            'kept ${(smooth * 100).round()}% and ROUGH '
            '${(rough * 100).round()}%',
      );
    }

    // The floor on the window is what stops the modes converging as the
    // control is raised — without it they were indistinguishable above about
    // half way, and the toggle stopped meaning anything. It costs a little
    // fidelity at the top, deliberately, so the gap here is not a defect.
    final smooth = await kept(Smoothing.gaussian, 1);
    final rough = await kept(Smoothing.kuwahara, 1);
    expect(
      smooth - rough,
      greaterThan(0.02),
      reason: 'at full detail ROUGH no longer flattens anything',
    );
    source.dispose();
  });

  test('a setting saved by a build we no longer ship does not break', () {
    // The full-resolution mode existed long enough to be saved. Anything
    // unrecognised has to land somewhere rather than throw.
    expect(
      StudySettings.fromJson(const {'smoothing': 'kuwaharaFull'}).smoothing,
      Smoothing.gaussian,
    );
  });
}
