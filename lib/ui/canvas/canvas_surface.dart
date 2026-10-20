import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../../engine/deferred_disposer.dart';
import 'screen_awake.dart';
import '../../engine/crop.dart';
import '../../engine/engine.dart';
import '../../engine/value_painter.dart';
import '../../state/canvas_session.dart';
import '../../theme.dart';
import '../widgets/controls.dart';
import '../widgets/glyphs.dart';

/// The image itself, plus every gesture that acts on it.
///
/// Zoom is fed to the engine rather than applied as a widget transform: the
/// blur runs in screen space and the band thresholds are absolute, so
/// re-running the pipeline on the visible crop resolves finer shapes without
/// moving a single value.
class CanvasSurface extends StatefulWidget {
  const CanvasSurface({
    super.key,
    required this.session,
    required this.shader,
    this.onTap,
    this.allowChromeToggle = true,
    this.drawGrid = true,
    this.freezeBlur = false,
  });

  final CanvasSession session;
  final ValueShader shader;
  final VoidCallback? onTap;
  final bool allowChromeToggle;
  final bool drawGrid;

  /// Held still while the open transition runs. Re-rendering at each
  /// intermediate size would re-quantise the picture as it grew — the blur
  /// sigma scales with frame width — so the shapes would visibly re-form
  /// instead of the whole thing simply getting bigger.
  final bool freezeBlur;

  @override
  State<CanvasSurface> createState() => _CanvasSurfaceState();
}

class _CanvasSurfaceState extends State<CanvasSurface> {
  final _disposer = DeferredDisposer();

  @override
  void initState() {
    super.initState();
    ScreenAwake.acquire();
  }

  ViewTransform _gestureStart = const ViewTransform();
  Offset _focalStart = Offset.zero;
  Size _size = Size.zero;

  Timer? _pendingTap;
  Offset _lastTapPosition = Offset.zero;

  @override
  void dispose() {
    ScreenAwake.release();
    _pendingTap?.cancel();
    _disposer.disposeAll();
    super.dispose();
  }

  Size get _sourceSize {
    final image = widget.session.image!;
    return croppedSize(
      Size(image.width.toDouble(), image.height.toDouble()),
      widget.session.settings.crop,
    );
  }

  void _onScaleStart(ScaleStartDetails details) {
    _gestureStart = widget.session.view;
    _focalStart = details.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final session = widget.session;
    final zoom = (_gestureStart.zoom * details.scale).clamp(
      ViewTransform.minZoom,
      ViewTransform.maxZoom,
    );
    if (_size.isEmpty) return;
    final k = zoom / _gestureStart.zoom;
    // Work in pixels for the gesture, then store the result as a fraction of
    // the picture so every resolution, and every shape of room, reads the
    // same crop.
    final base = containRect(_sourceSize, _size);
    final startPx =
        base.topLeft +
        Offset(
          _gestureStart.offset.dx * base.width,
          _gestureStart.offset.dy * base.height,
        );
    // Keep the point under the fingers fixed, then follow the pan.
    final pannedPx =
        Offset(
          _focalStart.dx - (_focalStart.dx - startPx.dx) * k,
          _focalStart.dy - (_focalStart.dy - startPx.dy) * k,
        ) +
        (details.localFocalPoint - _focalStart) -
        base.topLeft;
    final candidate = _gestureStart.copyWith(
      zoom: zoom,
      offset: Offset(pannedPx.dx / base.width, pannedPx.dy / base.height),
    );
    session.setView(
      candidate.copyWith(offset: candidate.clampedOffset(_sourceSize, _size)),
    );
  }

  void _onTapUp(TapUpDetails details) {
    final position = details.localPosition;
    final pending = _pendingTap;
    if (pending != null && (position - _lastTapPosition).distance < 32) {
      pending.cancel();
      _pendingTap = null;
      widget.session.cycleZoom(position);
      return;
    }
    _lastTapPosition = position;
    _pendingTap?.cancel();
    _pendingTap = Timer(AskanceMotion.doubleTapWindow, () {
      _pendingTap = null;
      widget.onTap?.call();
      if (widget.allowChromeToggle) widget.session.tapPicture();
    });
  }

