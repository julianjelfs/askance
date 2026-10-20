import 'package:askance/model/study.dart';
import 'package:askance/state/canvas_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('picking a stage sets the values and the detail together', () {
    final session = CanvasSession();
    addTearDown(session.dispose);
    for (var i = 0; i < StudySettings.stages.length; i++) {
      session.setStage(i);
      expect(session.settings.steps, StudySettings.stages[i].steps);
      expect(session.settings.detail, StudySettings.stages[i].detail);
      expect(session.settings.stage, i);
    }
  });

  test('moving the values or the detail by hand leaves every stage', () {
    final session = CanvasSession()..setStage(1);
    addTearDown(session.dispose);
    session.setDetail(session.settings.detail + 0.01);
    expect(session.settings.stage, isNull);

    session.setStage(1);
    session.setSteps(session.settings.steps + 1);
    expect(session.settings.stage, isNull);
  });

  test(
    'no stage goes back on the one before: never fewer values or less detail',
    () {
      const stages = StudySettings.stages;
      for (var i = 1; i < stages.length; i++) {
        final (before, after) = (stages[i - 1], stages[i]);
        expect(after.steps, greaterThanOrEqualTo(before.steps));
        expect(after.detail, greaterThanOrEqualTo(before.detail));
        expect(after, isNot(before), reason: 'a stage that changes nothing');
      }
      for (final s in stages) {
        expect(
          s.steps,
          inInclusiveRange(StudySettings.minSteps, StudySettings.maxSteps),
        );
        expect(s.detail, inInclusiveRange(0, 1));
      }
    },
  );
}
