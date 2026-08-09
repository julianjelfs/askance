import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'engine.dart';
import 'lstar.dart';

/// A labelled region of constant value, in the coordinates of the downsampled
/// band map it was found in.
class ValueRegion {
  const ValueRegion({
    required this.band,
    required this.centroid,
    required this.area,
  });

  final int band;
  final Offset centroid;
  final int area;

  /// The label drawn on the canvas: band index + 1, so "1" is darkest.
  String get label => '${band + 1}';
}

/// The band map the labeller works over, plus the grid it was sampled on.
class BandMap {
  const BandMap(this.bands, this.width, this.height);

  final Uint8List bands;
  final int width;
  final int height;
}

/// Downsample factor for the labelling pass. Chosen so the grid comes out at a
/// near-constant ~60 cells wide whatever the output resolution, which is what
/// makes the area threshold below resolution-independent.
int labelStride(double renderWidth) {
  final s = (8 * renderWidth / kReferenceWidth).round();
  return s < 8 ? 8 : s;
}

/// Converts an RGBA byte buffer into absolute value bands.
BandMap bandsFromRgba(ByteData rgba, int width, int height, int steps) {
  final bytes = rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes);
  final bands = Uint8List(width * height);
  for (var i = 0, p = 0; i < bands.length; i++, p += 4) {
    // The offscreen is opaque, so the premultiplied bytes are the colour.
    final l = lstarOfSrgb8(bytes[p], bytes[p + 1], bytes[p + 2]) / 100;
    var band = (l * steps).floor();
    if (band >= steps) band = steps - 1;
    if (band < 0) band = 0;
    bands[i] = band;
  }
  return BandMap(bands, width, height);
}

/// Connected-component labelling over the band map: 4-connected regions of
/// equal band, keeping those larger than 1/150th of the grid, largest 16 first.
List<ValueRegion> labelRegions(BandMap map, {int limit = 16}) {
  final gw = map.width;
  final gh = map.height;
  final bands = map.bands;
  final seen = Uint8List(gw * gh);
  final stack = <int>[];
  final regions = <ValueRegion>[];
  final minArea = (gw * gh) / 150;

  for (var start = 0; start < bands.length; start++) {
    if (seen[start] == 1) continue;
    final band = bands[start];
    stack
      ..clear()
      ..add(start);
    seen[start] = 1;
    var area = 0, sumX = 0, sumY = 0;

    while (stack.isNotEmpty) {
      final q = stack.removeLast();
      area++;
      final x = q % gw;
      final y = q ~/ gw;
      sumX += x;
      sumY += y;
      if (x > 0 && seen[q - 1] == 0 && bands[q - 1] == band) {
        seen[q - 1] = 1;
        stack.add(q - 1);
      }
      if (x < gw - 1 && seen[q + 1] == 0 && bands[q + 1] == band) {
        seen[q + 1] = 1;
        stack.add(q + 1);
      }
      if (y > 0 && seen[q - gw] == 0 && bands[q - gw] == band) {
        seen[q - gw] = 1;
        stack.add(q - gw);
      }
      if (y < gh - 1 && seen[q + gw] == 0 && bands[q + gw] == band) {
        seen[q + gw] = 1;
        stack.add(q + gw);
      }
    }

    if (area > minArea) {
      regions.add(
        ValueRegion(
          band: band,
          centroid: Offset(sumX / area, sumY / area),
          area: area,
        ),
      );
    }
  }

  regions.sort((a, b) => b.area.compareTo(a.area));
  return regions.length > limit ? regions.sublist(0, limit) : regions;
}

/// Runs the pipeline at labelling resolution and returns the regions to number.
///
/// Because the blur sigma scales with render width, running the whole pipeline
/// small produces the *same shapes* as running it at full size — so this is a
/// cheap pass rather than an approximation. It stays comfortably on the main
/// thread, which matters on web where `compute` has no real isolate to use.
/// The labelled regions, and the grid they were found on.
typedef LabelledRegions = ({
  List<ValueRegion> regions,
  int gridWidth,
  int gridHeight,
});

Future<LabelledRegions> computeRegions({
  required ui.Image source,
  required Size outputPx,
  required double detail,
  required ViewTransform view,
  required int steps,
}) async {
  const empty = (regions: <ValueRegion>[], gridWidth: 0, gridHeight: 0);
  final stride = labelStride(outputPx.width);
  final small = Size(outputPx.width / stride, outputPx.height / stride);

  // The pass covers only what the photograph occupies, which is less than the
  // frame whenever the image is shown whole, so the grid has to be measured
  // against that rather than against the frame.
  final sourceSize = Size(source.width.toDouble(), source.height.toDouble());
  final area = view.visible(sourceSize, small);
  final gw = area.width.round();
  final gh = area.height.round();
  if (gw < 4 || gh < 4) return empty;

  final blurred = await renderBlurredSource(
    source: source,
    outputPx: small,
    detail: detail,
    view: view,
  );
  try {
    if (blurred.width != gw || blurred.height != gh) return empty;
    final rgba = await blurred.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (rgba == null) return empty;
    return (
      regions: labelRegions(bandsFromRgba(rgba, gw, gh, steps)),
      gridWidth: gw,
      gridHeight: gh,
    );
  } finally {
    blurred.dispose();
  }
}
