import 'dart:typed_data';

import 'package:askance/data/study_repository.dart';
import 'package:askance/model/study.dart';
import 'package:askance/state/providers.dart';
import 'package:askance/theme.dart';
import 'package:askance/ui/onboarding/onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Crossfading the onboarding copy left both panels legible at once and the
/// two blocks of text sat on top of each other. One has to go before the next
/// arrives.
class _Fake implements StudyRepository {
  @override
  Future<List<Study>> loadStudies() async => const [];
  @override
  Future<void> saveStudies(List<Study> next) async {}
  @override
  Future<String> putImage(Uint8List bytes, {String extension = 'jpg'}) async =>
      'k';
  @override
  Future<Uint8List?> readImage(String key) async => null;
  @override
  Future<void> deleteImage(String key) async {}
  @override
  Future<bool> loadOnboardingSeen() async => false;
  @override
  Future<void> saveOnboardingSeen(bool seen) async {}
}

void main() {
  const first = 'Value before colour.';
  const second = 'Look askance.';

  /// How much of [title] is actually being shown, following every Opacity
  /// above it.
  double visibility(WidgetTester tester, String title) {
    if (find.text(title).evaluate().isEmpty) return 0;
    var opacity = 1.0;
    tester.element(find.text(title)).visitAncestorElements((element) {
      final widget = element.widget;
      if (widget is Opacity) opacity *= widget.opacity;
      if (widget is FadeTransition) opacity *= widget.opacity.value;
      return true;
    });
    return opacity;
  }

  testWidgets('the panels crossfade, quickly and completely', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(_Fake())],
        child: const MaterialApp(
          home: DesignScale(factor: 1.28, child: OnboardingScreen()),
        ),
      ),
    );
    // Let the pane's entrance fade and slide finish before measuring.
    await tester.pump(const Duration(milliseconds: 700));

    expect(visibility(tester, first), 1);
    expect(visibility(tester, second), 0);

    await tester.tap(find.text('Next'));
    await tester.pump(); // start the switcher's clock
    await tester.pump(const Duration(milliseconds: 90));

    // Mid-handover the new copy is arriving while the old departs: a
    // crossfade, not a cut and not a blank.
    expect(visibility(tester, second), greaterThan(0));
    expect(visibility(tester, second), lessThan(1));

    await tester.pumpAndSettle();
    expect(visibility(tester, first), 0);
    expect(visibility(tester, second), 1);
  });
}
