import 'dart:ui' as ui;

import 'package:askance/engine/engine.dart';
import 'package:askance/model/study.dart';
import 'package:askance/state/canvas_session.dart';
import 'package:askance/ui/canvas/canvas_surface.dart';
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

    // Near the top of the screen is near the bottom of the flipped picture.
    final flipped = await doubleTap(const Offset(100, 120), flipped: true);
    final upright = await doubleTap(const Offset(100, 480), flipped: false);
    expect(flipped.zoom, greaterThan(1));
    expect(flipped, upright);
  });
}
