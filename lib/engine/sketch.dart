import 'dart:math' as math;
import 'dart:ui';

import 'lines.dart';

/// A photograph of the drawing being made from the study, laid over the
/// picture so its key points can be checked against the reference.
///
/// Placed by moving, turning and scaling it, nothing more. The scale is one
/// number, [width], so the photograph keeps its own proportions: stretching
/// it one way would hide the very errors it is there to show.
///
/// Placed on the photograph, not the screen: [center] is a fraction of each
/// side of the whole photograph, as [BoardLine] measures its ends, and
/// [width] a fraction of the photograph's width. Zooming, panning or
/// re-cropping the study leaves the drawing on the passage it was lined up
/// with.
class SketchOverlay {
  const SketchOverlay({
    required this.imageKey,
    required this.center,
    required this.width,
    this.rotation = 0,
    this.opacity = defaultOpacity,
    this.page,
    this.straighten = true,
  });

  /// Names the copy of the photograph in app storage, as [Study.imageKey]
  /// does for the study's own.
  final String imageKey;
  final Offset center;
  final double width;

  /// Clockwise on screen, in radians.
  final double rotation;
  final double opacity;

  /// The corners of the sketchbook page found in the photograph, as
  /// fractions of each side of it, clockwise from the top left; null when
  /// none was found. Kept apart from the photograph, which is stored as it
  /// came, so a page found wrongly costs nothing.
  final List<Offset>? page;

  /// Whether the drawing is shown squared up to [page] rather than as the
  /// whole photograph. Means nothing without a page.
  final bool straighten;

  /// The page the drawing is cropped and squared up to, if it is.
  List<Offset>? get straightenedTo => straighten ? page : null;

  static const double defaultOpacity = 0.5;

  /// Far enough either way to cover any sensible framing of the drawing,
  /// near enough that it cannot be lost to a slip of the wheel.
  static const double minWidth = 0.05;
  static const double maxWidth = 8;

  SketchOverlay copyWith({
    Offset? center,
    double? width,
    double? rotation,
    double? opacity,
    bool? straighten,
  }) => SketchOverlay(
    imageKey: imageKey,
    center: center ?? this.center,
    width: width ?? this.width,
    rotation: rotation ?? this.rotation,
    opacity: opacity ?? this.opacity,
    page: page,
    straighten: straighten ?? this.straighten,
  );

  Map<String, Object?> toJson() => {
    'imageKey': imageKey,
    'center': [center.dx, center.dy],
    'width': width,
    'rotation': rotation,
    'opacity': opacity,
    if (page case final page?) ...{
      'page': [
        for (final c in page) [c.dx, c.dy],
      ],
      'straighten': straighten,
    },
  };

  /// Null for anything too damaged to place: no image, or no position.
  static SketchOverlay? fromJson(Object? json) {
    if (json is! Map) return null;
    final key = json['imageKey'];
    final center = json['center'];
    final width = json['width'];
    if (key is! String || key.isEmpty) return null;
    if (center is! List || center.length != 2) return null;
    if (center.any((v) => v is! num || !v.isFinite)) return null;
    if (width is! num || !width.isFinite || width <= 0) return null;
    final rotation = json['rotation'];
    final opacity = json['opacity'];
    return SketchOverlay(
      imageKey: key,
      center: Offset(
        (center[0] as num).toDouble().clamp(0.0, 1.0),
        (center[1] as num).toDouble().clamp(0.0, 1.0),
      ),
      width: width.toDouble().clamp(minWidth, maxWidth),
      rotation: rotation is num && rotation.isFinite ? rotation.toDouble() : 0,
      opacity: opacity is num && opacity.isFinite
          ? opacity.toDouble().clamp(0.0, 1.0)
          : defaultOpacity,
      // A damaged page costs the straightening, not the drawing.
      page: _pageFromJson(json['page']),
      straighten: json['straighten'] != false,
    );
  }

  static List<Offset>? _pageFromJson(Object? json) {
    if (json is! List || json.length != 4) return null;
    final corners = <Offset>[];
    for (final c in json) {
      if (c is! List || c.length != 2) return null;
      if (c.any((v) => v is! num || !v.isFinite)) return null;
      corners.add(
        Offset(
          (c[0] as num).toDouble().clamp(0.0, 1.0),
          (c[1] as num).toDouble().clamp(0.0, 1.0),
        ),
      );
    }
    return corners;
  }

