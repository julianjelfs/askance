import 'dart:ui' as ui;

import 'package:askance/engine/blur_pass.dart';
import 'package:askance/engine/deferred_disposer.dart';
import 'package:askance/engine/engine.dart';
import 'package:askance/engine/lstar.dart';
import 'package:askance/engine/value_painter.dart';
import 'package:askance/model/study.dart';
import 'package:askance/state/canvas_session.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('switching view closes a tool that would adjust nothing there', () {
    final session = CanvasSession()..toggleTool(CanvasTool.detail);
    addTearDown(session.dispose);
    session.setMode(ViewMode.photo);
    expect(session.openTool, isNull, reason: 'detail is lost on the photo');

    session.toggleTool(CanvasTool.tone);
    session.setMode(ViewMode.value);
    expect(session.openTool, isNull, reason: 'tone is PHOTO only');

    session.toggleTool(CanvasTool.grid);
    session.setMode(ViewMode.photo);
    expect(session.openTool, CanvasTool.grid, reason: 'grid is in both');
  });

  group('a stored tone', () {
    test('survives saving and reopening a study', () {
      const settings = StudySettings(
        tone: PhotoTone(mono: true, brightness: -0.3, contrast: 0.8, blur: 0.6),
      );
      expect(StudySettings.fromJson(settings.toJson()), settings);
    });

    test('that is missing or unusable opens untouched', () {
      for (final tone in [null, 'mono', 7]) {
        expect(StudySettings.fromJson({'tone': tone}).tone, const PhotoTone());
      }
    });
  });

  /// Paints a [colour]-filled photograph through the painter and returns the
  /// middle pixel.
  Future<({int r, int g, int b})> paintPhoto(
    Color colour,
    StudySettings settings, {
    bool peeking = false,
  }) async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(colour, BlendMode.src);
    final picture = recorder.endRecording();
    final source = await picture.toImage(40, 40);
    picture.dispose();

    const output = Size(40, 40);
    final disposer = DeferredDisposer();
    final out = ui.PictureRecorder();
    final painter = ValuePainter(
      shader: await ValueShader.load(),
      source: source,
      blurred: null,
      settings: settings,
      view: const ViewTransform(),
      devicePixelRatio: 1,
      peeking: peeking,
      splitPosition: 0.5,
      disposer: disposer,
      drawGrid: false,
    )..paint(Canvas(out, Offset.zero & output), output);
    final image = await out.endRecording().toImage(40, 40);
    painter.disposeResources();
    disposer.disposeAll();
    final bytes = (await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!.buffer.asUint8List();
    image.dispose();
    source.dispose();
    const i = (20 * 40 + 20) * 4;
    return (r: bytes[i], g: bytes[i + 1], b: bytes[i + 2]);
  }

  test('black and white keeps the lightness the value map reads, not a '
      'luma of the encoded channels', () async {
    const mono = StudySettings(
      mode: ViewMode.photo,
      tone: PhotoTone(mono: true),
    );
    // Saturated colours, where a luma of the encoded channels is furthest
    // from L*.
    for (final colour in const [
      Color(0xFFFFE000),
      Color(0xFF2040FF),
      Color(0xFFE02020),
    ]) {
      final px = await paintPhoto(colour, mono);
      expect(px.r, px.g);
      expect(px.g, px.b);
      final r8 = (colour.r * 255).round();
      final g8 = (colour.g * 255).round();
      final b8 = (colour.b * 255).round();
      expect(
        lstarOfSrgb8(px.r, px.g, px.b),
        closeTo(lstarOfSrgb8(r8, g8, b8), 1.5),
        reason: '$colour',
      );
    }
  });

  test('a peek shows the photograph untouched, whatever the tone', () async {
    const colour = Color(0xFF2040FF);
    final px = await paintPhoto(
      colour,
      const StudySettings(
        mode: ViewMode.photo,
        tone: PhotoTone(mono: true, contrast: 1),
      ),
      peeking: true,
    );
    expect(px, (r: 0x20, g: 0x40, b: 0xFF));
  });

  test(
    'blur in PHOTO softens the photograph, and none leaves it sharp',
    () async {
      // Black on the left, white on the right: a hard edge down the middle.
      const size = Size(200, 100);
      final recorder = ui.PictureRecorder();
      Canvas(recorder)
        ..drawColor(const Color(0xFFFFFFFF), BlendMode.src)
        ..drawRect(
          const Rect.fromLTWH(0, 0, 100, 100),
          Paint()..color = const Color(0xFF000000),
        );
      final picture = recorder.endRecording();
      final source = await picture.toImage(200, 100);
      picture.dispose();
      addTearDown(source.dispose);
      final shader = await ValueShader.load();

      /// Red just left of the edge, as the canvas shows the study.
      Future<int> nearEdge(double blur) async {
        final settings = StudySettings(
          mode: ViewMode.photo,
          tone: PhotoTone(blur: blur),
        );
        final pass = BlurPass();
        addTearDown(pass.dispose);
        pass.request(
          source: source,
          outputPx: size,
          detail: settings.pass.detail,
          view: const ViewTransform(),
          smoothing: settings.pass.smoothing,
          lockDetail: settings.pass.lockDetail,
        );
        await pass.settled;
        final disposer = DeferredDisposer();
        final out = ui.PictureRecorder();
        final painter = ValuePainter(
          shader: shader,
          source: source,
          blurred: pass.image,
          blurredView: pass.imageView,
          blurredSize: pass.imageOutputPx,
          settings: settings,
          view: const ViewTransform(),
          devicePixelRatio: 1,
          peeking: false,
          splitPosition: 0.5,
          disposer: disposer,
          drawGrid: false,
        )..paint(Canvas(out, Offset.zero & size), size);
        final image = await out.endRecording().toImage(200, 100);
        painter.disposeResources();
        disposer.disposeAll();
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
        image.dispose();
        return bytes[(50 * 200 + 97) * 4];
      }

      expect(await nearEdge(0), lessThan(10));
      expect(await nearEdge(1), greaterThan(40));
    },
  );
}
