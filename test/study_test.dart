import 'package:askance/engine/engine.dart';
import 'package:askance/engine/value_scale.dart';
import 'package:askance/model/study.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StudySettings', () {
    test('defaults match the state table', () {
      const s = StudySettings();
      expect(s.steps, 3);
      expect(s.scale, ValueScale.grey);
      expect(s.detail, 0.5);
      expect(s.mode, ViewMode.value);
      expect(s.grid, GridMode.off);
      expect(s.gridLevel, 2);
      expect(s.gridDivisions, 4);
      expect(s.skeletonFill, 0);
      expect(s.splitPosition, 0.5);
    });

    test('round-trips through JSON', () {
      const original = StudySettings(
        steps: 6,
        scale: ValueScale.sepia,
        detail: 0.42,
        mode: ViewMode.skeleton,
        grid: GridMode.diagonals,
        gridLevel: 3,
        skeletonFill: 3,
        lockDetail: true,
        splitPosition: 0.25,
      );
      expect(StudySettings.fromJson(original.toJson()), original);
    });

    test(
      'a malformed manifest falls back to defaults rather than throwing',
      () {
        final s = StudySettings.fromJson(const {
          'steps': 'lots',
          'scale': 'chartreuse',
          'mode': 'nonsense',
        });
        expect(s.steps, 3);
        expect(s.scale, ValueScale.grey);
        expect(s.mode, ViewMode.value);
      },
    );

    test('out-of-range values are clamped to the documented ranges', () {
      final low = StudySettings.fromJson(const {
        'steps': 0,
        'gridLevel': 0,
        'detail': -4.0,
        'splitPosition': -1.0,
      });
      expect(low.steps, StudySettings.minSteps);
      expect(low.gridLevel, StudySettings.minGridLevel);
      expect(low.detail, 0);
      expect(low.splitPosition, 0);

      final high = StudySettings.fromJson(const {
        'steps': 99,
        'gridLevel': 99,
        'detail': 4.0,
        'splitPosition': 9.0,
      });
      expect(high.steps, StudySettings.maxSteps);
      expect(high.gridLevel, StudySettings.maxGridLevel);
      expect(high.detail, 1);
      expect(high.splitPosition, 1);
    });
  });

  group('StudySettings legacy grid', () {
    test('square and diamond become lines and diagonals', () {
      expect(
        StudySettings.fromJson(const {'grid': 'square'}).grid,
        GridMode.lines,
      );
      expect(
        StudySettings.fromJson(const {'grid': 'diamond'}).grid,
        GridMode.diagonals,
      );
      expect(
        StudySettings.fromJson(const {'grid': 'nonsense'}).grid,
        GridMode.off,
      );
    });

    test('a division count becomes the nearest level', () {
      int levelFor(int divisions) =>
          StudySettings.fromJson({'gridDivisions': divisions}).gridLevel;
      expect(levelFor(2), 1);
      expect(levelFor(3), 1);
      expect(levelFor(4), 2);
      expect(levelFor(5), 2);
      expect(levelFor(6), 2);
      expect(levelFor(7), 3);
      expect(levelFor(10), 3);
      expect(levelFor(99), 4);
    });

    test('a level wins over a division count when both are present', () {
      expect(
        StudySettings.fromJson(const {
          'gridLevel': 1,
          'gridDivisions': 10,
        }).gridLevel,
        1,
      );
    });
  });

  group('Study', () {
    final study = Study(
      id: 'a',
      name: 'Portrait, yellow wall',
      date: DateTime(2026, 8, 8),
      imageKey: '123.jpg',
      settings: const StudySettings(),
    );

    test('caption reads as designed', () {
      expect(study.caption, '3 values · grey · 8 Aug');
    });

    test('round-trips through JSON', () {
      final restored = Study.fromJson(study.toJson())!;
      expect(restored.id, study.id);
      expect(restored.name, study.name);
      expect(restored.imageKey, study.imageKey);
      expect(restored.date, study.date);
      expect(restored.settings, study.settings);
    });

    test('an entry with no id or no image is dropped, not thrown on', () {
      expect(Study.fromJson(const {'name': 'orphan'}), isNull);
      expect(Study.fromJson(const {'id': 'a'}), isNull);
      expect(Study.fromJson(const {'id': 'a', 'imageKey': ''}), isNull);
      expect(Study.fromJson(const {'id': 42, 'imageKey': 'x.jpg'}), isNull);
    });

    test('a usable entry survives missing optional fields', () {
      final restored = Study.fromJson(const {'id': 'a', 'imageKey': 'x.jpg'})!;
      expect(restored.name, 'Untitled study');
      expect(restored.settings, const StudySettings());
    });
  });

  group('export filenames', () {
    test('slugify strips punctuation and collapses separators', () {
      expect(slugify('Portrait, yellow wall'), 'portrait-yellow-wall');
      expect(slugify('  Study #2 — take 3!  '), 'study-2-take-3');
      expect(slugify('***'), 'study');
    });
  });
}
