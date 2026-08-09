import 'package:askance/engine/engine.dart';
import 'package:askance/engine/value_scale.dart';
import 'package:askance/model/study.dart';
import 'package:askance/state/canvas_session.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

/// A study on the shelf keeps itself up to date: changing anything about it
/// writes back without a second save step.
void main() {
  Study studyNamed(String id, {StudySettings settings = const StudySettings()}) =>
      Study(
        id: id,
        name: 'Study $id',
        date: DateTime(2026, 8, 9),
        imageKey: '$id.jpg',
        settings: settings,
      );

  ({CanvasSession session, List<(String, StudySettings, String)> writes})
  sessionUnderTest() {
    final writes = <(String, StudySettings, String)>[];
    final session = CanvasSession()
      ..onPersist = (id, settings, name) => writes.add((id, settings, name));
    return (session: session, writes: writes);
  }

  test('an unsaved study never writes: there is nothing to write back to', () {
    fakeAsync((async) {
      final t = sessionUnderTest();
      t.session.startFreshStudy();
      t.session.setSteps(5);
      t.session.setDetail(0.2);
      async.elapse(const Duration(seconds: 2));
      expect(t.writes, isEmpty);
    });
  });

  test('a saved study writes its settled settings back', () {
    fakeAsync((async) {
      final t = sessionUnderTest();
      t.session.openStudy(studyNamed('a'));
      t.session.setSteps(6);
      async.elapse(const Duration(seconds: 2));

      expect(t.writes, hasLength(1));
      expect(t.writes.single.$1, 'a');
      expect(t.writes.single.$2.steps, 6);
    });
  });

  test('a flurry of changes collapses into one write', () {
    fakeAsync((async) {
      final t = sessionUnderTest();
      t.session.openStudy(studyNamed('a'));
      // What dragging the detail slider looks like.
      for (var i = 1; i <= 20; i++) {
        t.session.setDetail(i / 20);
        async.elapse(const Duration(milliseconds: 16));
      }
      async.elapse(const Duration(seconds: 2));

      expect(t.writes, hasLength(1));
      expect(t.writes.single.$2.detail, closeTo(1.0, 1e-9));
    });
  });

  test('every kind of setting counts, including the name', () {
    fakeAsync((async) {
      final t = sessionUnderTest();
      t.session.openStudy(studyNamed('a'));
      t.session
        ..setScale(ValueScale.sepia)
        ..setMode(ViewMode.skeleton)
        ..setGrid(GridMode.diamond)
        ..setGridDivisions(7)
        ..toggleNumbers()
        ..rename('Renamed');
      async.elapse(const Duration(seconds: 2));

      final (_, settings, name) = t.writes.single;
      expect(settings.scale, ValueScale.sepia);
      expect(settings.mode, ViewMode.skeleton);
      expect(settings.grid, GridMode.diamond);
      expect(settings.gridDivisions, 7);
      expect(settings.numbers, isFalse);
      expect(name, 'Renamed');
    });
  });

  test('a split drag writes only once it settles', () {
    fakeAsync((async) {
      final t = sessionUnderTest();
      t.session.openStudy(studyNamed('a'));
      t.session.setSplitPosition(0.3);
      t.session.setSplitPosition(0.4);
      async.elapse(const Duration(seconds: 2));
      expect(t.writes, isEmpty, reason: 'mid-drag positions are not settings');

      t.session.setSplitPosition(0.42, settle: true);
      async.elapse(const Duration(seconds: 2));
      expect(t.writes.single.$2.splitPosition, closeTo(0.42, 1e-9));
    });
  });

  test('view state is not a setting and never writes', () {
    fakeAsync((async) {
      final t = sessionUnderTest();
      t.session.openStudy(studyNamed('a'));
      t.session
        ..setView(const ViewTransform(zoom: 3))
        ..setPeeking(true)
        ..setPeeking(false)
        ..toggleChrome()
        ..toggleTool(CanvasTool.grid);
      async.elapse(const Duration(seconds: 2));
      expect(t.writes, isEmpty);
    });
  });

  test('a pending write cannot land on the study opened after it', () {
    fakeAsync((async) {
      final t = sessionUnderTest();
      t.session.openStudy(studyNamed('a'));
      t.session.setSteps(7);
      // Straight to another study, well inside the debounce.
      t.session.openStudy(studyNamed('b'));
      async.elapse(const Duration(seconds: 2));

      expect(t.writes, hasLength(1));
      expect(t.writes.single.$1, 'a', reason: "study a's change, on study a");
      expect(t.writes.single.$2.steps, 7);
    });
  });

  test('leaving the canvas flushes immediately rather than dropping it', () {
    fakeAsync((async) {
      final t = sessionUnderTest();
      t.session.openStudy(studyNamed('a'));
      t.session.setSteps(4);
      t.session.flushPersist();

      expect(t.writes, hasLength(1), reason: 'written without waiting');
      async.elapse(const Duration(seconds: 2));
      expect(t.writes, hasLength(1), reason: 'and not written twice');
    });
  });
}
