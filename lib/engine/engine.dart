import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
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

/// How the photograph is simplified before it is quantised.
///
/// Stored by name, so the labels can be reworded without stranding studies.
enum Smoothing {
  /// A Gaussian in screen space: everything softens equally and small shapes
  /// dissolve, the way squinting loses detail. Boundaries drift as it deepens,
  /// and what it leaves behind is smooth.
  gaussian('SMOOTH'),

  /// The same blur, followed by a Kuwahara pass that turns the gradients it
  /// left back into flat patches with definite edges. The blur decides what
  /// merges; this only decides how the result reads.
  kuwahara('ROUGH');

  const Smoothing(this.label);

  final String label;
}

/// Half-width of the Kuwahara quadrant, in output pixels.
///
/// The window is a square per quadrant, so the tap count goes with the square
/// of this. It has to be wide enough to span the gradients the blur leaves or
/// there is nothing for it to snap to an edge; beyond that it only costs.
/// Measured full-screen on a Pixel 9a, this is around 50ms.
///
/// Must not exceed KUWAHARA_MAX in the shader, which bounds the loop.
const double kKuwaharaRadius = 12;

/// Narrowest the window is allowed to get, before the fade below.
///
/// Tied to the sigma alone it vanished as soon as the detail control was
/// raised, and with it every trace of what distinguishes this mode: above
/// about half way the two were indistinguishable.
const double kKuwaharaMinRadius = 5;

/// How much of the top of the detail control the floor fades away over.
///
/// At full detail nothing is being simplified — the picture is the photograph
/// quantised and no more — so there is nothing left for a style to apply to,
/// and the two modes ought to arrive at the same image. Holding the floor up
/// to the end kept ROUGH about five points short of that for no reason the
/// picture could show. The separation belongs in the middle, where the
/// simplifying happens, and should run out as the work does.
const double kKuwaharaFloorFade = 0.25;

/// Widest window the shader itself will run, in the pixels it is handed.
/// Matches KUWAHARA_MAX there; anything wider is had by shrinking the picture.
const double kKuwaharaWindow = 12;

/// Times the smoothing pass to logcat. For measuring the dial above; the
/// integration test is what actually reads it.
const bool kMeasureSmoothing = false;

/// The width the blur and line-weight constants were tuned at.
const double kReferenceWidth = 480;

/// Sigma for the "detail" control. The renderWidth term keeps shapes the same
/// size at any output resolution.
///
/// The ramp is geometric because blur reads logarithmically — twice the sigma
/// is not twice the effect. Ramped linearly, the first half of the slider did
/// nothing perceptible: the portrait below held 93% of its detail at setting 0
/// and 95% at 45.
///
/// The result stays strictly proportional to the render width. computeRegions
/// runs the whole pipeline small and relies on getting the shapes the screen
/// has, so a sigma that drifted with resolution would put the numbers on
/// regions that are not there.
double blurSigma(double detail, double renderWidth) {
  const ceiling = 16.4, floor = 0.4;
  return ceiling *
      math.pow(floor / ceiling, detail) *
      (renderWidth / kReferenceWidth);
}

/// Skeleton stroke weight, in output pixels.
double skeletonLineWidth(double renderWidth) =>
    math.max(1, (renderWidth / kReferenceWidth).roundToDouble());

