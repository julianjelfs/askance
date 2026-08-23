import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:askance/engine/deferred_disposer.dart';
import 'package:askance/engine/engine.dart';
import 'package:askance/engine/regions.dart';
import 'package:askance/engine/value_scale.dart';
import 'package:askance/model/study.dart';
import 'package:askance/engine/value_painter.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// The bias slides every threshold together. The steps stay evenly spaced in
/// L*, so a value still means what it always did; it only decides which side
/// of a boundary a borderline passage falls on.
void main() {
  Future<ui.Image> flat(int grey, {int side = 64}) async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder, Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble()))
        .drawRect(
          Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble()),
          Paint()..color = Color.fromARGB(255, grey, grey, grey),
        );
    final picture = recorder.endRecording();
    final image = await picture.toImage(side, side);
    picture.dispose();
    return image;
  }

  /// The colour the pipeline paints a flat grey, all the way through the real
  /// shader.
  Future<Color> render(int grey, {required double bias, int steps = 3}) async {
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
      settings: StudySettings(steps: steps, bias: bias),
      view: view,
      devicePixelRatio: 1,
      peeking: false,
      splitPosition: 0.5,
      regions: null,
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

  test('with no bias the ramp is painted exactly as the scale says', () async {
    // Mid grey is L* 53.6, which at three steps is the middle band. The
    // renumbered uniforms would show up here first as a wrong colour.
    final painted = await render(128, bias: 0);
    final expected = ValueScale.grey.ramp(3)[1];
    expect(painted.toARGB32(), expected.toARGB32());
  });

  test('a positive bias lifts a passage into the band above', () async {
    // L* 53.6 sits just above the 33.3 boundary; pushing up past 66.7 needs
    // a bias of about 0.13.
    final lifted = await render(128, bias: 0.2);
    expect(lifted.toARGB32(), ValueScale.grey.ramp(3)[2].toARGB32());
  });

  test('a negative bias drops it into the band below', () async {
    final dropped = await render(128, bias: -0.21);
    expect(dropped.toARGB32(), ValueScale.grey.ramp(3)[0].toARGB32());
  });

  test('the labelling pass reads the same bands as the screen', () {
    // bandsFromRgba mirrors the shader; if they disagree the numbers land on
    // regions that are not there.
    final bytes = ByteData(4)
      ..setUint8(0, 128)
      ..setUint8(1, 128)
      ..setUint8(2, 128)
      ..setUint8(3, 255);
    expect(bandsFromRgba(bytes, 1, 1, 3).bands.first, 1);
    expect(bandsFromRgba(bytes, 1, 1, 3, bias: 0.2).bands.first, 2);
    expect(bandsFromRgba(bytes, 1, 1, 3, bias: -0.21).bands.first, 0);
  });

  test('bias survives a round trip through a saved study', () {
    const settings = StudySettings(bias: -0.125);
    expect(StudySettings.fromJson(settings.toJson()).bias, -0.125);
    // And is held to a range that always leaves every step reachable.
    expect(
      StudySettings.fromJson(const {'bias': 99.0}).bias,
      StudySettings.maxBias,
    );
  });
}
