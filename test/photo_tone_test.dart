import 'dart:ui' as ui;

import 'package:askance/engine/deferred_disposer.dart';
import 'package:askance/engine/engine.dart';
import 'package:askance/engine/lstar.dart';
import 'package:askance/engine/tone.dart';
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
        bias: -0.1,
        contrast: 0.8,
        tone: PhotoTone(mono: true, squint: true),
      );
      expect(StudySettings.fromJson(settings.toJson()), settings);
    });

    test('kept when PHOTO had its own blur and contrast opens as the '
        "study's", () {
      final settings = StudySettings.fromJson({
        'tone': {'mono': true, 'brightness': 0.3, 'contrast': 0.6, 'blur': 0.4},
      });
      expect(settings.tone, const PhotoTone(mono: true, squint: true));
      expect(settings.contrast, 0.6);
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

  test('a peek from PHOTO shows the photograph untouched, whatever the '
      'tone', () async {
    const colour = Color(0xFF2040FF);
    final px = await paintPhoto(
      colour,
      const StudySettings(
        mode: ViewMode.photo,
        bias: 0.2,
        contrast: 1,
        tone: PhotoTone(mono: true),
      ),
      peeking: true,
    );
    expect(px, (r: 0x20, g: 0x40, b: 0xFF));
  });

  test('PHOTO in colour has the lightness the value map bands', () async {
    for (final (bias, contrast) in const [
      (0.15, 0.0),
      (-0.1, 0.7),
      (0.0, -0.8),
    ]) {
      final settings = StudySettings(
        mode: ViewMode.photo,
        bias: bias,
        contrast: contrast,
      );
      for (final colour in const [Color(0xFF2040FF), Color(0xFF8A6A3C)]) {
        final px = await paintPhoto(colour, settings);
        final source = lstarOfSrgb8(
          (colour.r * 255).round(),
          (colour.g * 255).round(),
          (colour.b * 255).round(),
        );
        expect(
          lstarOfSrgb8(px.r, px.g, px.b),
          closeTo(
            toneCurve(source / 100, shift: bias, contrast: contrast) * 100,
            1.5,
          ),
          reason: '$colour $bias $contrast',
        );
      }
    }
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
      final photo = settings.tone.squint ? await pass(settings.detail) : null;
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

    const squint = PhotoTone(squint: true);

    test('is sharp, or squinting, blurred by the study\'s detail', () async {
      expect(
        await nearEdge(const StudySettings(mode: ViewMode.photo)),
        lessThan(10),
      );
      expect(
        await nearEdge(
          const StudySettings(mode: ViewMode.photo, detail: 0, tone: squint),
        ),
        greaterThan(40),
      );
    });

    test('is what a peek shows from the value map', () async {
      expect(
        await nearEdge(
          const StudySettings(steps: 2, detail: 0, tone: squint),
          peeking: true,
        ),
        greaterThan(40),
      );
    });

    test('is what SPLIT compares the value map against', () async {
      expect(
        await nearEdge(
          const StudySettings(mode: ViewMode.split, detail: 0, tone: squint),
        ),
        greaterThan(40),
      );
      expect(
        await nearEdge(const StudySettings(mode: ViewMode.split, bias: 0.25)),
        greaterThan(40),
      );
    });
  });

  group('the value map is made from the photograph as PHOTO shows it', () {
    /// The colour painted in the middle of a [grey] photograph once the
    /// pass for [settings] has rendered.
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
        contrast: settings.contrast,
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
      test('contrast pushes a passage into another value, '
          '${smoothing.label}', () async {
        // L* about 40: the middle of three values, until the contrast
        // spreads it down into the darkest.
        final flat = StudySettings(steps: 3, smoothing: smoothing);
        final punchy = flat.copyWith(contrast: 0.5);
        final ramp = flat.palette;
        expect(await valueOf(95, flat), (ramp[1].r * 255).round());
        expect(await valueOf(95, punchy), (ramp[0].r * 255).round());
      });

      test('a steep contrast keeps a passage in its own value, '
          '${smoothing.label}', () async {
        // L* about 45, which full contrast puts in the second of five
        // values. BLOCK fills it with a grey the shader must read back there.
        final steep = StudySettings(
          steps: 5,
          smoothing: smoothing,
          contrast: 1,
        );
        expect(await valueOf(107, steep), (steep.palette[1].r * 255).round());
      });
    }
  });
}
