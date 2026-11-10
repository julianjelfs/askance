import 'dart:ui' as ui;

import 'package:askance/engine/deferred_disposer.dart';
import 'package:askance/engine/engine.dart';
import 'package:askance/engine/families.dart';
import 'package:askance/engine/lstar.dart';
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
    const settings = StudySettings(steps: 5, shadowSteps: 2);
    expect(StudySettings.fromJson(settings.toJson()), settings);
    final old = settings.toJson()..remove('shadowSteps');
    expect(StudySettings.fromJson(old).shadowSteps, isNull);
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

  test('the outline runs along the families\' boundary and no other', () async {
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
      settings: const StudySettings(steps: 3, shadowSteps: 1),
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

    int alphaAt(int x) => bytes[(16 * 96 + x) * 4 + 3];
    // Shadow is the first stripe alone: the line is at x = 32.
    expect(alphaAt(31), 255);
    expect(alphaAt(32), 255);
    // Two lights meet at x = 64, which is no line between families.
    expect(alphaAt(63), 0);
    expect(alphaAt(64), 0);
    // Away from any boundary, the outline leaves the picture alone.
    expect(alphaAt(16), 0);
    expect(alphaAt(48), 0);
  });
}
