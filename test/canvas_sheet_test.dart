import 'dart:ui' as ui;

import 'package:askance/engine/engine.dart';
import 'package:askance/model/study.dart';
import 'package:askance/state/canvas_session.dart';
import 'package:askance/state/providers.dart';
import 'package:askance/theme.dart';
import 'package:askance/ui/canvas/canvas_screen.dart';
import 'package:askance/ui/canvas/canvas_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'a tap on the picture closes an open sheet before it hides anything',
    () {
      final session = CanvasSession()..toggleTool(CanvasTool.steps);
      addTearDown(session.dispose);

      session.tapPicture();
      expect(session.openTool, isNull);
      expect(session.chromeVisible, isTrue);

      session.tapPicture();
      expect(session.chromeVisible, isFalse);
    },
  );

  testWidgets('opening a tool lays its sheet over the picture without '
      'resizing it', (tester) async {
    tester.view.physicalSize = const Size(390, 844) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    // The canvas keeps the screen awake; there is no platform here to ask.
    tester.binding.defaultBinaryMessenger.setMockMessageHandler(
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
      (_) async => const StandardMessageCodec().encodeMessage(<Object?>[null]),
    );

    final session = CanvasSession()
      ..settings = const StudySettings(steps: 4, detail: 0.5);
    addTearDown(session.dispose);
    late ValueShader shader;
    await tester.runAsync(() async {
      shader = await ValueShader.load();
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(const Color(0xFF808080), BlendMode.src);
      session.image = await recorder.endRecording().toImage(60, 90);
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionProvider.overrideWithValue(session),
          shaderProvider.overrideWith((ref) => shader),
        ],
        child: const MaterialApp(
          home: DesignScale(factor: 1, child: CanvasScreen()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    final closed = tester.getRect(find.byType(CanvasSurface));

    session.toggleTool(CanvasTool.steps);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Stages'), findsOneWidget, reason: 'the sheet is open');
    expect(tester.getRect(find.byType(CanvasSurface)), closed);
  });
}
