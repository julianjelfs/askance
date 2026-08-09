import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/scheduler.dart';

import 'engine.dart';

/// What a blur render needs to know.
@immutable
class _BlurRequest {
  const _BlurRequest({
    required this.source,
    required this.outputPx,
    required this.detail,
    required this.view,
    required this.smoothing,
    required this.key,
  });

  final ui.Image source;
  final Size outputPx;
  final double detail;
  final ViewTransform view;
  final Smoothing smoothing;
  final Object key;
}

/// Owns the blurred offscreen that the shader samples.
///
/// Kept out of `paint()` on purpose: the blur is a GPU render that has to be
/// awaited before its texture can be bound as a sampler. Callers ask for the
/// pass they want and paint with whatever is currently ready, so a detail or
/// zoom change lands on the next frame rather than blocking this one.
class BlurPass extends ChangeNotifier {
  ui.Image? _image;
  Object? _key;

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
  Completer<void>? _settled;

  /// The most recent completed blur, or null until the first one lands.
  ui.Image? get image => _image;

  /// Whether [image] reflects the settings last asked for.
  bool get isCurrent => _queued == null && !_rendering;

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
  }) {
    if (_disposed || outputPx.isEmpty) return;
    final key = blurKeyFor(
      outputPx: outputPx,
      detail: detail,
      view: view,
      smoothing: smoothing,
    );
    if (key == _key || key == _queued?.key) return;
    _queued = _BlurRequest(
      source: source,
      outputPx: outputPx,
      detail: detail,
      view: view,
      smoothing: smoothing,
      key: key,
    );
    if (!_rendering) unawaited(_drain());
  }

  Future<void> _drain() async {
    _rendering = true;
    try {
      while (!_disposed && _queued != null) {
        final request = _queued!;
        _queued = null;

        final ui.Image next;
        try {
          next = await renderBlurredSource(
            source: request.source,
            outputPx: request.outputPx,
            detail: request.detail,
            view: request.view,
            smoothing: request.smoothing,
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
    _disposed = true;
    _queued = null;
    _settled?.complete();
    _settled = null;
    _image?.dispose();
    _image = null;
    super.dispose();
  }
}
