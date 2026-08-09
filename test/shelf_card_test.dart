import 'dart:typed_data';

import 'package:askance/data/study_repository.dart';
import 'package:askance/model/study.dart';
import 'package:askance/state/providers.dart';
import 'package:askance/theme.dart';
import 'package:askance/ui/shelf/study_card.dart';
import 'package:askance/ui/widgets/glyphs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoImages implements StudyRepository {
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
  Future<bool> loadEntitlement() async => true;
  @override
  Future<void> saveEntitlement(bool value) async {}
  @override
  Future<bool> loadOnboardingSeen() async => true;
  @override
  Future<void> saveOnboardingSeen(bool seen) async {}
}

void main() {
  final study = Study(
    id: 'a',
    name: 'A study',
    date: DateTime(2026, 8, 9),
    imageKey: 'a.jpg',
    settings: const StudySettings(),
  );

  Future<void> pumpCard(WidgetTester tester, {VoidCallback? onDelete}) =>
      tester.pumpWidget(
        ProviderScope(
          overrides: [repositoryProvider.overrideWithValue(_NoImages())],
          child: MaterialApp(
            home: DesignScale(
              factor: 1,
              child: Center(
                child: SizedBox(
                  width: 160,
                  child: StudyCard(
                    study: study,
                    onOpen: () {},
                    onDelete: onDelete ?? () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  /// The colour of the card's own outline.
  Color cardBorder(WidgetTester tester) {
    final container = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(StudyCard),
            matching: find.byType(Container),
          )
          .first,
    );
    final decoration = container.decoration! as BoxDecoration;
    return decoration.border!.top.color;
  }

  testWidgets('a card advertises deletion rather than hiding it in a hold', (
    tester,
  ) async {
    await pumpCard(tester);
    await tester.pump();

    final trash = find.byWidgetPredicate(
      (w) => w is GlyphIcon && w.glyph == Glyph.trash,
    );
    expect(trash, findsOneWidget);
    expect(tester.widget<GlyphIcon>(trash).color, AskanceColors.accent);
  });

  testWidgets('the trash asks first, exactly as a long press does', (
    tester,
  ) async {
    var deleted = false;
    await pumpCard(tester, onDelete: () => deleted = true);
    await tester.pump();

    await tester.tap(
      find.byWidgetPredicate((w) => w is GlyphIcon && w.glyph == Glyph.trash),
    );
    await tester.pumpAndSettle();

    expect(deleted, isFalse, reason: 'a tap must not delete on its own');
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(deleted, isTrue);
  });

  testWidgets('asking turns the card\'s own rule red, and adds no second one', (
    tester,
  ) async {
    await pumpCard(tester);
    await tester.pump();
    expect(cardBorder(tester), AskanceColors.dividerLight);

    await tester.longPress(find.byType(StudyThumbnail));
    await tester.pumpAndSettle();

    expect(cardBorder(tester), AskanceColors.accent);

    // The panel that covers the card draws no outline of its own, so the red
    // rule is the card's, not a second one sitting inside the grey one.
    final overlay = tester
        .widgetList<Container>(find.byType(Container))
        .where((c) => c.color == const Color(0xF2F3F2F2));
    expect(overlay, hasLength(1), reason: 'the confirm panel');
    expect(overlay.single.decoration, isNull);
    expect(overlay.single.foregroundDecoration, isNull);
  });
}
