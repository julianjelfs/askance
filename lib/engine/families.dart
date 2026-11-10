import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'crop.dart';
import 'lstar.dart';
import 'regions.dart';
import 'tone.dart';
import 'value_scale.dart';

/// Light and shadow: the two families every value under a single light
/// belongs to.
///
/// Every surface is either turned towards the light or away from it, so the
/// values split into a light family (lights and halftones) and a shadow
/// family (form and cast shadows, reflected light, accents), and everything
/// in the light is lighter than everything in the shadow. A drawing goes
/// wrong when one family leaks into the other: a reflected light rendered
/// bright enough to read as lit, a halftone pushed dark enough to read as
/// shadow.
///
/// The darkest [shadowBands] of the steps are shadow, the rest light. The
/// line between the families sits on one of the band boundaries, or, with a
/// [FamilySplit], anywhere: then each family is banded on its own, so no step
/// straddles the line. Its first place is Otsu's threshold for the whole
/// photograph, the valley between its darks and lights; after that it moves
/// only by hand.

/// The hues the families are tinted towards: cool shadows, warm lights. The
/// cool is the old cool scale's; the warm is a yellow-orange, kept clear of
/// the cadmium accent the outline is drawn in.
const double kShadowHue = 214;
const double kLightHue = 40;

/// How much of the gamut's chroma a family tint takes. Gentler than a tinted
/// scale: the tint says which side of the line a band is on, and should not
/// shout over the values themselves.
const double kFamilyTint = 0.45;

/// The scale's ramp with the shadow family tinted cool and the light family
/// warm, each band at exactly the L* the grey ramp puts it at, so a family
/// tint never moves a value.
///
/// With [gap], the ramp is one value longer and the value at the line is
/// left out: the "leave 5 unused" of a drawing, which keeps the darkest light
/// clear of the lightest shadow.
List<Color> familyRamp(
  ValueScale scale,
  int steps,
  int shadowBands, {
  bool gap = false,
}) {
  final targets = scale.lstarTargets(gap ? steps + 1 : steps);
  if (gap) targets.removeAt(shadowBands);
  return [
    for (final (i, target) in targets.indexed)
      colourAtLstar(
        hue: i < shadowBands ? kShadowHue : kLightHue,
        lstar: target,
        saturation: kFamilyTint,
      ),
  ];
}

/// Where a band falls: its family, if the study has families, and its step
/// within it, darkest first.
class BandPlace {
  const BandPlace({
    required this.band,
    required this.steps,
    required this.shadowBands,
  });

  /// Darkest first, 0 to steps - 1.
  final int band;
  final int steps;

  /// How many bands, darkest first, are shadow; null with no families.
  final int? shadowBands;

  /// Null with no families.
  bool? get inShadow => switch (shadowBands) {
    final s? => band < s,
    null => null,
  };

  /// The step within its family, or within all the steps with no families,
  /// counted from 1 at the darkest.
  int get step => switch (shadowBands) {
    final s? when band >= s => band - s + 1,
    _ => band + 1,
  };

  /// How many steps its family has, or all of them with no families.
  int get of => switch (shadowBands) {
    final s? => band < s ? s : steps - s,
    null => steps,
  };

  /// "Shadow · 2 of 2", "Light · 1 of 3", or "Value 3 of 5".
  String get label => switch (inShadow) {
    true => 'Shadow · $step of $of',
    false => 'Light · $step of $of',
    null => 'Value $step of $of',
  };
}

/// The band the shader puts an opaque sRGB colour in, by the same rule
/// [bandsFromRgba] holds it to.
int bandOfColour(
  int r,
  int g,
  int b,
  int steps, {
  required double bias,
  required double contrast,
  FamilySplit? split,
}) {
  final px = ByteData(4)
    ..setUint8(0, r)
    ..setUint8(1, g)
    ..setUint8(2, b)
    ..setUint8(3, 255);
  return bandsFromRgba(
    px,
    1,
    1,
    steps,
    bias: bias,
    contrast: contrast,
    split: split,
  ).bands[0];
}

/// The colour of [image] at [at], in its own pixels, as 8-bit sRGB; null
/// outside it. One pixel drawn into an image of its own and read back, so
/// the whole image never has to leave the GPU.
Future<(int, int, int)?> readPixel(ui.Image image, Offset at) async {
  final x = at.dx.floor(), y = at.dy.floor();
  if (x < 0 || y < 0 || x >= image.width || y >= image.height) return null;
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawImageRect(
    image,
    Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1),
    const Rect.fromLTWH(0, 0, 1, 1),
    Paint()..filterQuality = FilterQuality.none,
  );
  final picture = recorder.endRecording();
  final pixel = await picture.toImage(1, 1);
  picture.dispose();
  final data = await pixel.toByteData(format: ui.ImageByteFormat.rawRgba);
  pixel.dispose();
  if (data == null) return null;
  return (data.getUint8(0), data.getUint8(1), data.getUint8(2));
}

/// Otsu's threshold for [histogram]: the boundary that leaves the two sides
/// as tight as they can be about their own means, which is the valley
/// between two humps. As a fraction of the way along the bins.
double otsu(List<int> histogram) {
  final n = histogram.length;
  var total = 0, sum = 0.0;
  for (var i = 0; i < n; i++) {
    total += histogram[i];
    sum += i * histogram[i];
  }
  if (total == 0) return 0.5;
  var below = 0, sumBelow = 0.0, best = -1.0, cut = n ~/ 2;
  for (var i = 0; i < n - 1; i++) {
    below += histogram[i];
    sumBelow += i * histogram[i];
    final above = total - below;
    if (below == 0 || above == 0) continue;
    final d = sumBelow / below - (sum - sumBelow) / above;
    final between = below.toDouble() * above * d * d;
    if (between > best) {
      best = between;
      cut = i + 1;
    }
  }
  return cut / n;
}

/// Where the family line starts: Otsu's threshold over the toned lightness
/// of the whole of [source] inside [crop], whatever part of it is on screen.
Future<double> otsuLine(
  ui.Image source,
  Rect crop, {
  required double bias,
  required double contrast,
}) async {
  final from = cropPixels(
    Size(source.width.toDouble(), source.height.toDouble()),
    crop,
  );
  // A few tens of thousands of pixels make the same histogram as millions.
  final scale = math.min(1.0, 256 / math.max(from.width, from.height));
  final w = math.max(1, (from.width * scale).round());
  final h = math.max(1, (from.height * scale).round());
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawImageRect(
    source,
    from,
    Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    Paint()..filterQuality = FilterQuality.medium,
  );
  final picture = recorder.endRecording();
  final small = await picture.toImage(w, h);
  picture.dispose();
  final data = await small.toByteData(format: ui.ImageByteFormat.rawRgba);
  small.dispose();
  final histogram = List<int>.filled(256, 0);
  if (data != null) {
    for (var p = 0; p + 3 < data.lengthInBytes; p += 4) {
      final l = lstarOfSrgb8(
        data.getUint8(p),
        data.getUint8(p + 1),
        data.getUint8(p + 2),
      );
      final t = toneCurve(l / 100, shift: bias, contrast: contrast);
      histogram[math.min(255, (t * 256).floor())]++;
    }
  }
  return otsu(histogram);
}
