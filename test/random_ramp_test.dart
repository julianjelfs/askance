import 'package:askance/engine/engine.dart';
import 'package:askance/engine/lstar.dart';
import 'package:askance/engine/random_ramp.dart';
import 'package:askance/engine/value_scale.dart';
import 'package:askance/model/study.dart';
import 'package:flutter_test/flutter_test.dart';

/// The whole promise of the RANDOM mode is that the colours are arbitrary and
/// the values are not: every band must sit on exactly the L* the grey ramp
/// solves for, whatever hue the deal turned up.
void main() {
  double lstarOf(c) => lstarOfSrgb8(
    (c.r * 255).round(),
    (c.g * 255).round(),
    (c.b * 255).round(),
  );

  test('every band lands on the grey ramp\'s L*, across scales and seeds', () {
    final scales = [
      ValueScale.grey,
      ValueScale.warm,
      ValueScale.cool,
      ValueScale.tinted(140),
    ];
    for (final scale in scales) {
      for (var n = 2; n <= 7; n++) {
        final targets = scale.lstarTargets(n);
        for (var seed = 0; seed < 20; seed++) {
          final ramp = randomRamp(scale: scale, steps: n, seed: seed);
          expect(ramp.length, n);
          for (var i = 0; i < n; i++) {
            // Half a tolerance for the 8-bit rounding each channel takes on
            // the way out; the solve itself is exact.
            expect(
              lstarOf(ramp[i]),
              closeTo(targets[i], 0.6),
              reason: '$scale n=$n seed=$seed band $i',
            );
          }
        }
      }
    }
  });

  test('the same seed deals the same palette', () {
    final a = randomRamp(scale: ValueScale.grey, steps: 5, seed: 7);
    final b = randomRamp(scale: ValueScale.grey, steps: 5, seed: 7);
    for (var i = 0; i < 5; i++) {
      expect(a[i].toARGB32(), b[i].toARGB32());
    }
  });

  test('a new seed deals a new palette', () {
    final a = randomRamp(scale: ValueScale.grey, steps: 5, seed: 0);
    final b = randomRamp(scale: ValueScale.grey, steps: 5, seed: 1);
    expect(
      List.generate(5, (i) => a[i].toARGB32()),
      isNot(List.generate(5, (i) => b[i].toARGB32())),
    );
  });

  test('mid values come out chromatic, not another grey', () {
    // Near black and white the gamut pins every colour to grey — that is
    // physics, not a bug — but a middle band has room and should use it.
    for (var seed = 0; seed < 20; seed++) {
      final mid = randomRamp(scale: ValueScale.grey, steps: 3, seed: seed)[1];
      final channels = [mid.r, mid.g, mid.b];
      final spread =
          channels.reduce((a, b) => a > b ? a : b) -
          channels.reduce((a, b) => a < b ? a : b);
      expect(spread, greaterThan(0.05), reason: 'seed $seed dealt grey');
    }
  });

  test('the seed survives a round trip through a saved study', () {
    const settings = StudySettings(randomSeed: 42);
    expect(StudySettings.fromJson(settings.toJson()).randomSeed, 42);
    // A manifest from an older build simply starts at the first deal.
    expect(StudySettings.fromJson(const {}).randomSeed, 0);
  });

  test('what a split lays its colours over survives a round trip too', () {
    const settings = StudySettings(splitBase: ViewMode.random);
    expect(
      StudySettings.fromJson(settings.toJson()).splitBase,
      ViewMode.random,
    );
    // Anything that is not a colour ramp falls back to the grey one.
    expect(
      StudySettings.fromJson(const {'splitBase': 'skeleton'}).splitBase,
      ViewMode.value,
    );
    expect(StudySettings.fromJson(const {}).splitBase, ViewMode.value);
  });
}
