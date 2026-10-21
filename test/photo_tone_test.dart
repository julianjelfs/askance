import 'dart:ui' as ui;

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

  group('the photograph as PHOTO shows it', () {
    late ui.Image source;
    late ValueShader shader;
    const size = Size(200, 100);

    setUpAll(() async {
      // Black on the left, white on the right: a hard edge down the middle.
      final recorder = ui.PictureRecorder();
      Canvas(recorder)
        ..drawColor(const Color(0xFFFFFFFF), BlendMode.src)
        ..drawRect(
          const Rect.fromLTWH(0, 0, 100, 100),
          Paint()..color = const Color(0xFF000000),
        );
      final picture = recorder.endRecording();
      source = await picture.toImage(200, 100);
      picture.dispose();
      shader = await ValueShader.load();
    });
    tearDownAll(() => source.dispose());

    /// Red just left of the edge, as the canvas paints [settings], with both
    /// passes it would have asked for.
    Future<int> nearEdge(StudySettings settings, {bool peeking = false}) async {
      Future<ui.Image> pass(double detail) => renderBlurredSource(
        source: source,
        outputPx: size,
        detail: detail,
        view: const ViewTransform(),
      );
      final study = await pass(settings.detail);
      final photo = settings.photoBlurDetail == null
          ? null
          : await pass(settings.photoBlurDetail!);
      final disposer = DeferredDisposer();
      final out = ui.PictureRecorder();
      final painter = ValuePainter(
        shader: shader,
        source: source,
        blurred: study,
        photoBlurred: photo,
        settings: settings,
        view: const ViewTransform(),
        devicePixelRatio: 1,
        peeking: peeking,
        // Split with the photograph across the edge being probed.
        splitPosition: 0.75,
        disposer: disposer,
        drawGrid: false,
      )..paint(Canvas(out, Offset.zero & size), size);
      final image = await out.endRecording().toImage(200, 100);
      painter.disposeResources();
      disposer.disposeAll();
      study.dispose();
      photo?.dispose();
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      image.dispose();
      return bytes[(50 * 200 + 97) * 4];
    }

    const blurred = PhotoTone(blur: 1);

    test('is sharp with no blur, and softened with it', () async {
      expect(
        await nearEdge(const StudySettings(mode: ViewMode.photo)),
        lessThan(10),
      );
      expect(
        await nearEdge(
          const StudySettings(mode: ViewMode.photo, tone: blurred),
        ),
        greaterThan(40),
      );
    });

    test('is what a peek shows from the value map', () async {
      expect(
        await nearEdge(
          const StudySettings(steps: 2, tone: blurred),
          peeking: true,
        ),
        greaterThan(40),
      );
    });

    test('is what SPLIT compares the value map against', () async {
      expect(
        await nearEdge(
          const StudySettings(mode: ViewMode.split, tone: blurred),
        ),
        greaterThan(40),
      );
      expect(
        await nearEdge(
          const StudySettings(
            mode: ViewMode.split,
            tone: PhotoTone(brightness: 1),
          ),
        ),
        greaterThan(100),
      );
    });
  });

  group('the value map is made from the photograph as PHOTO shows it', () {
    /// The colour painted in the middle of a [grey] photograph, quantised
    /// to two values, once the pass for [settings] has rendered.
    Future<int> valueOf(int grey, StudySettings settings) async {
      const size = Size(60, 60);
      final recorder = ui.PictureRecorder();
      Canvas(
        recorder,
      ).drawColor(Color.fromARGB(255, grey, grey, grey), BlendMode.src);
      final picture = recorder.endRecording();
      final source = await picture.toImage(60, 60);
      picture.dispose();
      final pass = await renderBlurredSource(
        source: source,
        outputPx: size,
        detail: settings.detail,
        view: const ViewTransform(),
        smoothing: settings.smoothing,
        steps: settings.steps,
        bias: settings.bias,
        tone: settings.tone,
      );
      final disposer = DeferredDisposer();
      final out = ui.PictureRecorder();
      final painter = ValuePainter(
        shader: await ValueShader.load(),
        source: source,
        blurred: pass,
        settings: settings,
        view: const ViewTransform(),
        devicePixelRatio: 1,
        peeking: false,
        splitPosition: 0.5,
        disposer: disposer,
        drawGrid: false,
      )..paint(Canvas(out, Offset.zero & size), size);
      final image = await out.endRecording().toImage(60, 60);
      painter.disposeResources();
      disposer.disposeAll();
      pass.dispose();
      source.dispose();
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      image.dispose();
      return bytes[(30 * 60 + 30) * 4];
    }

    for (final smoothing in [Smoothing.gaussian, Smoothing.block]) {
      test('brightness lifts a passage into a lighter value, '
          '${smoothing.label}', () async {
        // L* about 40: the darker of two values, until brightened.
        final dark = StudySettings(steps: 2, smoothing: smoothing);
        final brightened = dark.copyWith(
          tone: const PhotoTone(brightness: 0.6),
        );
        final ramp = dark.palette;
        expect(await valueOf(95, dark), (ramp[0].r * 255).round());
        expect(await valueOf(95, brightened), (ramp[1].r * 255).round());
      });
    }
    test('blur softens the study as well as the photograph', () async {
      // Black on the left, white on the right.
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
      Future<int> nearEdge(PhotoTone tone) async {
        final pass = await renderBlurredSource(
          source: source,
          outputPx: const Size(200, 100),
          detail: 1,
          view: const ViewTransform(),
          tone: tone,
        );
        final bytes = (await pass.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
        pass.dispose();
        return bytes[(50 * 200 + 97) * 4];
      }

      expect(await nearEdge(const PhotoTone()), lessThan(10));
      expect(await nearEdge(const PhotoTone(blur: 1)), greaterThan(40));
      source.dispose();
    });
  });
}
