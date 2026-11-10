import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:askance/engine/deferred_disposer.dart';
import 'package:askance/engine/engine.dart';
import 'package:askance/engine/families.dart';
import 'package:askance/engine/lstar.dart';
import 'package:askance/engine/regions.dart';
import 'package:askance/engine/value_painter.dart';
import 'package:askance/engine/value_scale.dart';
import 'package:askance/model/study.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// Light and shadow families: the darkest few steps are shadow, the rest
/// light, and the line between them sits on one of the band boundaries the
/// value map already has.
void main() {
  double lstarOf(Color c) => lstarOfSrgb8(
    (c.r * 255).round(),
    (c.g * 255).round(),
    (c.b * 255).round(),
  );

  test('the family tint never moves a value', () {
    for (var steps = 2; steps <= 7; steps++) {
      final targets = ValueScale.grey.lstarTargets(steps);
      for (var shadow = 1; shadow < steps; shadow++) {
        final ramp = familyRamp(ValueScale.grey, steps, shadow);
        for (var i = 0; i < steps; i++) {
          // Half a tolerance for the 8-bit rounding, as the random ramp has.
          expect(
            lstarOf(ramp[i]),
            closeTo(targets[i], 0.6),
            reason: 'steps $steps, shadow $shadow, band $i',
          );
        }
      }
    }
  });

  test('a study with families is painted in the family ramp', () {
    const settings = StudySettings(steps: 5, shadowSteps: 2);
    expect(settings.palette, familyRamp(ValueScale.grey, 5, 2));
    // The middle band of five is the first light: warm, not cool.
    final halftone = settings.palette[2];
    expect(halftone.r, greaterThan(halftone.b));
    final shadow = settings.palette[1];
    expect(shadow.b, greaterThan(shadow.r));
  });

  test('each family keeps at least one step whatever the steps', () {
    const settings = StudySettings(steps: 7, shadowSteps: 6);
    expect(settings.shadowBands, 6);
    expect(settings.copyWith(steps: 3).shadowBands, 2);
    expect(settings.copyWith(steps: 2).shadowBands, 1);
    // Back up to seven, the line is where it was left.
    expect(settings.copyWith(steps: 3).copyWith(steps: 7).shadowBands, 6);
  });

  test('families survive a saved study; an older one opens without', () {
    const settings = StudySettings(
      steps: 5,
      shadowSteps: 2,
      familyLine: 0.42,
      familyGap: true,
    );
    expect(StudySettings.fromJson(settings.toJson()), settings);
    final old = settings.toJson()
      ..remove('shadowSteps')
      ..remove('familyLine')
      ..remove('familyGap');
    expect(StudySettings.fromJson(old).shadowSteps, isNull);
    expect(StudySettings.fromJson(old).split, isNull);
    expect(
      StudySettings.fromJson(
        settings.toJson()..['shadowSteps'] = 0,
      ).shadowSteps,
      1,
    );
  });

  test('the dropper names the family and the step within it', () {
    String label(int band, int? shadow) =>
        BandPlace(band: band, steps: 5, shadowBands: shadow).label;
    expect(label(0, 2), 'Shadow · 1 of 2');
    expect(label(1, 2), 'Shadow · 2 of 2');
    expect(label(2, 2), 'Light · 1 of 3');
    expect(label(4, 2), 'Light · 3 of 3');
    expect(label(3, null), 'Value 4 of 5');
  });

  /// Three upright stripes, one in each band of three: L* about 15, 54
  /// and 90.
  Future<ui.Image> stripes() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    for (final (i, grey) in [40, 128, 228].indexed) {
      canvas.drawRect(
        Rect.fromLTWH(i * 32.0, 0, 32, 32),
        Paint()..color = Color.fromARGB(255, grey, grey, grey),
      );
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(96, 32);
    picture.dispose();
    return image;
  }

  test('the dropper reads the band the value map shows', () async {
    final image = await stripes();
    addTearDown(image.dispose);
    for (final (x, band) in [(10.0, 0), (48.0, 1), (90.0, 2)]) {
      final (r, g, b) = (await readPixel(image, Offset(x, 16)))!;
      expect(bandOfColour(r, g, b, 3, bias: 0, contrast: 0), band);
    }
    expect(await readPixel(image, const Offset(96, 16)), isNull);
  });

  /// The alpha along the middle row of the family outline over [stripes].
  Future<List<int>> outlineRow(StudySettings settings) async {
    final shader = await ValueShader.load();
    final source = await stripes();
    const output = Size(96, 32);
    const view = ViewTransform();
    final disposer = DeferredDisposer();
    final recorder = ui.PictureRecorder();
    FamilyOutlinePainter(
      shader: shader,
      source: source,
      // The source itself, unblurred, so the boundaries stay where drawn.
      blurred: source,
      settings: settings,
      view: view,
      devicePixelRatio: 1,
      disposer: disposer,
    ).paint(Canvas(recorder, Offset.zero & output), output);
    final picture = recorder.endRecording();
    final rendered = await picture.toImage(96, 32);
    picture.dispose();
    final bytes = (await rendered.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!.buffer.asUint8List();
    rendered.dispose();
    disposer.disposeAll();
    source.dispose();

    return [for (var x = 0; x < 96; x++) bytes[(16 * 96 + x) * 4 + 3]];
  }

  test('the outline runs along the families\' boundary and no other', () async {
    final alpha = await outlineRow(
      const StudySettings(steps: 3, shadowSteps: 1),
    );
    // Shadow is the first stripe alone: the line is at x = 32.
    expect(alpha[31], 255);
    expect(alpha[32], 255);
    // Two lights meet at x = 64, which is no line between families.
    expect(alpha[63], 0);
    expect(alpha[64], 0);
    // Away from any boundary, the outline leaves the picture alone.
    expect(alpha[16], 0);
    expect(alpha[48], 0);
  });

  test(
    'a free line bands each family on its own, on the GPU and off it',
    () async {
      // The line above the middle stripe's 54 puts it in the shadow, which
      // the even ladder of three has as the middle of three.
      const settings = StudySettings(steps: 3, shadowSteps: 1, familyLine: 0.6);
      final alpha = await outlineRow(settings);
      expect(alpha[32], 0);
      expect(alpha[64], 255);
      final image = await stripes();
      addTearDown(image.dispose);
      final bands = [
        for (final x in [10.0, 48.0, 90.0])
          if (await readPixel(image, Offset(x, 16)) case (
            final r,
            final g,
            final b,
          ))
            bandOfColour(
              r,
              g,
              b,
              3,
              bias: 0,
              contrast: 0,
              split: settings.split,
            ),
      ];
      // The light family's two steps share 0.6..1: 90 is the lighter.
      expect(bands, [0, 0, 2]);
    },
  );

  test('the band map follows a free line as the shader does', () {
    // The shader's rule with a line, written out longhand.
    int shaderBand(int r, int g, int b, int steps, FamilySplit split) {
      final t = lstarOfSrgb8(r, g, b) / 100;
      final (:shadow, :at) = split;
      if (t < at) return (t / at * shadow).floor().clamp(0, shadow - 1);
      final light = steps - shadow;
      return shadow + ((t - at) / (1 - at) * light).floor().clamp(0, light - 1);
    }

    final rgba = Uint8List(256 * 4);
    for (var v = 0; v < 256; v++) {
      rgba.setAll(v * 4, [v, v, v, 255]);
    }
    for (final (steps, split) in [
      (5, (shadow: 2, at: 0.31)),
      (4, (shadow: 3, at: 0.62)),
      (7, (shadow: 1, at: 0.08)),
    ]) {
      final map = bandsFromRgba(
        ByteData.sublistView(rgba),
        256,
        1,
        steps,
        split: split,
      );
      for (var v = 0; v < 256; v++) {
        expect(
          map.bands[v],
          shaderBand(v, v, v, steps, split),
          reason: 'steps $steps, $split, grey $v',
        );
      }
    }
    // A line on a band boundary is the even ladder.
    for (var k = 1; k < 5; k++) {
      expect(toneCut(k, 5, (shadow: 2, at: 2 / 5)), closeTo(k / 5, 1e-12));
    }
  });

  test('a gap leaves the value at the line out of the palette', () {
    final wide = ValueScale.grey.lstarTargets(6);
    final ramp = familyRamp(ValueScale.grey, 5, 2, gap: true);
    expect(ramp, hasLength(5));
    for (final (i, colour) in ramp.indexed) {
      expect(lstarOf(colour), closeTo(wide[i < 2 ? i : i + 1], 0.6));
    }
  });

  test('the line starts in the valley between the darks and the lights', () {
    final histogram = List<int>.filled(256, 0);
    for (var i = 0; i < 40; i++) {
      histogram[30 + i] += 3;
      histogram[180 + i] += 2;
    }
    final cut = otsu(histogram) * 256;
    expect(cut, greaterThan(69));
    expect(cut, lessThanOrEqualTo(180));
  });
}
