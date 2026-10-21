import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/scheduler.dart';

import 'crop.dart';
import 'engine.dart';
import 'tone.dart';

/// What a blur render needs to know.
@immutable
class _BlurRequest {
  const _BlurRequest({
    required this.source,
    required this.outputPx,
    required this.detail,
    required this.view,
    required this.smoothing,
    required this.lockDetail,
    required this.crop,
    required this.steps,
    required this.bias,
    required this.tone,
    required this.key,
  });

  final ui.Image source;
  final Size outputPx;
  final double detail;
  final ViewTransform view;
  final Smoothing smoothing;
  final bool lockDetail;
  final Rect crop;
  final int steps;
  final double bias;
  final PhotoTone tone;
  final Object key;
}

/// How long BLOCK waits, on the web, for its inputs to stop changing before
/// tracing them.
///
/// A BLOCK pass is CPU work that on the web runs on the only thread there is,
/// and can hold it for a large fraction of a second on a phone. A resize or a
/// pinch asks for a pass every frame, and a pass per frame froze the screen
/// for each one in turn. Longer than a frame, so a running gesture keeps
/// putting it off; short enough not to be noticed once it stops. Meanwhile
/// the last pass is drawn where it belongs under the current view.
/// Elsewhere the tracing runs off the UI thread and nothing is held.
const Duration kBlockSettle = Duration(milliseconds: 150);

/// Renders one pass; [renderBlurredSource] in the app, a stand-in in tests.
typedef BlurRenderer =
    Future<ui.Image> Function({
      required ui.Image source,
      required Size outputPx,
      required double detail,
      required ViewTransform view,
      Smoothing smoothing,
      bool lockDetail,
      Rect crop,
      int steps,
      double bias,
      PhotoTone tone,
    });

/// Owns the blurred offscreen that the shader samples.
///
/// Kept out of `paint()` on purpose: the blur is a GPU render that has to be
/// awaited before its texture can be bound as a sampler. Callers ask for the
/// pass they want and paint with whatever is currently ready, so a detail or
/// zoom change lands on the next frame rather than blocking this one.
class BlurPass extends ChangeNotifier {
  BlurPass({this._render = renderBlurredSource, this._holdBlock = kIsWeb});

  final BlurRenderer _render;
  final bool _holdBlock;
  ui.Image? _image;
  Object? _key;
  ViewTransform? _imageView;
  Size? _imageOutputPx;

  /// At most one render runs at a time, and only the most recent request
  /// survives the wait.
  ///
  /// A pinch changes the zoom every frame. Launching a render per frame piles
  /// up dozens of full-resolution blurs that each invalidate the one before,
  /// so the GPU saturates and almost nothing reaches the screen until the
  /// gesture stops — the zoom appears to change nothing while you are moving.
  /// Coalescing to latest-wins keeps one render in flight and drops the
  /// intermediate frames nobody would have seen anyway.
  _BlurRequest? _queued;
  bool _rendering = false;
  bool _disposed = false;
  Timer? _settle;
  Completer<void>? _settled;

  /// The most recent completed blur, or null until the first one lands.
  ui.Image? get image => _image;

  /// The view and output size [image] was rendered for, which during a
  /// gesture are not the ones on screen; the painter needs them to draw it
  /// in the right place.
  ViewTransform? get imageView => _imageView;
  Size? get imageOutputPx => _imageOutputPx;

  /// Whether [image] reflects the settings last asked for.
  bool get isCurrent => _queued == null && !_rendering && _settle == null;

  /// Completes once nothing is queued or in flight, so a caller can make sure
  /// there is a finished pass to show before putting it on screen.
  Future<void> get settled {
    if (isCurrent || _disposed) return Future<void>.value();
    return (_settled ??= Completer<void>()).future;
  }

  /// Asks for the blur matching these inputs. Cheap and idempotent: repeated
  /// calls with the same inputs do nothing.
  void request({
    required ui.Image source,
    required Size outputPx,
    required double detail,
    required ViewTransform view,
    Smoothing smoothing = Smoothing.gaussian,
    bool lockDetail = false,
    Rect crop = kWholeImage,
    int steps = 3,
    double bias = 0,
    PhotoTone tone = const PhotoTone(),
  }) {
    if (_disposed || outputPx.isEmpty) return;
    final key = blurKeyFor(
      source: source,
      outputPx: outputPx,
      detail: detail,
      view: view,
      smoothing: smoothing,
      lockDetail: lockDetail,
      crop: crop,
      steps: steps,
      bias: bias,
      tone: tone,
    );
    if (key == _key || key == _queued?.key) return;
    _queued = _BlurRequest(
      source: source,
      outputPx: outputPx,
      detail: detail,
      view: view,
      smoothing: smoothing,
      lockDetail: lockDetail,
      crop: crop,
      steps: steps,
      bias: bias,
      tone: tone,
      key: key,
    );
    if (_rendering) return;
    // The first pass is never held: there is nothing on screen to keep.
    // After that, BLOCK waits until the requests stop coming.
    if (_holdBlock && smoothing == Smoothing.block && _image != null) {
      _settle?.cancel();
      _settle = Timer(kBlockSettle, () {
        _settle = null;
        if (!_rendering) unawaited(_drain());
      });
      return;
    }
    _settle?.cancel();
    _settle = null;
    unawaited(_drain());
  }

  Future<void> _drain() async {
    _rendering = true;
    try {
      while (!_disposed && _queued != null) {
        final request = _queued!;
        _queued = null;

        final ui.Image next;
        try {
          next = await _render(
            source: request.source,
            outputPx: request.outputPx,
            detail: request.detail,
            view: request.view,
            smoothing: request.smoothing,
            lockDetail: request.lockDetail,
            crop: request.crop,
            steps: request.steps,
            bias: request.bias,
            tone: request.tone,
          );
        } catch (e) {
          // Whatever asked for this can ask again; a failed pass should not
          // wedge the queue.
          continue;
        }

        if (_disposed) {
          next.dispose();
          return;
        }

        final previous = _image;
        _image = next;
        _key = request.key;
        _imageView = request.view;
        _imageOutputPx = request.outputPx;
        // The outgoing image is still referenced by the shader in the last
        // recorded frame, so let that frame finish before letting it go.
        if (previous != null) _disposeAfterFrame(previous);
        notifyListeners();
      }
    } finally {
      _rendering = false;
      _settled?.complete();
      _settled = null;
    }
  }

  void _disposeAfterFrame(ui.Image image) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      SchedulerBinding.instance.addPostFrameCallback((_) => image.dispose());
      SchedulerBinding.instance.scheduleFrame();
    });
  }

  @override
  void dispose() {
    _settle?.cancel();
    _settle = null;
    _disposed = true;
    _queued = null;
    _settled?.complete();
    _settled = null;
    _image?.dispose();
    _image = null;
    super.dispose();
  }
}
