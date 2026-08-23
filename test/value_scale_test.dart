import 'package:askance/engine/lstar.dart';
import 'package:askance/engine/value_scale.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('L*', () {
    test('black and white anchor the range', () {
      expect(lstarOfSrgb8(0, 0, 0), closeTo(0, 0.001));
      expect(lstarOfSrgb8(255, 255, 255), closeTo(100, 0.001));
    });

    test(
      'mid grey sits near Munsell value 5, not at 50% of the byte range',
      () {
        // sRGB 128 is ~53.6 L*, and L* ~= 10 x Munsell V.
        expect(lstarOfSrgb8(128, 128, 128), closeTo(53.585, 0.01));
      },
    );

    test('green reads far lighter than blue at equal 8-bit value', () {
      expect(lstarOfSrgb8(0, 255, 0), greaterThan(lstarOfSrgb8(0, 0, 255)));
    });

    test('luminance and L* round-trip', () {
      for (final l in [0.0, 5.0, 8.0, 20.0, 53.585, 90.0, 100.0]) {
        expect(lstarOfLuminance(luminanceOfLstar(l)), closeTo(l, 0.001));
      }
    });
  });

  // The scale is continuous now; these sample the legacy hues plus a spread
  // of arbitrary ones.
  final scales = [
    ValueScale.grey,
    ValueScale.warm,
    ValueScale.sepia,
    ValueScale.cool,
    ValueScale.tinted(75),
    ValueScale.tinted(140),
    ValueScale.tinted(288),
  ];

  group('ramp', () {
    test('grey at 3 steps gives the specified middle band', () {
      // The README's sanity check. sRGB interpolation gives ~132 here.
      final ramp = ValueScale.grey.ramp(3);
      final mid = ramp[1];
      expect(
        [(mid.r * 255).round(), (mid.g * 255).round(), (mid.b * 255).round()],
        [122, 120, 120],
      );
    });

    test('endpoints are preserved exactly at every step count', () {
      for (final scale in scales) {
        for (var n = 2; n <= 7; n++) {
          final ramp = scale.ramp(n);
          expect(
            ramp.first.toARGB32(),
            scale.dark.toARGB32(),
            reason: '$scale n=$n dark',
          );
          expect(
            ramp.last.toARGB32(),
            scale.light.toARGB32(),
            reason: '$scale n=$n light',
          );
        }
      }
    });

    test('bands are evenly spaced in L*, and ascend', () {
      for (final scale in scales) {
        for (var n = 3; n <= 7; n++) {
          final ls = scale
              .ramp(n)
              .map(
                (c) => lstarOfSrgb8(
                  (c.r * 255).round(),
                  (c.g * 255).round(),
                  (c.b * 255).round(),
                ),
              )
              .toList();
          final expectedStep = (ls.last - ls.first) / (n - 1);
          for (var i = 1; i < n; i++) {
            expect(
              ls[i] - ls[i - 1],
              closeTo(expectedStep, 0.4),
              reason: '$scale n=$n band $i',
            );
          }
        }
      }
    });

    test('band count matches the step count across the whole 2..7 range', () {
      for (var n = 2; n <= 7; n++) {
        expect(ValueScale.grey.ramp(n).length, n);
      }
    });

    test('moving the tint never moves a value', () {
      // Every scale shares the grey endpoints' L*, so each band holds its L*
      // whatever the hue — the whole justification for a continuous control.
      final reference = ValueScale.grey.lstarTargets(5);
      for (final scale in scales) {
        final ls = scale
            .ramp(5)
            .map(
              (c) => lstarOfSrgb8(
                (c.r * 255).round(),
                (c.g * 255).round(),
                (c.b * 255).round(),
              ),
            )
            .toList();
        for (var i = 0; i < 5; i++) {
          expect(ls[i], closeTo(reference[i], 0.6), reason: '$scale band $i');
        }
      }
    });

    test('a tinted mid band actually carries the tint', () {
      final mid = ValueScale.warm.ramp(3)[1];
      expect(mid.r, greaterThan(mid.b), reason: 'warm should lean red');
      final cool = ValueScale.cool.ramp(3)[1];
      expect(cool.b, greaterThan(cool.r), reason: 'cool should lean blue');
    });
  });

  group('persistence', () {
    test('grey and tints round-trip', () {
      expect(ValueScale.fromJson(ValueScale.grey.toJson()), ValueScale.grey);
      final tint = ValueScale.tinted(123.5);
      expect(ValueScale.fromJson(tint.toJson()), tint);
    });

    test('the old enum names map onto their fixed hues', () {
      expect(ValueScale.fromJson('graphite'), ValueScale.grey);
      expect(ValueScale.fromJson('warm'), ValueScale.warm);
      expect(ValueScale.fromJson('sepia'), ValueScale.sepia);
      expect(ValueScale.fromJson('cool'), ValueScale.cool);
      expect(ValueScale.fromJson('chartreuse'), ValueScale.grey);
      expect(ValueScale.fromJson(null), ValueScale.grey);
    });
  });
}
