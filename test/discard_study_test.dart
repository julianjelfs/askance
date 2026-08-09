import 'dart:typed_data';

import 'package:askance/data/study_repository.dart';
import 'package:askance/model/study.dart';
import 'package:askance/state/providers.dart';
import 'package:askance/ui/share/share_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Going back from a study that has never been kept asks what to do with it,
/// because the photograph only exists in that session.
class _FakeRepository implements StudyRepository {
  List<Study> studies = const [];
  bool unlocked = false;

  @override
  Future<List<Study>> loadStudies() async => studies;

  @override
  Future<void> saveStudies(List<Study> next) async => studies = next;

  @override
  Future<String> putImage(Uint8List bytes, {String extension = 'jpg'}) async =>
      'image.$extension';

  @override
  Future<Uint8List?> readImage(String key) async => null;

  @override
  Future<void> deleteImage(String key) async {}

  @override
  Future<bool> loadEntitlement() async => unlocked;

  @override
  Future<void> saveEntitlement(bool value) async => unlocked = value;

  @override
  Future<bool> loadOnboardingSeen() async => true;

  @override
  Future<void> saveOnboardingSeen(bool seen) async {}
}

void main() {
  Future<ShareOutcome?> openSheet(
    WidgetTester tester, {
    required bool offerDiscard,
    required _FakeRepository repository,
  }) async {
    ShareOutcome? outcome;
    var opened = false;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () async {
                opened = true;
                outcome = await showShareSheet(
                  context,
                  ref,
                  offerDiscard: offerDiscard,
                );
              },
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(GestureDetector).first);
    await tester.pumpAndSettle();
    expect(opened, isTrue);
    return outcome;
  }

  testWidgets('the way out offers to discard, and says what is at stake', (
    tester,
  ) async {
    final repository = _FakeRepository();
    await openSheet(tester, offerDiscard: true, repository: repository);

    expect(find.text('Keep this study?'), findsOneWidget);
    expect(find.text('Discard'), findsOneWidget);
    expect(
      find.textContaining('not on the shelf yet'),
      findsOneWidget,
      reason: 'the consequence should be spelled out',
    );
  });

  testWidgets('pressing SHARE on a kept study offers no discard', (
    tester,
  ) async {
    final repository = _FakeRepository();
    await openSheet(tester, offerDiscard: false, repository: repository);

    expect(find.text('Share this study'), findsOneWidget);
    expect(find.text('Discard'), findsNothing);
  });

  testWidgets('discarding is free even when the shelf is locked', (
    tester,
  ) async {
    final repository = _FakeRepository()..unlocked = false;
    ShareOutcome? outcome;
    var settled = false;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () async {
                outcome = await showShareSheet(context, ref, offerDiscard: true);
                settled = true;
              },
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(GestureDetector).first);
    await tester.pumpAndSettle();

    // The paywall is up, which is the point: this is the moment the shelf is
    // worth something. Discarding still must not cost anything.
    expect(find.textContaining('ONE PAYMENT'), findsOneWidget);

    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(settled, isTrue);
    expect(outcome, ShareOutcome.discarded);
    expect(repository.unlocked, isFalse, reason: 'no purchase was started');
  });
}
