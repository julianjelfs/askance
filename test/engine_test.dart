import 'dart:ui';

import 'package:askance/engine/engine.dart';
import 'package:askance/engine/lstar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('blur sigma', () {
    test('spans the range the control is defined over', () {
      expect(blurSigma(0, 480), closeTo(16.4, 1e-9));
      expect(blurSigma(1, 480), closeTo(0.4, 1e-9));
    });

    test('ramps geometrically, so the slider is used all the way', () {
      // Linear put the halfway point at 8.4, which is heavy enough that the
      // whole lower half of the control looked alike.
      expect(blurSigma(0.5, 480), closeTo(2.561, 1e-3));
    });

    test('scales with render width so shapes stay the same size', () {
      // computeRegions runs the pipeline small and needs the same shapes the
      // screen has, which only holds if this is strictly proportional.
      for (final detail in [0.0, 0.25, 0.5, 0.75, 1.0]) {
        expect(
          blurSigma(detail, 960) / blurSigma(detail, 480),
          closeTo(2, 1e-9),
          reason: 'sigma drifted with resolution at detail $detail',
        );
      }
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

  group('showing the whole photograph', () {
    test('a portrait fits inside a tall frame with room to spare', () {
      final rect = containRect(const Size(900, 1350), const Size(320, 664));
      expect(rect.width, lessThanOrEqualTo(320.001));
      expect(rect.height, lessThanOrEqualTo(664.001));
      // Nothing is cropped: the whole of both dimensions is on screen.
      expect(rect.width / rect.height, closeTo(900 / 1350, 1e-9));
    });

    test('a landscape shows whole rather than filling the height', () {
      const output = Size(320, 664);
      final rect = containRect(const Size(4000, 1000), output);
      expect(
        rect.width,
        closeTo(320, 0.001),
        reason: 'a wide photograph should meet the sides',
      );
      expect(
        rect.height,
        lessThan(output.height),
        reason: 'and leave the ground showing above and below',
      );
      expect(rect.width / rect.height, closeTo(4, 1e-9));
    });

    test('the image is centred in whatever room is left over', () {
      const output = Size(320, 664);
      final rect = containRect(const Size(4000, 1000), output);
      expect(rect.center.dx, closeTo(output.width / 2, 1e-9));
      expect(rect.center.dy, closeTo(output.height / 2, 1e-9));
    });

    test('a frame-shaped photograph fills it exactly', () {
      final rect = containRect(const Size(640, 1328), const Size(320, 664));
      expect(rect, const Rect.fromLTWH(0, 0, 320, 664));
    });
  });

  group('view transform', () {
    const source = Size(900, 1350);
    const output = Size(320, 664);

    test('at 1x the whole photograph is on screen', () {
      final rect = const ViewTransform().destination(source, output);
      expect(rect.left, greaterThanOrEqualTo(-0.001));
      expect(rect.top, greaterThanOrEqualTo(-0.001));
      expect(rect.right, lessThanOrEqualTo(output.width + 0.001));
      expect(rect.bottom, lessThanOrEqualTo(output.height + 0.001));
    });

    test('the visible area is the picture at 1x and the frame once zoomed', () {
      const view = ViewTransform();
      final whole = view.visible(source, output);
      expect(whole, view.destination(source, output));

      // Zoomed far enough to cover, the picture and the frame are the same.
      final zoomed = const ViewTransform(zoom: 6).visible(source, output);
      expect(zoomed.width, closeTo(output.width, 0.001));
      expect(zoomed.height, closeTo(output.height, 0.001));
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

  group('lstar helpers', () {
    test('sRGB round-trips through linear light', () {
      for (var v = 0; v <= 255; v += 17) {
        final c = v / 255;
        expect(linearToSrgb(srgbToLinear(c)), closeTo(c, 1e-9));
      }
    });
  });

  group('covering a card', () {
    // A 4:5 shelf card, and a photograph far wider than it.
    const card = Size(160, 200);
    const landscape = Size(4000, 1000);

    test('fills the card rather than letterboxing it', () {
      final view = coveringView(const ViewTransform(), landscape, card);
      final rect = view.destination(landscape, card);
      expect(rect.left, lessThanOrEqualTo(0.001));
      expect(rect.top, lessThanOrEqualTo(0.001));
      expect(rect.right, greaterThanOrEqualTo(card.width - 0.001));
      expect(rect.bottom, greaterThanOrEqualTo(card.height - 0.001));
    });

    test('takes the middle of a landscape, not its left edge', () {
      final view = coveringView(const ViewTransform(), landscape, card);
      final rect = view.destination(landscape, card);
      expect(
        rect.center.dx,
        closeTo(card.width / 2, 0.001),
        reason: 'whatever the photograph is of is more likely to be central',
      );
    });

    test('a view that already covers is left alone', () {
      // A portrait fills a card by width at 1x, so nothing needs adding.
      const portrait = Size(800, 1000);
      const panned = ViewTransform(zoom: 2, offset: Offset(-0.1, -0.2));
      final view = coveringView(panned, portrait, card);
      expect(view.zoom, 2, reason: 'the zoom it was left at');
    });
  });
}
