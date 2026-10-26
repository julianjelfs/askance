import 'dart:ui' as ui;

import 'package:askance/engine/engine.dart';
import 'package:askance/model/study.dart';
import 'package:askance/state/canvas_session.dart';
import 'package:askance/ui/canvas/canvas_surface.dart';
import 'package:askance/ui/study_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'the flip is never saved with a study, and a reopened study is unflipped',
    () {
      final session = CanvasSession()..setFlipped(true);
      addTearDown(session.dispose);

      expect(session.settled, const StudySettings());

      session.openStudy(
        Study(
          id: 'a',
          name: 'a',
          date: DateTime(2026),
          imageKey: 'a',
          settings: const StudySettings(),
        ),
      );
      expect(session.flipped, isFalse);
    },
  );

  testWidgets('a double tap on the flipped picture zooms on the passage under '
      'the finger', (tester) async {
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.binding.defaultBinaryMessenger.setMockMessageHandler(
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
      (_) async => const StandardMessageCodec().encodeMessage(<Object?>[null]),
    );

    late ValueShader shader;
    late ui.Image image;
    await tester.runAsync(() async {
      shader = await ValueShader.load();
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(const Color(0xFF808080), BlendMode.src);
      image = await recorder.endRecording().toImage(400, 600);
    });

    Future<ViewTransform> doubleTap(Offset at, {required bool flipped}) async {
      final session = CanvasSession()
        ..image = image
        ..flipped = flipped;
      await tester.pumpWidget(
        MaterialApp(
          home: CanvasSurface(session: session, shader: shader),
        ),
      );
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(at);
      await tester.pump();
      final view = session.view;
      await tester.pumpWidget(const SizedBox());
      session.image = null;
      session.dispose();
      return view;
    }

    // Near the top left of the screen is near the bottom right of the
    // picture turned upside down.
    final flipped = await doubleTap(const Offset(100, 120), flipped: true);
    final upright = await doubleTap(const Offset(300, 480), flipped: false);
    expect(flipped.zoom, greaterThan(1));
    expect(flipped, upright);
  });

  testWidgets('the up arrow flips the picture, except while a text field '
      'has the keys', (tester) async {
    final session = CanvasSession();
    addTearDown(session.dispose);
    final renaming = ValueNotifier(false);
    addTearDown(renaming.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: StudyKeys(
          session: session,
          child: Material(
            child: ValueListenableBuilder(
              valueListenable: renaming,
              builder: (context, on, _) =>
                  on ? const TextField(autofocus: true) : const SizedBox(),
            ),
          ),
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    expect(session.flipped, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    expect(session.flipped, isFalse);

    renaming.value = true;
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    expect(session.flipped, isFalse, reason: 'the caret has the arrow');

    // Renaming ends by swapping the field back out; the shortcut returns.
    renaming.value = false;
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    expect(session.flipped, isTrue);
  });
}
