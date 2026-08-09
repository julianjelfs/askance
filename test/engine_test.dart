import 'dart:typed_data';
import 'dart:ui';

import 'package:askance/engine/engine.dart';
import 'package:askance/engine/lstar.dart';
import 'package:askance/engine/regions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('blur sigma', () {
    test('matches the specified formula', () {
      expect(blurSigma(0, 480), closeTo(16.4, 1e-9));
      expect(blurSigma(1, 480), closeTo(0.4, 1e-9));
      expect(blurSigma(0.5, 480), closeTo(8.4, 1e-9));
    });

    test('scales with render width so shapes stay the same size', () {
      // The whole point of the renderWidth term: doubling the output doubles
      // the blur, so the shapes it produces are identical.
      final small = blurSigma(0.5, 480) - 0.4;
      final large = blurSigma(0.5, 960) - 0.4;
      expect(large / small, closeTo(2, 1e-9));
    });
  });

  group('skeleton line weight', () {
    test('never drops below one pixel and scales with output', () {
      expect(skeletonLineWidth(240), 1);
      expect(skeletonLineWidth(480), 1);
      expect(skeletonLineWidth(1200), 3);
      expect(skeletonLineWidth(2480), 5);
    });
  });

  group('cover crop', () {
    test('fills the frame and aligns 32% from the top', () {
      // A 2:3 source into a taller frame covers by height, overflowing sideways.
      final rect = coverRect(const Size(900, 1350), const Size(320, 664));
      expect(rect.height, greaterThanOrEqualTo(664));
      expect(rect.width, greaterThanOrEqualTo(320));
      expect(rect.left, closeTo((320 - rect.width) / 2, 1e-9));
      expect(rect.top, closeTo((664 - rect.height) * 0.32, 1e-9));
    });

    test('a wide source into a tall frame covers by width', () {
      final rect = coverRect(const Size(4000, 1000), const Size(320, 664));
      expect(rect.width, greaterThanOrEqualTo(320));
      expect(rect.height, greaterThanOrEqualTo(664));
    });
  });

  group('view transform', () {
    const source = Size(900, 1350);
    const output = Size(320, 664);

    test('at 1x the frame is exactly covered', () {
      final rect = const ViewTransform().destination(source, output);
      expect(rect.left, lessThanOrEqualTo(0.001));
      expect(rect.top, lessThanOrEqualTo(0.001));
      expect(rect.right, greaterThanOrEqualTo(output.width - 0.001));
      expect(rect.bottom, greaterThanOrEqualTo(output.height - 0.001));
    });

    test('panning can never expose the ground behind the image', () {
      const zoomed = ViewTransform(zoom: 3, offset: Offset(9999, -9999));
      final rect = zoomed.destination(source, output);
      expect(rect.left, lessThanOrEqualTo(0.001));
      expect(rect.top, lessThanOrEqualTo(0.001));
      expect(rect.right, greaterThanOrEqualTo(output.width - 0.001));
      expect(rect.bottom, greaterThanOrEqualTo(output.height - 0.001));
    });

    test('zoom is clamped to the 1x-6x range', () {
      const start = ViewTransform();
      expect(start.zoomedAt(Offset.zero, 99, source, output).zoom, 6);
      expect(start.zoomedAt(Offset.zero, 0.01, source, output).zoom, 1);
    });

    test('the same view describes the same crop at any output size', () {
      // The photograph is drawn in logical pixels, the blur pass renders in
      // device pixels and an export renders at 1200 wide. All three must agree
      // on the crop, or the two halves of a split slide apart as you zoom.
      const view = ViewTransform(zoom: 2.5, offset: Offset(-0.18, -0.22));
      const logical = Size(320, 664);
      final atLogical = view.destination(source, logical);
      for (final scale in [3.0, 1200 / 320]) {
        final bigger = Size(logical.width * scale, logical.height * scale);
        final atBigger = view.destination(source, bigger);
        expect(
          atBigger.left / bigger.width,
          closeTo(atLogical.left / logical.width, 1e-9),
          reason: 'left at ${scale}x',
        );
        expect(
          atBigger.top / bigger.height,
          closeTo(atLogical.top / logical.height, 1e-9),
          reason: 'top at ${scale}x',
        );
        expect(
          atBigger.width / bigger.width,
          closeTo(atLogical.width / logical.width, 1e-9),
          reason: 'width at ${scale}x',
        );
      }
    });

    test('zooming keeps the focal point under the finger', () {
      const start = ViewTransform();
      const focus = Offset(100, 200);
      final zoomed = start.zoomedAt(focus, 2, source, output);
      // The source point under `focus` before the zoom is still under it after,
      // expressed as a fraction of the image rect.
      final before = start.destination(source, output);
      final after = zoomed.destination(source, output);
      final fx = (focus.dx - before.left) / before.width;
      final fy = (focus.dy - before.top) / before.height;
      expect(after.left + fx * after.width, closeTo(focus.dx, 0.001));
      expect(after.top + fy * after.height, closeTo(focus.dy, 0.001));
    });
  });

  group('label stride', () {
    test('holds the labelling grid near a constant width', () {
      for (final width in [480.0, 1200.0, 2480.0, 3720.0]) {
        final grid = width / labelStride(width);
        expect(grid, closeTo(60, 5), reason: 'at \$width');
      }
    });

    test('never goes below 8, so small frames label more coarsely', () {
      expect(labelStride(100), 8);
      expect(labelStride(320), 8);
    });
  });

  group('band map', () {
    ByteData rgbaOf(List<List<int>> greys) {
      final bytes = Uint8List(greys.length * greys.first.length * 4);
      var p = 0;
      for (final row in greys) {
        for (final v in row) {
          bytes[p++] = v;
          bytes[p++] = v;
          bytes[p++] = v;
          bytes[p++] = 255;
        }
      }
      return ByteData.view(bytes.buffer);
    }

    test('quantises on absolute thresholds, band 0 darkest', () {
      // L* of 0, 128 and 255 is 0, 53.6 and 100; at 3 steps that is 0, 1, 2.
      final map = bandsFromRgba(
        rgbaOf([
          [0, 128, 255],
        ]),
        3,
        1,
        3,
      );
      expect(map.bands, [0, 1, 2]);
    });

    test('white lands in the top band rather than overflowing', () {
      for (var steps = 2; steps <= 7; steps++) {
        final map = bandsFromRgba(
          rgbaOf([
            [255],
          ]),
          1,
          1,
          steps,
        );
        expect(map.bands.first, steps - 1, reason: 'at $steps steps');
      }
    });

    test(
      'a pixel keeps its band whatever the step count of its neighbours',
      () {
        // Absolute thresholds mean the same grey is the same band in any frame.
        final wide = bandsFromRgba(
          rgbaOf([
            [40, 40, 200, 200],
          ]),
          4,
          1,
          4,
        );
        final crop = bandsFromRgba(
          rgbaOf([
            [40, 200],
          ]),
          2,
          1,
          4,
        );
        expect(wide.bands[0], crop.bands[0]);
        expect(wide.bands[2], crop.bands[1]);
      },
    );
  });

  group('region labelling', () {
    BandMap mapOf(List<List<int>> rows) {
      final w = rows.first.length;
      final bands = Uint8List(w * rows.length);
      var i = 0;
      for (final row in rows) {
        for (final v in row) {
          bands[i++] = v;
        }
      }
      return BandMap(bands, w, rows.length);
    }

    test('finds one region per connected block of equal band', () {
      final rows = List.generate(
        20,
        (y) => List.generate(20, (x) => x < 10 ? 0 : 2),
      );
      final regions = labelRegions(mapOf(rows));
      expect(regions.length, 2);
      expect(regions.map((r) => r.band).toSet(), {0, 2});
    });

    test('regions are ordered largest first', () {
      final rows = List.generate(
        20,
        (y) => List.generate(20, (x) => x < 4 ? 0 : 2),
      );
      final regions = labelRegions(mapOf(rows));
      expect(regions.first.band, 2);
      expect(regions.first.area, greaterThan(regions.last.area));
    });

    test('specks below a 150th of the grid are dropped', () {
      final rows = List.generate(20, (y) => List.generate(20, (x) => 0));
      // A 2x1 speck in a 400-cell grid is under the 2.67-cell threshold.
      rows[5][5] = 3;
      rows[5][6] = 3;
      final regions = labelRegions(mapOf(rows));
      expect(regions.every((r) => r.band != 3), isTrue);
    });

    test('labels are the band index plus one, so 1 is darkest', () {
      final rows = List.generate(10, (y) => List.generate(10, (x) => 0));
      expect(labelRegions(mapOf(rows)).single.label, '1');
    });

    test('at most sixteen regions are labelled', () {
      // A fine checkerboard of alternating bands makes far more than 16.
      final rows = List.generate(
        60,
        (y) => List.generate(60, (x) => ((x ~/ 3) + (y ~/ 3)) % 2),
      );
      expect(labelRegions(mapOf(rows)).length, lessThanOrEqualTo(16));
    });

    test('the centroid of a square region is its middle', () {
      final rows = List.generate(20, (y) => List.generate(20, (x) => 0));
      final region = labelRegions(mapOf(rows)).single;
      expect(region.centroid.dx, closeTo(9.5, 0.001));
      expect(region.centroid.dy, closeTo(9.5, 0.001));
    });
  });

  group('lstar helpers', () {
    test('sRGB round-trips through linear light', () {
      for (var v = 0; v <= 255; v += 17) {
        final c = v / 255;
        expect(linearToSrgb(srgbToLinear(c)), closeTo(c, 1e-9));
      }
    });
  });
}
