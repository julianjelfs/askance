import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:askance/engine/engine.dart';
import 'package:askance/engine/regions.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// The app's central claim: zooming resolves finer shapes without changing the
/// scale. Because the blur runs in screen space at a sigma fixed to the output
/// width, a zoomed-in frame shows the same shape *size* but more shapes — so
/// the density of band boundaries should hold roughly steady as you zoom, not
/// fall away with the magnification.
void main() {
  /// A source whose detail density is the same at every scale.
  ///
  /// The circle count quadruples as the radius halves, so any sub-rectangle
  /// contains roughly as much structure per unit area as the whole. Without
  /// that, zooming into a fraction of the frame shows fewer features simply
  /// because there were fewer there to begin with, and the measurement below
  /// says nothing about the engine.
  Future<ui.Image> fractalSource(int side) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble()),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble()),
      Paint()..color = const Color(0xFF808080),
    );
    final random = math.Random(7);
    for (var band = 0; band < 6; band++) {
      final step = side / math.pow(2, band + 1);
      final count = 8 * math.pow(4, band).toInt();
      for (var i = 0; i < count; i++) {
        final grey = random.nextInt(256);
        canvas.drawCircle(
          Offset(random.nextDouble() * side, random.nextDouble() * side),
          step * (0.12 + random.nextDouble() * 0.2),
          Paint()..color = Color.fromARGB(255, grey, grey, grey),
        );
      }
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(side, side);
    picture.dispose();
    return image;
  }

  /// Fraction of horizontally adjacent cells that sit in different bands.
  double edgeDensity(BandMap map) {
    var edges = 0, total = 0;
    for (var y = 0; y < map.height; y++) {
      for (var x = 0; x < map.width - 1; x++) {
        final i = y * map.width + x;
        if (map.bands[i] != map.bands[i + 1]) edges++;
        total++;
      }
    }
    return edges / total;
  }

  Future<double> densityAt({
    required ui.Image source,
    required double zoom,
    required double detail,
    required Size output,
    int steps = 4,
  }) async {
    final blurred = await renderBlurredSource(
      source: source,
      outputPx: output,
      detail: detail,
      view: ViewTransform(zoom: zoom),
    );
    final rgba = await blurred.toByteData(format: ui.ImageByteFormat.rawRgba);
    blurred.dispose();
    return edgeDensity(
      bandsFromRgba(rgba!, output.width.round(), output.height.round(), steps),
    );
  }

  test('zooming in resolves more shapes, at the same shape size', () async {
    // Source far larger than the output, so zooming has real detail to reach.
    final source = await fractalSource(2048);
    const output = Size(480, 480);
    addTearDown(source.dispose);

    for (final detail in [0.2, 0.5]) {
      final atOne = await densityAt(
        source: source,
        zoom: 1,
        detail: detail,
        output: output,
      );
      final atThree = await densityAt(
        source: source,
        zoom: 3,
        detail: detail,
        output: output,
      );

      // Magnifying a fixed render would divide the density by the zoom. Holding
      // it near parity is the property that makes zoom useful.
      expect(
        atThree,
        greaterThan(atOne * 0.6),
        reason:
            'at detail $detail the zoomed frame lost too much shape density: '
            '${atOne.toStringAsFixed(4)} -> ${atThree.toStringAsFixed(4)}',
      );
    }
  });

  test('the blur is applied after the zoom, not before it', () async {
    // If the blur were applied to the source and the result then magnified,
    // a zoomed frame would carry the blur magnified with it and its bands
    // would be far smoother than an unzoomed frame at the same setting.
    final source = await fractalSource(2048);
    addTearDown(source.dispose);
    const output = Size(480, 480);

    final atOne = await densityAt(
      source: source,
      zoom: 1,
      detail: 0.35,
      output: output,
    );
    final atSix = await densityAt(
      source: source,
      zoom: 6,
      detail: 0.35,
      output: output,
    );
    expect(atSix, greaterThan(atOne * 0.5));
  });
}