/// Where the source image lands in an [output]-sized frame at 1x zoom: whole,
/// centred, with the ground showing on whichever pair of edges is short.
///
/// The handoff notes describe a cover crop aligned 32% from the top, which
/// keeps a head in frame on a portrait but hides most of a landscape. Starting
/// from the whole photograph makes no decision on the artist's behalf: zoom is
/// how you choose a passage, and it now remembers the one you chose.
Rect containRect(Size source, Size output) {
  final scale = math.min(
    output.width / source.width,
    output.height / source.height,
  );
  final w = source.width * scale;
  final h = source.height * scale;
  return Rect.fromLTWH((output.width - w) / 2, (output.height - h) / 2, w, h);
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

  /// Destination rect for the source image. Once zoomed past the point where
  /// the image covers the frame it is clamped so the ground cannot show; below
  /// that it stays centred in whatever room is left.
  Rect destination(Size source, Size output) {
    final base = containRect(source, output);
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
    final base = containRect(source, output);
    final dest = destination(source, output);
    return Offset(
      (dest.left - base.left * zoom) / output.width,
      (dest.top - base.top * zoom) / output.height,
    );
  }

  /// The part of the frame the photograph actually occupies: the whole frame
  /// once zoomed in, and less than it while the image is shown whole.
  Rect visible(Size source, Size output) =>
      destination(source, output).intersect(Offset.zero & output);

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

/// [base] zoomed just far enough that the photograph covers [output].
///
/// A study is shown whole, but a thumbnail or a backdrop is an indication of
/// a picture rather than the picture itself, and reads better filling its
/// space than sitting in it with the ground showing. The pan is kept, so a
/// card still shows roughly the passage that was last being worked on.
ViewTransform coveringView(ViewTransform base, Size source, Size output) {
  if (output.isEmpty || source.isEmpty) return base;
  final whole = containRect(source, output);
  if (whole.isEmpty) return base;
  final needed = math.max(
    output.width / whole.width,
    output.height / whole.height,
  );
  if (needed <= base.zoom) {
    return base.copyWith(offset: base.clampedOffset(source, output));
  }

  // Grown about the middle of the frame, not about its origin. A landscape
  // shown whole already meets the sides, so scaling it up from the origin
  // pins its left edge and the card ends up showing the left of the
  // photograph — rarely where anything worth looking at is.
  //
  // Deliberately not capped at maxZoom: covering is the point, and a very
  // wide photograph in a tall card can need more than a hand could pinch.
  const centre = Offset(0.5, 0.5);
  final k = needed / base.zoom;
  final candidate = ViewTransform(
    zoom: needed,
    offset: Offset(
      centre.dx - (centre.dx - base.offset.dx) * k,
      centre.dy - (centre.dy - base.offset.dy) * k,
    ),
  );
  return candidate.copyWith(offset: candidate.clampedOffset(source, output));
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
/// The Kuwahara program, compiled once on first use.
///
/// Held here rather than behind a provider because the pass that needs it is a
/// plain function, reached from the canvas, the shelf and an export alike.
Future<ui.FragmentProgram>? _kuwaharaProgram;

Future<ui.Image> renderBlurredSource({
  required ui.Image source,
  required Size outputPx,
  required double detail,
  required ViewTransform view,
  Smoothing smoothing = Smoothing.gaussian,
  double quadrantRadius = kKuwaharaRadius,
}) async {
  final sourceSize = Size(source.width.toDouble(), source.height.toDouble());
  final dest = view.destination(sourceSize, outputPx);
  // Only the part of the frame the photograph occupies. Rendering the whole
  // frame instead would leave transparent margins whenever the image is shown
  // whole, and the blur would pull that transparency inwards as a dark fringe
  // along the edges of the picture.
  final area = view.visible(sourceSize, outputPx);
  final w = math.max(1, area.width.round());
  final h = math.max(1, area.height.round());

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(
    recorder,
    Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
  );
  final sigma = blurSigma(detail, outputPx.width);


  // The blur must run over the *magnified* pixels, in output space, and this
  // has to be spelled out with a layer rather than hung off the paint.
  //
  // Given `drawImageRect` with an imageFilter on its Paint, Skia filters the
  // result in device space, which is what we want, but Impeller filters the
  // source image in the image's own space and magnifies the blurred result
  // afterwards. That makes the effective on-screen sigma scale with the zoom,
  // so zooming in returns the identical shapes at a larger size instead of
  // resolving finer ones — the single behaviour the app exists for, working on
  // web and silently doing nothing on Android, iOS and macOS.
  //
  // Rasterising into a layer first and filtering that layer is unambiguous on
  // both backends: the sigma is pinned to output pixels.
  canvas.saveLayer(
    Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    Paint()
      // Clamp rather than decal: a decal blur pulls transparency in from
      // outside the layer and leaves a dark rim once premultiplied.
      ..imageFilter = ui.ImageFilter.blur(
        sigmaX: sigma,
        sigmaY: sigma,
        tileMode: TileMode.clamp,
      ),
  );
  canvas.drawImageRect(
    source,
    Offset.zero & sourceSize,
    dest.shift(-area.topLeft),
    Paint()..filterQuality = FilterQuality.medium,
  );
  canvas.restore();

  final picture = recorder.endRecording();
  final image = await picture.toImage(w, h);
  picture.dispose();

  if (smoothing == Smoothing.gaussian) return image;

  // Both modes merge by the same blur, so the detail slider means the same
  // thing in each. All Kuwahara does is decide the character of what is left:
  // it turns the soft gradients the blur produced back into flat patches with
  // definite edges. Giving it the merging to do as well was the mistake — it
  // preserves edges by design, so widening its window coarsened the shapes
  // without ever reducing how many there were.
  // The window follows the blur it is undoing, between a floor and a ceiling,
  // and is worked out at the reference width before being scaled up like the
  // sigma is. Sized in output pixels instead it would not survive a change of
  // resolution, and computeRegions runs this whole pipeline small expecting
  // the shapes the screen has.
  final floor =
      kKuwaharaMinRadius *
      ((1 - detail) / kKuwaharaFloorFade).clamp(0.0, 1.0);
  final radius =
      blurSigma(detail, kReferenceWidth).clamp(
        // A ceiling below the floor means the ceiling: the floor is there to
        // keep the mode recognisable, not to override a deliberate limit.
        math.min(floor, quadrantRadius),
        quadrantRadius,
      ) *
      (outputPx.width / kReferenceWidth);
  final flattened = await _kuwahara(blurred: image, quadrantRadius: radius);
  image.dispose();
  return flattened;
}

/// Turns the soft gradients a blur leaves into flat patches with definite
/// edges, by replacing each pixel with the mean of whichever of four
/// overlapping quadrants around it is flattest.
///
/// Runs over the already-blurred image, so it inherits whatever the detail
/// setting merged and only decides how the result reads. The window can stay
/// narrow because it is no longer being asked to reach across features.
Future<ui.Image> _kuwahara({
  required ui.Image blurred,
  required double quadrantRadius,
}) async {
  final program = await (_kuwaharaProgram ??= ui.FragmentProgram.fromAsset(
    'shaders/kuwahara.frag',
  ));
  final clock = Stopwatch()..start();

  // The shader's loop is bounded, and the tap count goes with the square of
  // the window besides, so a window wider than that is had by shrinking the
  // picture instead. The result comes back at the reduced size and the value
  // shader magnifies it on the way in, which is no loss: this only happens at
  // the coarse settings, where nothing that small survives anyway. At most a
  // little over 2x, so none of the stair-stepping a deep reduction gives.
  final reduction = math.max(1.0, quadrantRadius / kKuwaharaWindow);
  final width = math.max(2, (blurred.width / reduction).round());
  final height = math.max(2, (blurred.height / reduction).round());
  final size = Size(width.toDouble(), height.toDouble());
  final radius = quadrantRadius / reduction;

  final ui.Image input;
  if (reduction > 1) {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder, Offset.zero & size).drawImageRect(
      blurred,
      Offset.zero & Size(blurred.width.toDouble(), blurred.height.toDouble()),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.medium,
    );
    final picture = recorder.endRecording();
    input = await picture.toImage(width, height);
    picture.dispose();
  } else {
    input = blurred;
  }

  final shader = program.fragmentShader()
    ..setFloat(0, size.width)
    ..setFloat(1, size.height)
    ..setFloat(2, radius)
    ..setImageSampler(0, input);

  final recorder = ui.PictureRecorder();
  ui.Canvas(
    recorder,
    Offset.zero & size,
  ).drawRect(Offset.zero & size, Paint()..shader = shader);
  final picture = recorder.endRecording();
  final flattened = await picture.toImage(width, height);
  picture.dispose();
  shader.dispose();
  if (!identical(input, blurred)) input.dispose();

  if (kMeasureSmoothing) {
    final taps = 4 * math.pow(radius + 1, 2) * width * height;
    debugPrint(
      '[askance] ROUGH ${width}x$height '
      'r=${radius.toStringAsFixed(1)} '
      '${(taps / 1e6).toStringAsFixed(0)}M taps ${clock.elapsedMilliseconds}ms',
    );
  }
  return flattened;
}

/// Identifies a blur result, so it is recomputed only when it has to be.
Object blurKeyFor({
  required Size outputPx,
  required double detail,
  required ViewTransform view,
  required Smoothing smoothing,
}) => Object.hash(
  outputPx.width,
  outputPx.height,
  detail,
  view.zoom,
  view.offset,
  smoothing,
);

/// Wraps the compiled fragment program and knows how to set its uniforms.
class ValueShader {
  ValueShader(this._program);

  final ui.FragmentProgram _program;

  static Future<ValueShader> load() async =>
      ValueShader(await ui.FragmentProgram.fromAsset('shaders/askance.frag'));

  ui.FragmentShader build({
    required Rect area,
    required Size devicePx,
    required int steps,
    required ValueScale scale,
    required bool skeleton,
    required double bias,
  }) {
    final shader = _program.fragmentShader();
    shader
      ..setFloat(0, area.width)
      ..setFloat(1, area.height)
      ..setFloat(2, area.left)
      ..setFloat(3, area.top)
      ..setFloat(4, devicePx.width)
      ..setFloat(5, devicePx.height)
      ..setFloat(6, steps.toDouble())
      ..setFloat(7, skeleton ? 1 : 0)
      ..setFloat(8, skeletonLineWidth(devicePx.width))
      ..setFloat(9, bias);

    final ramp = scale.ramp(steps);
    for (var i = 0; i < 7; i++) {
      final c = ramp[math.min(i, ramp.length - 1)];
      shader
        ..setFloat(10 + i * 3, c.r)
        ..setFloat(11 + i * 3, c.g)
        ..setFloat(12 + i * 3, c.b);
    }
    return shader;
  }
}
