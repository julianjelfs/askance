import 'dart:ui' as ui;

import 'package:askance/engine/deferred_disposer.dart';
import 'package:askance/engine/engine.dart';
import 'package:askance/engine/value_painter.dart';
import 'package:askance/model/study.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// A pass takes a moment to render, and until the new one lands the painter
/// shows the last. That pass must still be drawn where its picture belongs
/// under the current view, or a pinch, or the picture's room changing, shows
/// the wrong part of the photograph, stretched, until the new pass snaps in.
void main() {
  const src = Size(800, 1200);

  /// Light, with a dark block whose corner sits half way across and a
  /// quarter of the way down: away from the middle, so a pass drawn at the
  /// wrong scale shows even where one drawn about the right centre would not.
  Future<ui.Image> marked() async {
    final w = src.width, h = src.height;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    canvas.drawRect(
      Rect.fromLTRB(w / 2, h / 4, w, h),
      Paint()..color = const Color(0xFF000000),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(w.toInt(), h.toInt());
    picture.dispose();
    return image;
  }

  /// Paints [pass], rendered for [passView] at [passSize], under [view] at
  /// [size], and returns the red channel of the result.
  Future<int Function(int, int)> paint({
    required ui.Image source,
    required ui.Image pass,
    required ViewTransform passView,
    required Size passSize,
    required ViewTransform view,
    required Size size,
  }) async {
    final disposer = DeferredDisposer();
    final recorder = ui.PictureRecorder();
    final painter = ValuePainter(
      shader: await ValueShader.load(),
      source: source,
      blurred: pass,
      blurredView: passView,
      blurredSize: passSize,
      settings: const StudySettings(steps: 2),
      view: view,
      devicePixelRatio: 1,
      peeking: false,
      splitPosition: 0.5,
      disposer: disposer,
      drawGrid: false,
    )..paint(Canvas(recorder, Offset.zero & size), size);
    final image = await recorder.endRecording().toImage(
      size.width.round(),
      size.height.round(),
    );
    painter.disposeResources();
    disposer.disposeAll();
    final bytes = (await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!.buffer.asUint8List();
    final w = image.width;
    image.dispose();
    // Red, or -1 where nothing is painted: until the new pass lands, room
    // the old one never covered is left to the surround.
    return (x, y) {
      final i = (y * w + x) * 4;
      return bytes[i + 3] == 0 ? -1 : bytes[i];
    };
  }

  /// Finds the dark block's left and top edges on screen and checks they are
  /// where [view] puts them.
  void expectBlockWhere(
    int Function(int, int) red,
    ViewTransform view,
    Size size,
  ) {
    final dest = view.destination(src, size);
    final left = (dest.left + dest.width / 2).round();
    final top = (dest.top + dest.height / 4).round();
    int firstDark(int Function(int) at, int length) {
      for (var i = 0; i < length; i++) {
        final r = at(i);
        if (r >= 0 && r < 128) return i;
      }
      return -1;
    }

    // Across, at a height well inside the block; down, at a column inside
    // it.
    final row = (dest.top + dest.height * 0.625).round();
    final column = (dest.left + dest.width * 0.6).round();
    expect(
      firstDark((x) => red(x, row), size.width.toInt()),
      closeTo(left, 3),
      reason: "the block's left edge",
    );
    expect(
      firstDark((y) => red(column, y), size.height.toInt()),
      closeTo(top, 3),
      reason: "the block's top edge",
    );
  }

  test('a stale pass follows a zoom, landing on the same photograph', () async {
    final source = await marked();
    addTearDown(source.dispose);
    const size = Size(400, 600);
    const before = ViewTransform();
    final pass = await renderBlurredSource(
      source: source,
      outputPx: size,
      detail: 1,
      view: before,
    );
    addTearDown(pass.dispose);

    // Pinched in to 2x about a point left of and above the middle.
    final after = before.zoomedAt(const Offset(120, 200), 2, src, size);
    final red = await paint(
      source: source,
      pass: pass,
      passView: before,
      passSize: size,
      view: after,
      size: size,
    );
    expectBlockWhere(red, after, size);
  });

  test(
    'a stale pass keeps its proportions when the picture gets more room',
    () async {
      final source = await marked();
      addTearDown(source.dispose);
      // Zoomed in, so the picture covers its frame and the frame's shape
      // matters; then the controls go and the frame grows taller.
      const view = ViewTransform(zoom: 2, offset: Offset(-0.3, -0.4));
      const small = Size(400, 520), big = Size(400, 760);
      final pass = await renderBlurredSource(
        source: source,
        outputPx: small,
        detail: 1,
        view: view,
      );
      addTearDown(pass.dispose);

      final red = await paint(
        source: source,
        pass: pass,
        passView: view,
        passSize: small,
        view: view,
        size: big,
      );
      expectBlockWhere(red, view, big);
    },
  );
}
