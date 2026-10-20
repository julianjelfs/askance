import 'dart:math' as math;
import 'dart:ui';

/// The whole photograph, as a crop.
///
/// A crop is a fraction of each side of the source image rather than a pixel
/// rect, for the same reason the view's pan is: the same study is drawn from
/// the original at screen size, at export size and small on a shelf card, and
/// a fraction means the same thing at all of them.
const Rect kWholeImage = Rect.fromLTRB(0, 0, 1, 1);

/// Smallest crop, as a share of the largest one of its shape. Below this the
/// study is of so few source pixels that the zoom has nothing left to give.
const double kMinCropScale = 0.15;

/// The part of an [image]-sized photograph that [crop] stands for, in the
/// photograph's own pixels.
Rect cropPixels(Size image, Rect crop) => Rect.fromLTRB(
  crop.left * image.width,
  crop.top * image.height,
  crop.right * image.width,
  crop.bottom * image.height,
);

/// The picture a study is of: the size of [crop] out of an [image]-sized
/// photograph. Everything downstream of the crop — framing, zoom, the grid,
/// exports — treats this as the photograph.
Size croppedSize(Size image, Rect crop) => cropPixels(image, crop).size;

/// The shapes a crop can take, as short side over long.
///
/// A-series paper is one shape at every size, which is the point of it: an A4
/// crop is an A3 crop and an A5 one, so a study squared up for one board
/// transfers to any of them.
enum CropShape {
  whole('WHOLE', null),
  aSeries('A4', math.sqrt1_2),
  fourFive('4:5', 0.8),
  square('1:1', 1);

  const CropShape(this.label, this.shortOverLong);

  final String label;

  /// Null for [whole], which takes the photograph's own shape.
  final double? shortOverLong;

  /// Width over height, the way round [landscape] asks for.
  double? aspect({required bool landscape}) => switch (shortOverLong) {
    null => null,
    final r => landscape ? 1 / r : r,
  };
}

/// A crop of [aspect] (width over height, in pixels) out of an [image]-sized
/// photograph: [scale] of the largest one that fits, centred as close to
/// [centre] as it can be without leaving the photograph.
Rect fitCrop(
  Size image,
  double aspect, {
  Offset centre = const Offset(0.5, 0.5),
  double scale = 1,
}) {
  var w = image.width;
  var h = w / aspect;
  if (h > image.height) {
    h = image.height;
    w = h * aspect;
  }
  final k = scale.clamp(kMinCropScale, 1.0);
  w *= k;
  h *= k;
  final cx = (centre.dx * image.width).clamp(w / 2, image.width - w / 2);
  final cy = (centre.dy * image.height).clamp(h / 2, image.height - h / 2);
  return Rect.fromLTRB(
    (cx - w / 2) / image.width,
    (cy - h / 2) / image.height,
    (cx + w / 2) / image.width,
    (cy + h / 2) / image.height,
  );
}

/// How big [crop] is against the largest crop of its own shape, the inverse
/// of [fitCrop]'s scale.
double cropScaleOf(Size image, Rect crop) {
  final px = cropPixels(image, crop);
  if (px.isEmpty) return 1;
  final largest = cropPixels(image, fitCrop(image, px.width / px.height));
  return (px.width / largest.width).clamp(kMinCropScale, 1.0);
}

/// The shape [crop] was cut to, and which way round; null when it matches
/// none, which only a hand-edited manifest can produce.
({CropShape shape, bool landscape})? cropShapeOf(Size image, Rect crop) {
  if (crop == kWholeImage) return (shape: CropShape.whole, landscape: false);
  final px = cropPixels(image, crop);
  if (px.isEmpty) return null;
  final aspect = px.width / px.height;
  for (final shape in CropShape.values) {
    for (final landscape in const [false, true]) {
      final target = shape.aspect(landscape: landscape);
      // A pixel either way on a small image is a fraction of a percent; a
      // different preset is never closer than ten.
      if (target != null && (aspect / target - 1).abs() < 0.01) {
        return (shape: shape, landscape: landscape);
      }
    }
  }
  return null;
}

/// Reads a stored crop, falling back to the whole photograph for anything
/// that is not a usable rect inside it.
Rect cropFromJson(Object? json) {
  if (json is! List || json.length != 4 || json.any((v) => v is! num)) {
    return kWholeImage;
  }
  final [l, t, r, b] = [for (final v in json) (v as num).toDouble()];
  if (l < 0 || t < 0 || r > 1 || b > 1) return kWholeImage;
  // Narrower than this is not a crop anyone made on purpose.
  if (r - l < 0.01 || b - t < 0.01) return kWholeImage;
  return Rect.fromLTRB(l, t, r, b);
}

List<double> cropToJson(Rect crop) => [
  crop.left,
  crop.top,
  crop.right,
  crop.bottom,
];
