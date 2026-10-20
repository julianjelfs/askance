import 'package:askance/engine/engine.dart';
import 'package:askance/engine/lstar.dart';
import 'package:askance/engine/random_ramp.dart';
import 'package:askance/engine/value_scale.dart';
import 'package:askance/model/study.dart';
import 'package:askance/state/canvas_session.dart';
import 'package:askance/ui/canvas/tool_panel.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The palette swatch is the list of colours to mix, so it must show exactly
/// the colours the picture is painted in — the painter reads the same
/// [StudySettings.palette] — and nothing else.
void main() {
  final scale = ValueScale.tinted(140);
  List<Color> random(int steps) =>
      randomRamp(scale: scale, steps: steps, seed: 1234);

  test('palette follows whichever colouring is on screen', () {
    final base = StudySettings(steps: 5, scale: scale, randomSeed: 1234);
    expect(base.palette, scale.ramp(5));
    expect(base.copyWith(mode: ViewMode.random).palette, random(5));
    expect(
      base.copyWith(mode: ViewMode.split, splitBase: ViewMode.random).palette,
      random(5),
    );
    expect(
      base.copyWith(mode: ViewMode.skeleton, splitBase: ViewMode.value).palette,
      scale.ramp(5),
    );
  });

  testWidgets('swatch shows one chip per value, each a palette colour', (
    tester,
  ) async {
    final session = CanvasSession()
      ..settings = StudySettings(
        steps: 4,
        scale: scale,
        mode: ViewMode.random,
        randomSeed: 1234,
      );
    addTearDown(session.dispose);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 44,
            child: PaletteSwatch(session: session, chipHeight: 32),
          ),
        ),
      ),
    );

    final shown = tester
        .widgetList<Container>(find.byType(Container))
        .map((c) => (c.decoration as BoxDecoration?)?.color)
        .nonNulls
        .toList();
    // Lightest at the top, as a value scale stands.
    expect(shown, random(4).reversed.toList());
  });

  test('isolating a band keeps its colour alone and hides the rest', () {
    final palette = scale.ramp(5);
    double lstar(Color c) => lstarOfSrgb8(
      (c.r * 255).round(),
      (c.g * 255).round(),
      (c.b * 255).round(),
    );
    for (final band in [0, 4]) {
      final shown = isolateBand(palette, band);
      expect(shown[band], palette[band]);
      final rest = {
        for (var i = 0; i < shown.length; i++)
          if (i != band) shown[i],
      };
      // One flat colour for everything else, far enough from the kept band
      // in value that the darkest and the palest both still read.
      expect(rest, hasLength(1));
      expect(
        (lstar(rest.single) - lstar(palette[band])).abs(),
        greaterThan(40),
      );
    }
  });

  testWidgets('tapping a colour isolates it, tapping again shows them all, '
      'and the study never records it', (tester) async {
    final session = CanvasSession()
      ..settings = StudySettings(steps: 4, scale: scale);
    addTearDown(session.dispose);
    final before = session.settled;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 44,
            child: ListenableBuilder(
              listenable: session,
              builder: (_, _) =>
                  PaletteSwatch(session: session, chipHeight: 32),
            ),
          ),
        ),
      ),
    );

    final chips = find.byType(GestureDetector);
    // The top chip is the lightest, which is the last band.
    await tester.tap(chips.first);
    expect(session.isolatedBand, 3);
    expect(session.settled, before);

    await tester.tap(chips.first);
    expect(session.isolatedBand, isNull);

    await tester.tap(chips.last);
    expect(session.isolatedBand, 0);
    session.setSteps(5);
    expect(session.isolatedBand, isNull, reason: 'band 0 of 4 is not of 5');
  });
}
