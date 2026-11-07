import 'dart:ui' as ui;

import 'package:askance/engine/engine.dart';
import 'package:askance/engine/export.dart';
import 'package:askance/engine/lines.dart';
import 'package:askance/model/study.dart';
import 'package:askance/state/canvas_session.dart';
import 'package:askance/ui/canvas/canvas_surface.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('lines are kept with the study', () {
    test('they round-trip through JSON', () {
      const settings = StudySettings(
        lines: [
          BoardLine(Offset(0.1, 0.2), Offset(0.8, 0.9)),
          BoardLine(Offset(0.5, 0), Offset(0.5, 1)),
        ],
      );
      expect(StudySettings.fromJson(settings.toJson()), settings);
    });

    test('a damaged line costs that line, and a study saved before lines '
        'opens with none', () {
      final json = const StudySettings().toJson()
        ..['lines'] = [
          [0.1, 0.2, 0.3, 0.4],
          [0.1, 'x', 0.3, 0.4],
          [0.1, 0.2],
          'nonsense',
        ];
      expect(StudySettings.fromJson(json).lines, const [
        BoardLine(Offset(0.1, 0.2), Offset(0.3, 0.4)),
      ]);
      expect(StudySettings.fromJson(json..remove('lines')).lines, isEmpty);
    });
  });

  test('a line stays on the point of the photograph it was ruled at, '
      'whatever the crop, zoom and pan', () {
    const point = Offset(0.4, 0.7);
    const crop = Rect.fromLTRB(0.2, 0.3, 0.9, 0.95);
    const source = Size(1400, 1950);
    const output = Size(500, 700);
    final view = const ViewTransform().zoomedAt(
      const Offset(320, 410),
      3.2,
      source,
      output,
    );
    final picture = view.destination(source, output);
    final screen = lineToScreen(point, crop, picture);
    // The same point found through pixels: [source] is this crop of a
    // 2000 x 3000 photograph.
    final px = Offset(
      (point.dx - crop.left) * 2000 / source.width,
      (point.dy - crop.top) * 3000 / source.height,
    );
    expect(screen.dx, closeTo(picture.left + px.dx * picture.width, 1e-6));
    expect(screen.dy, closeTo(picture.top + px.dy * picture.height, 1e-6));
    final back = screenToLine(screen, crop, picture);
    expect(back.dx, closeTo(point.dx, 1e-9));
    expect(back.dy, closeTo(point.dy, 1e-9));

    // Re-cropping leaves the line where it was on the photograph.
    final session = CanvasSession()
      ..settings = const StudySettings(lines: [BoardLine(point, point)]);
    addTearDown(session.dispose);
    session.setCrop(crop);
    expect(session.settings.lines, const [BoardLine(point, point)]);
  });

  group('exported', () {
    late ui.Image source;
    late ValueShader shader;

    setUpAll(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(const Color(0xFF808080), BlendMode.src);
      final picture = recorder.endRecording();
      source = await picture.toImage(200, 300);
      picture.dispose();
      shader = await ValueShader.load();
    });
    tearDownAll(() => source.dispose());

    /// The grey photograph exported with a line ruled straight across it
    /// three tenths of the way down, as a lookup of the colour at a
    /// fraction of each side plus [dy] pixels down.
    Future<Color Function(double x, {int dy})> export(GridMode grid) async {
      final png = await renderExport(
        shader: shader,
        source: source,
        settings: StudySettings(
          mode: ViewMode.photo,
          grid: grid,
          gridLevel: 1,
          lines: const [BoardLine(Offset(0, 0.3), Offset(1, 0.3))],
        ),
        view: const ViewTransform(),
        target: ExportSize.screen,
        splitPosition: 0.5,
      );
      final codec = await ui.instantiateImageCodec(png!);
      final image = (await codec.getNextFrame()).image;
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      final width = image.width;
      final y = (image.height * 0.3).round();
      image.dispose();
      codec.dispose();
      return (double x, {int dy = 0}) {
        final i = ((y + dy) * width + (width * x).round()) * 4;
        return Color.fromARGB(
          bytes[i + 3],
          bytes[i],
          bytes[i + 1],
          bytes[i + 2],
        );
      };
    }

    void expectAccent(Color c, String reason) {
      expect((c.r * 255).round(), greaterThan(200), reason: reason);
      expect((c.b * 255).round(), lessThan(80), reason: reason);
    }

    /// Tinted toward the accent: the thin quarter ticks are antialiased, so
    /// a sampled pixel is a blend rather than the accent itself.
    void expectTinted(Color c, String reason) => expect(
      (c.r * 255).round() - (c.b * 255).round(),
      greaterThan(60),
      reason: reason,
    );

    void expectGrey(Color c, String reason) =>
        expect((c.r * 255).round(), (c.b * 255).round(), reason: reason);

    // A fifth of the way across is clear of every grid rule at level 1.
    test('lines are exported whether or not the grid is on', () async {
      expectAccent((await export(GridMode.lines))(0.2), 'with the grid');
      expectAccent((await export(GridMode.off))(0.2), 'without it');
    });

    test('a ruled line carries ticks across its middle and quarters and '
        'nowhere else', () async {
      final at = await export(GridMode.off);
      expectAccent(at(0.5, dy: 3), 'the tick, just below the line');
      expectAccent(at(0.5, dy: -3), 'the tick, just above the line');
      expectTinted(at(0.25, dy: 3), 'the first quarter tick');
      expectTinted(at(0.75, dy: -3), 'the last quarter tick');
      expectGrey(at(0.2, dy: 3), 'beside the line away from its ticks');
    });
  });

  testWidgets('on the desktop, with the grid off, two clicks rule a line and '
      'dragging an end moves it', (tester) async {
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
      ..drawingLines = true;

    await tester.pumpWidget(
      MaterialApp(
        home: CanvasSurface(session: session, shader: shader, editLines: true),
      ),
    );

    await tester.tapAt(const Offset(100, 150), kind: PointerDeviceKind.mouse);
    await tester.tapAt(const Offset(300, 450), kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(session.settings.lines, const [
      BoardLine(Offset(0.25, 0.25), Offset(0.75, 0.75)),
    ]);

    // Taken a few pixels off the end: the end moves with the pointer
    // rather than jumping under it.
    await tester.dragFrom(
      const Offset(303, 452),
      const Offset(-100, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(seconds: 1));
    expect(session.settings.lines.single.a, const Offset(0.25, 0.25));
    expect(session.settings.lines.single.b.dx, closeTo(0.5, 1e-9));
    expect(session.settings.lines.single.b.dy, closeTo(0.75, 1e-9));
    expect(session.view, const ViewTransform(), reason: 'no pan');

    // Pressed and held on an end before dragging it, the line stays in
    // hand: drawing lines, a hold never peeks at the photograph.
    final hold = await tester.startGesture(
      const Offset(200, 450),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(seconds: 1));
    expect(session.peeking, isFalse);
    await hold.moveBy(const Offset(0, -100));
    await hold.up();
    await tester.pump(const Duration(seconds: 1));
    expect(session.peeking, isFalse);
    expect(session.settings.lines.single.b.dy, closeTo(7 / 12, 1e-9));

    await tester.pumpWidget(const SizedBox());
    session.image = null;
    session.dispose();
    image.dispose();
  });
}
