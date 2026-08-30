import 'package:askance/engine/value_painter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('grid level follows the zoom', () {
    test('at 1x it is the chosen level', () {
      expect(gridLevelAt(2, 1), 2);
    });

    test('every doubling adds a depth', () {
      expect(gridLevelAt(2, 2), closeTo(3, 1e-9));
      expect(gridLevelAt(2, 4), closeTo(4, 1e-9));
      expect(gridLevelAt(1, 2.82842712), closeTo(2.5, 1e-6));
    });

    test('never deeper than the cap', () {
      expect(gridLevelAt(4, 64), maxGridDepth);
    });
  });

  group('rule strength', () {
    test('the coarsest rules are full strength at 1x', () {
      expect(gridRuleAlpha(1, 1), 1);
      expect(gridRuleAlpha(1, 4), 1);
    });

    test('a depth beyond the level is not drawn', () {
      expect(gridRuleAlpha(3, 2), 0);
      expect(gridRuleAlpha(3, 1.5), 0);
    });

    test(
      'the arriving depth eases in from nothing to its settled strength',
      () {
        expect(gridRuleAlpha(3, 2), 0);
        expect(gridRuleAlpha(3, 2.5), closeTo(gridRuleAlpha(3, 3) / 2, 1e-9));
        expect(gridRuleAlpha(3, 2.999), closeTo(gridRuleAlpha(3, 3), 1e-4));
        // Eased: slow to start.
        expect(gridRuleAlpha(3, 2.1), lessThan(gridRuleAlpha(3, 3) * 0.1));
      },
    );

    test('finer rules are lighter than coarser ones', () {
      for (var depth = 1; depth < 5; depth++) {
        expect(
          gridRuleAlpha(depth + 1, 5),
          lessThanOrEqualTo(gridRuleAlpha(depth, 5)),
        );
      }
      expect(gridRuleAlpha(5, 5), lessThan(gridRuleAlpha(1, 5)));
    });

    test('zooming on only ever strengthens a rule', () {
      for (var level = 3.0; level < 6; level += 0.25) {
        expect(
          gridRuleAlpha(3, level + 0.25),
          greaterThanOrEqualTo(gridRuleAlpha(3, level)),
        );
      }
    });
  });
}
