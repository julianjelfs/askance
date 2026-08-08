/// Holds resources alive for a couple of paints after they stop being used.
///
/// A `ui.FragmentShader` must outlive the *rasterisation* of the frame that
/// drew with it, not merely the paint call that recorded it. Disposing one
/// inside `paint()` renders as a solid fill of nothing on web.
class DeferredDisposer {
  final List<void Function()> _thisFrame = [];
  final List<void Function()> _lastFrame = [];

  void retire(void Function() dispose) => _thisFrame.add(dispose);

  /// Call once at the start of each paint. Releases anything retired two
  /// paints ago, by which point its frame is long rasterised.
  void tick() {
    for (final dispose in _lastFrame) {
      dispose();
    }
    _lastFrame
      ..clear()
      ..addAll(_thisFrame);
    _thisFrame.clear();
  }

  void disposeAll() {
    for (final dispose in [..._lastFrame, ..._thisFrame]) {
      dispose();
    }
    _lastFrame.clear();
    _thisFrame.clear();
  }
}
