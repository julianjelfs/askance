import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'value_scale.dart';

/// How the quantised image is presented.
enum ViewMode {
  value('VAL', 'VALUE MAP'),
  photo('PHOTO', 'PHOTOGRAPH'),
  split('SPLIT', 'SPLIT'),
  skeleton('EDGE', 'SKELETON');

  const ViewMode(this.railLabel, this.longLabel);

  /// Label used on the phone's right-edge rail, which is 44px wide.
  final String railLabel;

  /// Label used in the desktop rail, which has room for the full word.
  final String longLabel;
}

/// Vertical alignment of the cover crop: 32% from the top rather than centred,
/// which keeps a head in frame on portrait sources.
const double kCropAlignY = 0.32;

/// The width the blur and line-weight constants were tuned at.
const double kReferenceWidth = 480;

/// Gaussian sigma for the "detail" control. The renderWidth term keeps shapes
/// the same size at any output resolution.
double blurSigma(double detail, double renderWidth) =>
    (1 - detail) * 16 * (renderWidth / kReferenceWidth) + 0.4;

/// Skeleton stroke weight, in output pixels.
double skeletonLineWidth(double renderWidth) =>
    math.max(1, (renderWidth / kReferenceWidth).roundToDouble());

/// Where the source image lands when cover-cropped into a [output]-sized frame
/// at 1x zoom.
Rect coverRect(Size source, Size output) {
  final scale = math.max(
    output.width / source.width,
    output.height / source.height,
  );
  final w = source.width * scale;
  final h = source.height * scale;
  return Rect.fromLTWH(
    (output.width - w) / 2,
    (output.height - h) * kCropAlignY,
    w,
    h,
  );
}

/// Pan/zoom over the cover-cropped frame.
///
/// [offset] is a *fraction* of the output size, not a pixel count, so the same
/// transform describes the same crop at any resolution. That matters because
/// the same view is applied at three different scales at once: the photograph
/// is drawn in logical pixels, the blur pass renders in device pixels, and an
/// export renders at 1200 or 2480 wide. A pixel offset would make those three
/// disagree the moment you panned or zoomed — visible as the two halves of a
/// split sliding apart.
class ViewTransform {
  const ViewTransform({this.zoom = 1, this.offset = Offset.zero});

  final double zoom;

  /// Pan, as a fraction of the output width and height.
  final Offset offset;

  static const double minZoom = 1;
  static const double maxZoom = 6;

  /// Destination rect for the source image, clamped so the frame is never
  /// allowed to show through at the edges.
  Rect destination(Size source, Size output) {
    final base = coverRect(source, output);
    final scaled = Rect.fromLTWH(
      base.left * zoom + offset.dx * output.width,
      base.top * zoom + offset.dy * output.height,
      base.width * zoom,
      base.height * zoom,
    );
    return _clampToCover(scaled, output);
  }

  /// The offset that [destination] actually used, after clamping.
  Offset clampedOffset(Size source, Size output) {
    if (output.isEmpty) return offset;
    final base = coverRect(source, output);
    final dest = destination(source, output);
    return Offset(
      (dest.left - base.left * zoom) / output.width,
      (dest.top - base.top * zoom) / output.height,
    );
  }

  static Rect _clampToCover(Rect r, Size output) {
    var dx = 0.0, dy = 0.0;
    if (r.width >= output.width) {
      if (r.left > 0) dx = -r.left;
      if (r.right + dx < output.width) dx = output.width - r.right;
    } else {
      dx = (output.width - r.width) / 2 - r.left;
    }
    if (r.height >= output.height) {
      if (r.top > 0) dy = -r.top;
      if (r.bottom + dy < output.height) dy = output.height - r.bottom;
    } else {
      dy = (output.height - r.height) / 2 - r.top;
    }
    return r.shift(Offset(dx, dy));
  }

  ViewTransform copyWith({double? zoom, Offset? offset}) =>
      ViewTransform(zoom: zoom ?? this.zoom, offset: offset ?? this.offset);

