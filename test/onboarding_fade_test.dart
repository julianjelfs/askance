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

  testWidgets('the panels never overlap while one replaces the other', (
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
    await tester.pump();

    expect(visibility(tester, first), 1);
    expect(visibility(tester, second), 0);

    await tester.tap(find.text('Next'));

    // Step through the whole handover. At no point should both be readable.
    for (var elapsed = 0; elapsed < 500; elapsed += 20) {
      await tester.pump(const Duration(milliseconds: 20));
      final a = visibility(tester, first);
      final b = visibility(tester, second);
      expect(
        a < 0.02 || b < 0.02,
        isTrue,
        reason:
            'at ${elapsed}ms both panels were legible: '
            '${a.toStringAsFixed(2)} and ${b.toStringAsFixed(2)}',
      );
    }

    await tester.pumpAndSettle();
    expect(visibility(tester, first), 0);
    expect(visibility(tester, second), 1);
  });
}
