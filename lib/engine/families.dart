import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'regions.dart';
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
/// Here the line between the families sits on one of the existing band
/// boundaries: the darkest [shadowBands] of the steps are shadow, the rest
/// light. The quantisation itself is untouched, so a value means what it
/// always did.

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
List<Color> familyRamp(ValueScale scale, int steps, int shadowBands) => [
  for (final (i, target) in scale.lstarTargets(steps).indexed)
    colourAtLstar(
      hue: i < shadowBands ? kShadowHue : kLightHue,
      lstar: target,
      saturation: kFamilyTint,
    ),
];

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