  /// Zoom to [target] keeping the point under the finger fixed. [focus] is in
  /// output-space pixels, matching the size the gesture was measured in.
  ViewTransform zoomedAt(
    Offset focus,
    double target,
    Size source,
    Size output,
  ) {
    if (output.isEmpty) return this;
    final next = target.clamp(minZoom, maxZoom);
    final k = next / zoom;
    // The focal point has to be a fraction too, or it is compared against an
    // offset in different units.
    final f = Offset(focus.dx / output.width, focus.dy / output.height);
    final candidate = ViewTransform(
      zoom: next,
      offset: Offset(
        f.dx - (f.dx - offset.dx) * k,
        f.dy - (f.dy - offset.dy) * k,
      ),
    );
    return candidate.copyWith(offset: candidate.clampedOffset(source, output));
  }

  @override
  bool operator ==(Object other) =>
      other is ViewTransform && other.zoom == zoom && other.offset == offset;

  @override
  int get hashCode => Object.hash(zoom, offset);
}

/// Renders the blurred, cropped source at output resolution.
///
/// This is the input to the shader. The blur has to happen in screen space —
/// that is what makes shapes simplify uniformly however far you have zoomed —
/// so it cannot be folded into the fragment pass at sigma 16.
///
/// Deliberately asynchronous: `Picture.toImageSync` hands back an image whose
/// backing texture may not have been rasterised yet, and binding that as a
/// shader sampler intermittently samples an empty texture. `toImage` waits for
/// the raster thread, at the cost of the result landing a frame later.
Future<ui.Image> renderBlurredSource({
  required ui.Image source,
  required Size outputPx,
  required double detail,
  required ViewTransform view,
}) async {
  final w = outputPx.width.round();
  final h = outputPx.height.round();
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(
    recorder,
    Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
  );
  final dest = view.destination(
    Size(source.width.toDouble(), source.height.toDouble()),
    Size(w.toDouble(), h.toDouble()),
  );
  final sigma = blurSigma(detail, w.toDouble());
  canvas.drawImageRect(
    source,
    Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
    dest,
    Paint()
      ..filterQuality = FilterQuality.medium
      // Clamp rather than decal: a decal blur pulls transparency in from
      // outside the image and leaves a dark rim once premultiplied.
      ..imageFilter = ui.ImageFilter.blur(
        sigmaX: sigma,
        sigmaY: sigma,
        tileMode: TileMode.clamp,
      ),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(w, h);
  picture.dispose();
  return image;
}

/// Identifies a blur result, so it is recomputed only when it has to be.
Object blurKeyFor({
  required Size outputPx,
  required double detail,
  required ViewTransform view,
}) => Object.hash(
  outputPx.width,
  outputPx.height,
  detail,
  view.zoom,
  view.offset,
);

/// Wraps the compiled fragment program and knows how to set its uniforms.
class ValueShader {
  ValueShader(this._program);

  final ui.FragmentProgram _program;

  static Future<ValueShader> load() async =>
      ValueShader(await ui.FragmentProgram.fromAsset('shaders/askance.frag'));

  ui.FragmentShader build({
    required Size logicalSize,
    required Size devicePx,
    required int steps,
    required ValueScale scale,
    required bool skeleton,
  }) {
    final shader = _program.fragmentShader();
    shader
      ..setFloat(0, logicalSize.width)
      ..setFloat(1, logicalSize.height)
      ..setFloat(2, devicePx.width)
      ..setFloat(3, devicePx.height)
      ..setFloat(4, steps.toDouble())
      ..setFloat(5, skeleton ? 1 : 0)
      ..setFloat(6, skeletonLineWidth(devicePx.width));

    final ramp = scale.ramp(steps);
    for (var i = 0; i < 7; i++) {
      final c = ramp[math.min(i, ramp.length - 1)];
      shader
        ..setFloat(7 + i * 3, c.r)
        ..setFloat(8 + i * 3, c.g)
        ..setFloat(9 + i * 3, c.b);
    }
    return shader;
  }
}
