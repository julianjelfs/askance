import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../../engine/blur_pass.dart';
import '../../engine/deferred_disposer.dart';
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
  });

  final CanvasSession session;
  final ValueShader shader;
  final VoidCallback? onTap;
  final bool allowChromeToggle;
  final bool drawGrid;

  @override
  State<CanvasSurface> createState() => _CanvasSurfaceState();
}

class _CanvasSurfaceState extends State<CanvasSurface> {
  final _disposer = DeferredDisposer();
  final _blur = BlurPass();

  ViewTransform _gestureStart = const ViewTransform();
  Offset _focalStart = Offset.zero;
  Size _size = Size.zero;

  @override
  void dispose() {
    _disposer.disposeAll();
    _blur.dispose();
    super.dispose();
  }

  Size get _sourceSize {
    final image = widget.session.image!;
    return Size(image.width.toDouble(), image.height.toDouble());
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
    final k = zoom / _gestureStart.zoom;
    // Keep the point under the fingers fixed, then follow the pan.
    final offset =
        Offset(
          _focalStart.dx - (_focalStart.dx - _gestureStart.offset.dx) * k,
          _focalStart.dy - (_focalStart.dy - _gestureStart.offset.dy) * k,
        ) +
        (details.localFocalPoint - _focalStart);
    final candidate = ViewTransform(zoom: zoom, offset: offset);
    session.setView(
      candidate.copyWith(offset: candidate.clampedOffset(_sourceSize, _size)),
    );
  }

  void _onScroll(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final session = widget.session;
    final factor = event.scrollDelta.dy > 0 ? 0.9 : 1.1;
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
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) session.setViewport(_size, dpr);
        });

        // Asking every build is cheap: the pass only re-renders when the
        // detail, zoom or output size actually changes.
        _blur.request(
          source: session.image!,
          outputPx: Size(_size.width * dpr, _size.height * dpr),
          detail: session.settings.detail,
          view: session.view,
        );

        return Listener(
          onPointerSignal: _onScroll,
          child: RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            gestures: {
              TapGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                    TapGestureRecognizer.new,
                    (instance) => instance.onTap = () {
                      widget.onTap?.call();
                      if (widget.allowChromeToggle) session.toggleChrome();
                    },
                  ),
              DoubleTapGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                    DoubleTapGestureRecognizer
                  >(
                    DoubleTapGestureRecognizer.new,
                    (instance) =>
                        instance.onDoubleTapDown = (details) =>
                            session.cycleZoom(details.localPosition),
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
                listenable: _blur,
                builder: (context, _) => CustomPaint(
                  size: Size.infinite,
                  painter: ValuePainter(
                    shader: widget.shader,
                    source: session.image!,
                    blurred: _blur.image,
                    settings: session.settings,
                    view: session.view,
                    devicePixelRatio: dpr,
                    peeking: session.peeking,
                    splitPosition: session.splitPosition,
                    regions: session.regions,
                    disposer: _disposer,
                    drawGrid: widget.drawGrid,
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
/// 2px rule and a 32x32 grip. The handle travels the full width, edge to edge.
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
          children: [
            Positioned(
              left: (session.splitPosition * width - target / 2).clamp(
                0.0,
                width - target,
              ),
              top: 0,
              bottom: 0,
              width: target,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: (d) {
                  final box = context.findRenderObject() as RenderBox?;
                  if (box == null) return;
                  final local = box.globalToLocal(d.globalPosition);
                  session.setSplitPosition(local.dx / width);
                },
                onHorizontalDragEnd: (_) => session.setSplitPosition(
                  session.splitPosition,
                  settle: true,
                ),
                child: Center(
                  child: Container(
                    width: 32 * s,
                    height: 32 * s,
                    color: AskanceColors.accent,
                    alignment: Alignment.center,
                    child: GlyphIcon(
                      Glyph.splitGrip,
                      size: 11 * s,
                      color: AskanceColors.ground,
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