  @override
  bool operator ==(Object other) =>
      other is SketchOverlay &&
      other.imageKey == imageKey &&
      other.center == center &&
      other.width == width &&
      other.rotation == rotation &&
      other.opacity == opacity &&
      _samePage(other.page, page) &&
      other.straighten == straighten;

  static bool _samePage(List<Offset>? a, List<Offset>? b) {
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    imageKey,
    center,
    width,
    rotation,
    opacity,
    page == null ? null : Object.hashAll(page!),
    straighten,
  );
}

/// A drawing of [sketch]'s size laid square over the [crop] of a
/// photograph of [photo]'s size, as large as fits inside it: where a
/// photograph of the board, cropped to the board's shape, already nearly
/// lines up.
SketchOverlay fittedSketch({
  required String imageKey,
  required Size photo,
  required Size sketch,
  required Rect crop,
  List<Offset>? page,
  bool straighten = true,
}) {
  final room = Size(crop.width * photo.width, crop.height * photo.height);
  final scale = math.min(
    room.width / sketch.width,
    room.height / sketch.height,
  );
  return SketchOverlay(
    imageKey: imageKey,
    center: crop.center,
    width: (sketch.width * scale / photo.width).clamp(
      SketchOverlay.minWidth,
      SketchOverlay.maxWidth,
    ),
    page: page,
    straighten: straighten,
  );
}

/// The drawing's centre and width on screen, when the [crop] of the
/// photograph is drawn into [picture].
({Offset center, double width}) sketchOnScreen(
  SketchOverlay sketch,
  Rect crop,
  Rect picture,
) => (
  center: lineToScreen(sketch.center, crop, picture),
  width: sketch.width / crop.width * picture.width,
);

/// [start] as a gesture leaves it: turned by [rotation] and scaled by
/// [scale] about the point that began at [focalStart], which has since moved
/// to [focal]. The point of the drawing under the fingers stays under them.
SketchOverlay movedSketch(
  SketchOverlay start, {
  required Offset focalStart,
  required Offset focal,
  double scale = 1,
  double rotation = 0,
  required Rect crop,
  required Rect picture,
}) {
  final width = (start.width * scale).clamp(
    SketchOverlay.minWidth,
    SketchOverlay.maxWidth,
  );
  // The scale actually applied, so a clamped width does not still pull the
  // centre toward the focal point as if it had grown.
  final k = width / start.width;
  final from = lineToScreen(start.center, crop, picture) - focalStart;
  final cos = math.cos(rotation);
  final sin = math.sin(rotation);
  final turned = Offset(
    from.dx * cos - from.dy * sin,
    from.dx * sin + from.dy * cos,
  );
  final center = screenToLine(focal + turned * k, crop, picture);
  return start.copyWith(
    // Held on the photograph, so some of the drawing is always within reach.
    center: Offset(center.dx.clamp(0.0, 1.0), center.dy.clamp(0.0, 1.0)),
    width: width,
    rotation: _wrap(start.rotation + rotation),
  );
}

/// Into -pi..pi, so a drawing turned round and round does not store an
/// ever-growing angle.
double _wrap(double angle) {
  final turned = (angle + math.pi) % (2 * math.pi);
  return turned - math.pi;
}

/// Lays [image] over the picture as [sketch] places it, clipped to
/// [visible]. With [outline], its edge is ruled too, to show what a drag is
/// moving.
void paintSketch(
  Canvas canvas,
  Image image,
  SketchOverlay sketch,
  Rect crop,
  Rect picture,
  Rect visible, {
  Paint? outline,
}) {
  if (visible.isEmpty || picture.isEmpty) return;
  final placed = sketchOnScreen(sketch, crop, picture);
  final height = placed.width * image.height / image.width;
  final dst = Rect.fromCenter(
    center: Offset.zero,
    width: placed.width,
    height: height,
  );
  canvas.save();
  canvas.clipRect(visible);
  canvas.translate(placed.center.dx, placed.center.dy);
  canvas.rotate(sketch.rotation);
  canvas.drawImageRect(
    image,
    Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
    dst,
    Paint()
      ..color = Color.fromRGBO(0, 0, 0, sketch.opacity)
      ..filterQuality = FilterQuality.medium,
  );
  if (outline != null) canvas.drawRect(dst, outline);
  canvas.restore();
}
