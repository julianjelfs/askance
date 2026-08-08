import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/scheduler.dart';

import 'engine.dart';

/// Owns the blurred offscreen that the shader samples.
///
/// Kept out of `paint()` on purpose: the blur is a GPU render that has to be
/// awaited before its texture can be bound as a sampler. Callers ask for the
/// pass they want and paint with whatever is currently ready, so a detail or
/// zoom change lands on the next frame rather than blocking this one.
class BlurPass extends ChangeNotifier {
  ui.Image? _image;
  Object? _key;
  Object? _pending;
  bool _disposed = false;

  /// The most recent completed blur, or null until the first one lands.
  ui.Image? get image => _image;

  /// Whether [image] is the blur for the settings last asked for.
  bool get isCurrent => _pending == null;

  /// Asks for the blur matching these inputs. Cheap and idempotent: repeated
  /// calls with the same inputs do nothing.
  void request({
    required ui.Image source,
    required Size outputPx,
    required double detail,
    required ViewTransform view,
  }) {
    if (_disposed || outputPx.isEmpty) return;
    final key = blurKeyFor(outputPx: outputPx, detail: detail, view: view);
    if (key == _key || key == _pending) return;
    _pending = key;
    _render(source, outputPx, detail, view, key);
  }

  Future<void> _render(
    ui.Image source,
    Size outputPx,
    double detail,
    ViewTransform view,
    Object key,
  ) async {
    final ui.Image next;
    try {
      next = await renderBlurredSource(
        source: source,
        outputPx: outputPx,
        detail: detail,
        view: view,
      );
    } catch (e) {
      if (_pending == key) _pending = null;
      return;
    }
    if (_disposed) {
      next.dispose();
      return;
    }
    // A newer request overtook this one, which can happen while dragging.
    if (_pending != key) {
      next.dispose();
      return;
    }
    final previous = _image;
    _image = next;
    _key = key;
    _pending = null;
    // The outgoing image is still referenced by the shader in the last
    // recorded frame, so let that frame finish before letting it go.
    if (previous != null) _disposeAfterFrame(previous);
    notifyListeners();
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
    _image?.dispose();
    _image = null;
    super.dispose();
  }
}
