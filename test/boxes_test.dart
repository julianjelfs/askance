import 'dart:ui' as ui;

import 'package:askance/engine/boxes.dart';
import 'package:askance/engine/engine.dart';
import 'package:askance/engine/export.dart';
import 'package:askance/model/study.dart';
import 'package:askance/state/canvas_session.dart';
import 'package:askance/ui/canvas/canvas_surface.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('boxes are kept with the study', () {
    test('they round-trip through JSON', () {
      const settings = StudySettings(
        boxes: [
          BoardBox(Rect.fromLTRB(0.1, 0.2, 0.4, 0.9)),
          BoardBox(Rect.fromLTRB(0.5, 0.5, 0.6, 0.7)),
        ],
      );
      expect(StudySettings.fromJson(settings.toJson()), settings);
    });

    test('a damaged box costs that box, and a study saved before boxes '
        'opens with none', () {
      final json = const StudySettings().toJson()
        ..['boxes'] = [
          [0.4, 0.9, 0.1, 0.2],
          [0.1, 'x', 0.3, 0.4],
          [0.1, 0.2],
          'nonsense',
        ];
      expect(StudySettings.fromJson(json).boxes, const [
        BoardBox(Rect.fromLTRB(0.1, 0.2, 0.4, 0.9)),
      ]);
      expect(StudySettings.fromJson(json..remove('boxes')).boxes, isEmpty);
    });
  });

  test('proportions are read in pixels of the photograph, width first with '
      'the shorter side 1', () {
    // On a 400 x 200 photograph, half the width by the whole height is
    // 200 x 200: square, though the fractions are not.
    const photo = Size(400, 200);
    expect(
      boxRatioLabel(const BoardBox(Rect.fromLTRB(0, 0, 0.5, 1)), photo),
      '1.00 : 1',
    );
    // 80 x 200: tall.
    expect(
      boxRatioLabel(const BoardBox(Rect.fromLTRB(0, 0, 0.2, 1)), photo),
      '1 : 2.50',
    );
    // 400 x 100: wide.
    expect(
      boxRatioLabel(const BoardBox(Rect.fromLTRB(0, 0, 1, 0.5)), photo),
      '4.00 : 1',
    );
  });

  test('a box moved toward an edge stops at it without shrinking', () {
    const box = BoardBox(Rect.fromLTRB(0.6, 0.1, 0.9, 0.3));
    final moved = box.movedBy(const Offset(0.5, -0.5)).rect;
    expect(moved.left, closeTo(0.7, 1e-9));
    expect(moved.top, 0);
    expect(moved.right, closeTo(1, 1e-9));
    expect(moved.bottom, closeTo(0.2, 1e-9));
  });

  test('exported, a box is drawn on the picture', () async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(const Color(0xFF808080), BlendMode.src);
    final picture = recorder.endRecording();
    final source = await picture.toImage(200, 300);
    picture.dispose();
    addTearDown(source.dispose);
    final png = await renderExport(
      shader: await ValueShader.load(),
      source: source,
      settings: const StudySettings(
        mode: ViewMode.photo,
        boxes: [BoardBox(Rect.fromLTRB(0.2, 0.3, 0.8, 0.7))],
      ),
      view: const ViewTransform(),
      target: ExportSize.screen,
    );
    final codec = await ui.instantiateImageCodec(png!);
    final image = (await codec.getNextFrame()).image;
    final bytes = (await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!.buffer.asUint8List();
    int red(double x, double y) =>
        bytes[((image.height * y).round() * image.width +
                (image.width * x).round()) *
            4];
    int blue(double x, double y) =>
        bytes[((image.height * y).round() * image.width +
                    (image.width * x).round()) *
                4 +
            2];
    // The top side, away from its ticks, is the accent; inside is grey.
    expect(red(0.35, 0.3), greaterThan(200));
    expect(blue(0.35, 0.3), lessThan(80));
    expect(red(0.5, 0.5), blue(0.5, 0.5));
    image.dispose();
    codec.dispose();
  });

  testWidgets('on the desktop, in box mode, a drag draws a box, a corner '
      'resizes it, a side moves it, and a drag inside it draws another', (
    tester,
  ) async {
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
    final session = CanvasSession()
      ..image = image
      ..settings = const StudySettings(grid: GridMode.off)
      ..drawingLines = true
      ..guideShape = GuideShape.box;

    await tester.pumpWidget(
      MaterialApp(
        home: CanvasSurface(session: session, shader: shader, editLines: true),
      ),
    );

    Future<void> drag(Offset from, Offset by) async {
      final gesture = await tester.startGesture(
        from,
        kind: PointerDeviceKind.mouse,
      );
      // Past the slop in one step, then the rest, so the drag ends where
      // it was meant to.
      await gesture.moveBy(by / 2);
      await tester.pump();
      await gesture.moveBy(by / 2);
      await tester.pump();
      await gesture.up();
      await tester.pump(const Duration(seconds: 1));
    }

    Rect only(int i) => session.settings.boxes[i].rect;
    void expectRect(Rect actual, Rect expected) {
      expect(actual.left, closeTo(expected.left, 1e-9));
      expect(actual.top, closeTo(expected.top, 1e-9));
      expect(actual.right, closeTo(expected.right, 1e-9));
      expect(actual.bottom, closeTo(expected.bottom, 1e-9));
    }

    await drag(const Offset(100, 150), const Offset(200, 300));
    expect(session.settings.boxes, hasLength(1));
    expectRect(only(0), const Rect.fromLTRB(0.25, 0.25, 0.75, 0.75));
    expect(session.view, const ViewTransform(), reason: 'no pan');
    expect(session.selectedBox, 0, reason: 'a new box is selected');

    // The top left corner, dragged in: the bottom right stays put.
    await drag(const Offset(101, 151), const Offset(100, 0));
    expectRect(only(0), const Rect.fromLTRB(0.5, 0.25, 0.75, 0.75));

    // The bottom side, dragged up: the box moves, keeping its size.
    await drag(const Offset(250, 450), const Offset(0, -60));
    expectRect(only(0), const Rect.fromLTRB(0.5, 0.15, 0.75, 0.65));

    // Inside it, a drag draws a second box rather than moving the first.
    await drag(const Offset(225, 150), const Offset(40, 60));
    expect(session.settings.boxes, hasLength(2));
    expectRect(only(0), const Rect.fromLTRB(0.5, 0.15, 0.75, 0.65));

    // A slip of the mouse is not a box.
    await drag(const Offset(50, 500), const Offset(3, 30));
    expect(session.settings.boxes, hasLength(2));

    // Delete removes the selected one.
    session.selectBox(0);
    expect(session.deleteSelectedGuide(), isTrue);
    expect(session.settings.boxes, hasLength(1));

    await tester.pumpWidget(const SizedBox());
    session.image = null;
    session.dispose();
    image.dispose();
  });
}
