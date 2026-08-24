import 'dart:ui' as ui;

import 'package:askance/engine/deferred_disposer.dart';
import 'package:askance/engine/engine.dart';
import 'package:askance/engine/value_scale.dart';
import 'package:askance/model/study.dart';
import 'package:askance/engine/value_painter.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// The skeleton's fill blocks values in the way a painting is begun: darkest
/// first, everything unplaced left as ground, all through the real shader.
void main() {
  Future<ui.Image> flat(int grey, {int side = 64}) async {
    final recorder = ui.PictureRecorder();
    Canvas(
      recorder,
      Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble()),
    ).drawRect(
      Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble()),
      Paint()..color = Color.fromARGB(255, grey, grey, grey),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(side, side);
    picture.dispose();
    return image;
  }

  /// The colour the pipeline paints the middle of a flat grey in skeleton
  /// mode at the given fill. Flat, so there are no edges to ink.
  Future<Color> render(int grey, {required int fill}) async {
    final shader = await ValueShader.load();
    final source = await flat(grey);
    const output = Size(64, 64);
    const view = ViewTransform();

    final blurred = await renderBlurredSource(
      source: source,
      outputPx: output,
      detail: 1,
      view: view,
    );
    final disposer = DeferredDisposer();
    final recorder = ui.PictureRecorder();
    final painter = ValuePainter(
      shader: shader,
      source: source,
      blurred: blurred,
      settings: StudySettings(
        steps: 3,
        mode: ViewMode.skeleton,
        skeletonFill: fill,
      ),
      view: view,
      devicePixelRatio: 1,
      peeking: false,
      splitPosition: 0.5,
      disposer: disposer,
      drawGrid: false,
    )..paint(Canvas(recorder, Offset.zero & output), output);

    final picture = recorder.endRecording();
    final rendered = await picture.toImage(64, 64);
    picture.dispose();
    painter.disposeResources();
    disposer.disposeAll();
    blurred.dispose();
    source.dispose();

    final bytes = (await rendered.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!.buffer.asUint8List();
    rendered.dispose();
    final i = (32 * 64 + 32) * 4;
    return Color.fromARGB(255, bytes[i], bytes[i + 1], bytes[i + 2]);
  }

  const ground = Color(0xFFF3F2F2);

  test(
    'a band stays ground until the fill reaches it, darkest first',
    () async {
      // Mid grey is L* 53.6: the middle band of three. It must appear only
      // once the fill count passes it — after the darkest band's turn.
      final mid = ValueScale.grey.ramp(3)[1];
      expect((await render(128, fill: 0)).toARGB32(), ground.toARGB32());
      expect((await render(128, fill: 1)).toARGB32(), ground.toARGB32());
      expect((await render(128, fill: 2)).toARGB32(), mid.toARGB32());
      expect((await render(128, fill: 3)).toARGB32(), mid.toARGB32());
    },
  );

  test('the darkest band is the first placed', () async {
    // sRGB 30 sits in band 0 of three.
    final dark = ValueScale.grey.ramp(3)[0];
    expect((await render(30, fill: 0)).toARGB32(), ground.toARGB32());
    expect((await render(30, fill: 1)).toARGB32(), dark.toARGB32());
  });

  test('the fill count survives a round trip through a saved study', () {
    const settings = StudySettings(skeletonFill: 4);
    expect(StudySettings.fromJson(settings.toJson()).skeletonFill, 4);
    // Manifests from the numbers era simply start unfilled.
    expect(StudySettings.fromJson(const {'numbers': true}).skeletonFill, 0);
  });
}