  void _onScroll(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final session = widget.session;
    final factor = scrollZoomFactor(event.scrollDelta.dy);
    session.setView(
      session.view.zoomedAt(
        event.localPosition,
        session.view.zoom * factor,
        _sourceSize,
        _size,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final dpr = MediaQuery.devicePixelRatioOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        _size = constraints.biggest;
        if (!widget.freezeBlur) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) session.setViewport(_size, dpr);
          });

          // Asking every build is cheap: the pass only re-renders when the
          // detail, zoom or output size actually changes.
          session.blur.request(
            source: session.image!,
            outputPx: Size(_size.width * dpr, _size.height * dpr),
            detail: session.settings.detail,
            view: session.view,
            smoothing: session.settings.smoothing,
            lockDetail: session.settings.lockDetail,
            crop: session.settings.crop,
            steps: session.settings.steps,
            bias: session.settings.bias,
          );
        }

        return Listener(
          onPointerSignal: _onScroll,
          child: RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            gestures: {
              // Tap and double tap are timed here rather than left to a
              // DoubleTapGestureRecognizer, because the scale recognizer wins
              // the arena first and the double tap never fires. The single tap
              // is held for the design's 300ms double-tap window so a second
              // tap can claim it.
              TapGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                    TapGestureRecognizer.new,
                    (instance) => instance.onTapUp = _onTapUp,
                  ),
              LongPressGestureRecognizer: peekRecognizer(
                onStart: () => session.setPeeking(true),
                onEnd: () => session.setPeeking(false),
              ),
              ScaleGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<ScaleGestureRecognizer>(
                    ScaleGestureRecognizer.new,
                    (instance) => instance
                      ..onStart = _onScaleStart
                      ..onUpdate = _onScaleUpdate,
                  ),
            },
            child: RepaintBoundary(
              child: ListenableBuilder(
                listenable: session.blur,
                builder: (context, _) => CustomPaint(
                  size: Size.infinite,
                  painter: ValuePainter(
                    shader: widget.shader,
                    source: session.image!,
                    blurred: session.blur.image,
                    blurredView: session.blur.imageView,
                    blurredSize: session.blur.imageOutputPx,
                    settings: session.settings,
                    view: session.view,
                    devicePixelRatio: dpr,
                    peeking: session.peeking,
                    splitPosition: session.splitPosition,
                    disposer: _disposer,
                    drawGrid: widget.drawGrid,
                    isolatedBand: session.isolatedBand,
                    outline: true,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A 44px-wide invisible drag target centred on the split boundary, carrying a
/// round grip on the rule. The handle travels the full width, edge to edge.
class SplitHandle extends StatelessWidget {
  const SplitHandle({super.key, required this.session});

  final CanvasSession session;

  @override
  Widget build(BuildContext context) {
    final s = DesignScale.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final target = 44 * s;
        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              // Deliberately not clamped into the frame: the grip stays
              // centred on the boundary the whole way and clips at the edges.
              // Holding it back so it stays wholly visible would leave it
              // trailing the rule by half its width at either extreme.
              left: session.splitPosition * width - target / 2,
              top: 0,
              bottom: 0,
              width: target,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                // Follows the pointer by delta, so it needs no mapping back
                // into the surface's coordinate space.
                onHorizontalDragUpdate: (d) => session.setSplitPosition(
                  session.splitPosition + d.delta.dx / width,
                ),
                onHorizontalDragEnd: (_) => session.setSplitPosition(
                  session.splitPosition,
                  settle: true,
                ),
                child: Center(
                  child: Container(
                    width: 36 * s,
                    height: 36 * s,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: AskanceColors.accent,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: Color(0x40000000), blurRadius: 6),
                      ],
                    ),
                    child: GlyphIcon(
                      Glyph.splitGrip,
                      size: 11 * s,
                      color: AskanceColors.paper,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
