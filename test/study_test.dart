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
      expect(s.gridDivisions, 4);
      expect(s.numbers, isTrue);
      expect(s.splitPosition, 0.5);
    });

    test('round-trips through JSON', () {
      const original = StudySettings(
        steps: 6,
        scale: ValueScale.sepia,
        detail: 0.42,
        mode: ViewMode.skeleton,
        grid: GridMode.diamond,
        gridDivisions: 9,
        numbers: false,
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
        'gridDivisions': 1,
        'detail': -4.0,
        'splitPosition': -1.0,
      });
      expect(low.steps, StudySettings.minSteps);
      expect(low.gridDivisions, StudySettings.minDivisions);
      expect(low.detail, 0);
      expect(low.splitPosition, 0);

      final high = StudySettings.fromJson(const {
        'steps': 99,
        'gridDivisions': 99,
        'detail': 4.0,
        'splitPosition': 9.0,
      });
      expect(high.steps, StudySettings.maxSteps);
      expect(high.gridDivisions, StudySettings.maxDivisions);
      expect(high.detail, 1);
      expect(high.splitPosition, 1);
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
