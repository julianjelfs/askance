import 'dart:ui' as ui;

import 'package:askance/engine/engine.dart';
import 'package:askance/model/study.dart';
import 'package:askance/state/canvas_session.dart';
import 'package:askance/state/providers.dart';
import 'package:askance/theme.dart';
import 'package:askance/ui/desktop/desktop_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the rail unfolds one group at a time, and folding a group '
      'ends the mode whose way out was inside it', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // The canvas keeps the screen awake; there is no platform here to ask.
    tester.binding.defaultBinaryMessenger.setMockMessageHandler(
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
      (_) async => const StandardMessageCodec().encodeMessage(<Object?>[null]),
    );
    final session = CanvasSession()..settings = const StudySettings(steps: 4);
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
          home: DesignScale(factor: 1, child: DesktopScreen()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    Future<void> tap(String label) async {
      // An unfolded group can run below the bottom of a laptop's window.
      await tester.ensureVisible(find.text(label));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text(label));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    // Folded to begin with: the essentials, and none of the groups' controls.
    expect(find.text('Stages'), findsOneWidget);
    expect(find.text('Edit crop'), findsNothing);
    expect(find.text('Brightness'), findsNothing);

    await tap('Board');
    expect(find.text('Edit crop'), findsOneWidget);

    await tap('Draw lines');
    expect(session.drawingLines, isTrue);

    await tap('Picture');
    expect(find.text('Brightness'), findsOneWidget);
    expect(find.text('Edit crop'), findsNothing);
    expect(session.drawingLines, isFalse);
  });
}
