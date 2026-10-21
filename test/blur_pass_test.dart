import 'dart:ui' as ui;

import 'package:askance/engine/blur_pass.dart';
import 'package:askance/engine/engine.dart';
import 'package:askance/engine/tone.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ui.Image source;
  late ui.Image pixel;
  final rendered = <(Smoothing, Size)>[];

  Future<ui.Image> render({
    required ui.Image source,
    required Size outputPx,
    required double detail,
    required ViewTransform view,
    Smoothing smoothing = Smoothing.gaussian,
    bool lockDetail = false,
    Rect crop = const Rect.fromLTRB(0, 0, 1, 1),
    int steps = 3,
    double bias = 0,
    PhotoTone tone = const PhotoTone(),
  }) async {
    rendered.add((smoothing, outputPx));
    return pixel.clone();
  }

  setUp(() => rendered.clear());

  Future<void> images(WidgetTester tester) async {
    await tester.runAsync(() async {
      Future<ui.Image> one() {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawColor(const Color(0xFF808080), BlendMode.src);
        return recorder.endRecording().toImage(1, 1);
      }

      source = await one();
      pixel = await one();
    });
  }

  /// The tool panel opening: the picture shrinks a little every frame for a
  /// third of a second.
  Future<void> resizeBurst(
    WidgetTester tester,
    BlurPass pass,
    Smoothing smoothing,
  ) async {
    for (var frame = 1; frame <= 20; frame++) {
      pass.request(
        source: source,
        outputPx: Size(1170, 1500 - frame * 15.0),
        detail: 0.4,
        view: const ViewTransform(),
        smoothing: smoothing,
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('on the web, a burst of resizes costs BLOCK one pass, once the '
      'size has settled', (tester) async {
    await images(tester);
    final pass = BlurPass(render: render, holdBlock: true);
    addTearDown(pass.dispose);

    pass.request(
      source: source,
      outputPx: const Size(1170, 1500),
      detail: 0.4,
      view: const ViewTransform(),
      smoothing: Smoothing.block,
    );
    await tester.pump();
    expect(rendered, hasLength(1), reason: 'the first pass is not held');

    await resizeBurst(tester, pass, Smoothing.block);
    expect(rendered, hasLength(2));
    expect(rendered.last.$2, const Size(1170, 1200), reason: 'the final size');
  });

  testWidgets('the cheap passes still follow a resize frame by frame', (
    tester,
  ) async {
    await images(tester);
    final pass = BlurPass(render: render);
    addTearDown(pass.dispose);

    await resizeBurst(tester, pass, Smoothing.gaussian);
    expect(rendered.length, greaterThan(10));
  });
}
