import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../../engine/deferred_disposer.dart';
import 'screen_awake.dart';
import '../../engine/crop.dart';
import '../../engine/engine.dart';
import '../../engine/lines.dart';
import '../../engine/value_painter.dart';
import '../../model/study.dart';
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
    this.editLines = false,
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

  /// Whether lines can be ruled here while the session is drawing them. Only
  /// the desktop stage: a mouse tells a click from a drag cleanly, where a
  /// finger on the phone's canvas is already panning, peeking and toggling
  /// the controls.
  final bool editLines;

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

  /// Where the pointer went down, which is where a drag took hold: the scale
  /// recogniser only reports where it was once it had moved far enough.
  Offset _downAt = Offset.zero;

  /// The end being dragged, and how far from the pointer it sits, so it
  /// moves with the pointer rather than jumping under it.
  ({int line, int end})? _draggingEnd;
  Offset _grabOffset = Offset.zero;

  /// The mouse over the picture while lines are being ruled.
  Offset? _hover;

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

  bool get _editing =>
      widget.editLines &&
      widget.session.drawingLines &&
      widget.session.settings.grid != GridMode.off;

  Rect get _picture => widget.session.view.destination(_sourceSize, _size);
  Rect get _area => widget.session.view.visible(_sourceSize, _size);

  void _onScaleStart(ScaleStartDetails details) {
    _gestureStart = widget.session.view;
    _focalStart = details.localFocalPoint;
    _draggingEnd = null;
    if (_editing && details.pointerCount == 1 && !_size.isEmpty) {
      final session = widget.session;
      final crop = session.settings.crop;
      final found = lineEndAt(session.settings.lines, _downAt, crop, _picture);
      if (found != null) {
        _draggingEnd = found;
        _grabOffset =
            lineToScreen(
              session.settings.lines[found.line].end(found.end),
              crop,
              _picture,
            ) -
            _downAt;
        session.selectLine(found.line);
      }
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (_draggingEnd == null) return;
    setState(() => _draggingEnd = null);
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final session = widget.session;
    if (_draggingEnd case final dragging?) {
      // Held inside the picture as it shows: an end dragged off it would be
      // out of reach.
      final area = _area;
      final at = details.localFocalPoint + _grabOffset;
      final clamped = Offset(
        at.dx.clamp(area.left, area.right),
        at.dy.clamp(area.top, area.bottom),
      );
      session.moveLineEnd(
        dragging.line,
        dragging.end,
        screenToLine(clamped, session.settings.crop, _picture),
      );
      return;
    }
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
    if (_editing) {
      _onLineClick(position);
      return;
    }
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

  /// A click while ruling lines. Acts at once, with no wait for a second
  /// click: ruling takes the double click's zoom, and the scroll wheel still
  /// zooms.
  void _onLineClick(Offset position) {
    final session = widget.session;
    final crop = session.settings.crop;
    final picture = _picture;
    if (session.lineStart == null) {
      final lines = session.settings.lines;
      final hit =
          lineEndAt(lines, position, crop, picture)?.line ??
          lineAt(lines, position, crop, picture);
      if (hit != null) {
        session.selectLine(hit == session.selectedLine ? null : hit);
        return;
      }
      // A click away from a selected line lets go of it, rather than also
      // starting a line nobody meant to.
      if (session.selectedLine != null) {
        session.selectLine(null);
        return;
      }
    }
    if (!_area.contains(position)) return;
    session.placeLineEnd(screenToLine(position, crop, picture));
  }

  MouseCursor get _cursor {
    if (!_editing) return MouseCursor.defer;
    if (_draggingEnd != null) return SystemMouseCursors.grabbing;
    final hover = _hover;
    if (hover == null || _size.isEmpty) return SystemMouseCursors.precise;
    final session = widget.session;
    final crop = session.settings.crop;
    if (session.lineStart == null) {
      final lines = session.settings.lines;
      if (lineEndAt(lines, hover, crop, _picture) != null) {
        return SystemMouseCursors.grab;
      }
      if (lineAt(lines, hover, crop, _picture) != null) {
        return SystemMouseCursors.click;
      }
    }
    return SystemMouseCursors.precise;
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
            contrast: session.settings.contrast,
          );
          if (session.settings.photoNeedsOwnPass) {
            session.photoBlur.request(
              source: session.image!,
              outputPx: Size(_size.width * dpr, _size.height * dpr),
              detail: session.settings.detail,
              view: session.view,
              lockDetail: session.settings.lockDetail,
              crop: session.settings.crop,
            );
          }
        }

        // Flipped outside the gestures, so every position they report is
        // already in the picture's own, unflipped space: a pinch or a double
        // tap still zooms on the passage under the fingers.
        return Transform.flip(
          flipX: session.flipped,
          flipY: session.flipped,
          child: Listener(
            onPointerSignal: _onScroll,
            onPointerDown: (event) => _downAt = event.localPosition,
            child: MouseRegion(
              cursor: _cursor,
              onHover: (event) {
                if (_editing) setState(() => _hover = event.localPosition);
              },
              onExit: (_) {
                if (_hover != null) setState(() => _hover = null);
              },
              child: RawGestureDetector(
                behavior: HitTestBehavior.opaque,
                gestures: {
                  // Tap and double tap are timed here rather than left to a
                  // DoubleTapGestureRecognizer, because the scale recognizer wins
                  // the arena first and the double tap never fires. The single tap
                  // is held for the design's 300ms double-tap window so a second
                  // tap can claim it.
                  TapGestureRecognizer:
                      GestureRecognizerFactoryWithHandlers<
                        TapGestureRecognizer
                      >(
                        TapGestureRecognizer.new,
                        (instance) => instance.onTapUp = _onTapUp,
                      ),
                  LongPressGestureRecognizer: peekRecognizer(
                    onStart: () => session.setPeeking(true),
                    onEnd: () => session.setPeeking(false),
                  ),
                  ScaleGestureRecognizer:
                      GestureRecognizerFactoryWithHandlers<
                        ScaleGestureRecognizer
                      >(
                        ScaleGestureRecognizer.new,
                        (instance) => instance
                          ..onStart = _onScaleStart
                          ..onUpdate = _onScaleUpdate
                          ..onEnd = _onScaleEnd,
                      ),
                },
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    RepaintBoundary(
                      child: ListenableBuilder(
                        listenable: Listenable.merge([
                          session.blur,
                          session.photoBlur,
                        ]),
                        builder: (context, _) => CustomPaint(
                          size: Size.infinite,
                          painter: ValuePainter(
                            shader: widget.shader,
                            source: session.image!,
                            blurred: session.blur.image,
                            blurredView: session.blur.imageView,
                            blurredSize: session.blur.imageOutputPx,
                            photoBlurred: session.photoBlur.image,
                            photoBlurredView: session.photoBlur.imageView,
                            photoBlurredSize: session.photoBlur.imageOutputPx,
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
                    // Its own layer, so following the mouse repaints the
                    // handles and not the picture under them.
                    if (_editing)
                      CustomPaint(
                        painter: _LineEditPainter(
                          lines: session.settings.lines,
                          crop: session.settings.crop,
                          picture: _picture,
                          visible: _area,
                          selected: session.selectedLine,
                          start: session.lineStart,
                          hover: _hover,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// What only shows while lines are being ruled: a handle on every end, the
/// selected line picked out, and the line being ruled following the mouse
/// from its first end.
class _LineEditPainter extends CustomPainter {
  _LineEditPainter({
    required this.lines,
    required this.crop,
    required this.picture,
    required this.visible,
    required this.selected,
    required this.start,
    required this.hover,
  });

  final List<BoardLine> lines;
  final Rect crop;
  final Rect picture;
  final Rect visible;
  final int? selected;
  final Offset? start;
  final Offset? hover;

  static const double _handleRadius = 4.5;

  @override
  void paint(Canvas canvas, Size size) {
    if (visible.isEmpty || picture.isEmpty) return;
    canvas.save();
    canvas.clipRect(visible);

    final accent = Paint()..color = AskanceColors.accent;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = AskanceColors.accent;
    final paper = Paint()..color = AskanceColors.paper;

    if (selected case final index? when index < lines.length) {
      canvas.drawLine(
        lineToScreen(lines[index].a, crop, picture),
        lineToScreen(lines[index].b, crop, picture),
        Paint()
          ..color = AskanceColors.accent
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round,
      );
    }

    void handle(Offset at, {required bool filled}) {
      canvas.drawCircle(at, _handleRadius, filled ? accent : paper);
      canvas.drawCircle(at, _handleRadius, ring);
    }

    for (var i = 0; i < lines.length; i++) {
      handle(lineToScreen(lines[i].a, crop, picture), filled: i == selected);
      handle(lineToScreen(lines[i].b, crop, picture), filled: i == selected);
    }

    if (start case final first?) {
      final from = lineToScreen(first, crop, picture);
      if (hover case final to?) {
        canvas.drawLine(
          from,
          to,
          Paint()
            ..color = AskanceColors.accent.withValues(alpha: 0.6)
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round,
        );
      }
      handle(from, filled: true);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LineEditPainter old) =>
      old.lines != lines ||
      old.crop != crop ||
      old.picture != picture ||
      old.visible != visible ||
      old.selected != selected ||
      old.start != start ||
      old.hover != hover;
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
