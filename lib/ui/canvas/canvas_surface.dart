import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart'
    show HardwareKeyboard, KeyEvent, LogicalKeyboardKey;
import 'package:flutter/widgets.dart';

import '../../engine/deferred_disposer.dart';
import 'screen_awake.dart';
import '../../engine/crop.dart';
import '../../engine/engine.dart';
import '../../engine/families.dart';
import '../../engine/lines.dart';
import '../../engine/sketch.dart';
import '../../engine/value_painter.dart';
import '../../state/canvas_session.dart';
import '../../theme.dart';
import '../widgets/controls.dart';
import '../widgets/glyphs.dart';
import 'tool_panel.dart' show probeReadout;

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
    HardwareKeyboard.instance.addHandler(_onKey);
    // A new pass is a new picture under the point being read: another zoom
    // resolves other shapes, another detail merges others.
    widget.session.blur.addListener(_readProbe);
  }

  /// Reads the pass under the dropper's point, and hands the colour back to
  /// the session to band. The pass is the value map's own, mapped the way
  /// the painter maps it, so the reading is of the shape on screen.
  Future<void> _readProbe() async {
    final session = widget.session;
    final point = session.probePoint;
    final pass = session.blur.image;
    if (!session.probing || point == null || pass == null || _size.isEmpty) {
      return;
    }
    final picture = _picture;
    final rect = passRect(
      _sourceSize,
      picture,
      _area,
      session.blur.imageView,
      session.blur.imageOutputPx,
    );
    final screen = lineToScreen(point, session.settings.crop, picture);
    if (rect.isEmpty || !rect.contains(screen)) {
      session.setProbeColour(point, null);
      return;
    }
    final colour = await readPixel(
      pass,
      Offset(
        (screen.dx - rect.left) / rect.width * pass.width,
        (screen.dy - rect.top) / rect.height * pass.height,
      ),
    );
    if (!mounted) return;
    session.setProbeColour(point, colour);
  }

  /// Shift pressed or let go with the mouse still: the line being ruled
  /// snaps, or lets go of the snap, without waiting for the mouse to move.
  bool _onKey(KeyEvent event) {
    final key = event.logicalKey;
    if ((key == LogicalKeyboardKey.shiftLeft ||
            key == LogicalKeyboardKey.shiftRight) &&
        _editing &&
        widget.session.lineStart != null &&
        _hover != null) {
      setState(() {});
    }
    return false;
  }

  /// Where the end of a line from [from], on screen, goes for the pointer at
  /// [to]: with shift held it snaps to the nearest 15 degrees.
  Offset _lineEnd(Offset from, Offset to) =>
      HardwareKeyboard.instance.isShiftPressed
      ? snappedLineEnd(from, to, _area)
      : to;

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

  /// The drawing as a gesture lining it up found it, which every update of
  /// that gesture is measured from.
  SketchOverlay? _sketchStart;

  @override
  void dispose() {
    ScreenAwake.release();
    HardwareKeyboard.instance.removeHandler(_onKey);
    widget.session.blur.removeListener(_readProbe);
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

  bool get _editing => widget.editLines && widget.session.drawingLines;

  bool get _aligning =>
      widget.session.aligningSketch && widget.session.settings.sketch != null;

  Rect get _picture => widget.session.view.destination(_sourceSize, _size);
  Rect get _area => widget.session.view.visible(_sourceSize, _size);

  void _onScaleStart(ScaleStartDetails details) {
    _gestureStart = widget.session.view;
    _focalStart = details.localFocalPoint;
    _draggingEnd = null;
    if (_aligning) {
      setState(() => _sketchStart = widget.session.settings.sketch);
      return;
    }
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
    if (_sketchStart != null) setState(() => _sketchStart = null);
    if (_draggingEnd == null) return;
    setState(() => _draggingEnd = null);
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final session = widget.session;
    if (_sketchStart case final start?) {
      // Anywhere on the picture takes hold of the drawing, not only the
      // drawing itself: shrunk small or pushed aside, it would otherwise be
      // hard to find again.
      if (_size.isEmpty) return;
      session.moveSketch(
        movedSketch(
          start,
          focalStart: _focalStart,
          focal: details.localFocalPoint,
          scale: details.scale,
          rotation: details.rotation,
          crop: session.settings.crop,
          picture: _picture,
        ),
      );
      return;
    }
    if (_draggingEnd case final dragging?) {
      // Held inside the picture as it shows: an end dragged off it would be
      // out of reach.
      final area = _area;
      final at = details.localFocalPoint + _grabOffset;
      final clamped = Offset(
        at.dx.clamp(area.left, area.right),
        at.dy.clamp(area.top, area.bottom),
      );
      final crop = session.settings.crop;
      final other = lineToScreen(
        session.settings.lines[dragging.line].end(1 - dragging.end),
        crop,
        _picture,
      );
      session.moveLineEnd(
        dragging.line,
        dragging.end,
        screenToLine(_lineEnd(other, clamped), crop, _picture),
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
    // Lining up, a tap would only hide the controls that end it.
    if (_aligning) return;
    // Probing, a tap reads the value under it, at once: the double tap's
    // zoom is still a pinch or a scroll away.
    if (widget.session.probing) {
      if (!_area.contains(position)) return;
      widget.session.placeProbe(
        screenToLine(position, widget.session.settings.crop, _picture),
      );
      _readProbe();
      return;
    }
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
    final end = switch (session.lineStart) {
      final start? => _lineEnd(lineToScreen(start, crop, picture), position),
      null => position,
    };
    // Snapped from a start since panned out of view, the end can land off
    // the picture too.
    if (!_area.inflate(0.5).contains(end)) return;
    session.placeLineEnd(screenToLine(end, crop, picture));
  }

  MouseCursor get _cursor {
    if (_aligning) {
      return _sketchStart != null
          ? SystemMouseCursors.grabbing
          : SystemMouseCursors.grab;
    }
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

  /// How far the drawing turns for each pixel the wheel reports: a notch of
  /// a mouse wheel is about six degrees.
  static const double _turnPerScrollPx = 0.001;

  void _onScroll(PointerSignalEvent event) {
    if (_aligning) {
      _onSketchScroll(event);
      return;
    }
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

  /// Lining up: the wheel scales the drawing about the pointer, and with
  /// shift held, turns it. A browser's trackpad pinch arrives as a scale.
  void _onSketchScroll(PointerSignalEvent event) {
    final session = widget.session;
    final start = session.settings.sketch;
    if (start == null || _size.isEmpty) return;
    final at = event.localPosition;
    SketchOverlay moved({double scale = 1, double rotation = 0}) => movedSketch(
      start,
      focalStart: at,
      focal: at,
      scale: scale,
      rotation: rotation,
      crop: session.settings.crop,
      picture: _picture,
    );
    switch (event) {
      case PointerScaleEvent(:final scale):
        session.moveSketch(moved(scale: scale));
      case PointerScrollEvent(:final scrollDelta):
        // Browsers and macOS turn a shifted wheel sideways on its way here,
        // so a scroll that is only sideways is a turn too, with or without
        // the key seen.
        final sideways = scrollDelta.dy == 0 && scrollDelta.dx != 0;
        if (sideways || HardwareKeyboard.instance.isShiftPressed) {
          final delta = sideways ? scrollDelta.dx : scrollDelta.dy;
          session.moveSketch(moved(rotation: delta * _turnPerScrollPx));
        } else {
          session.moveSketch(moved(scale: scrollZoomFactor(scrollDelta.dy)));
        }
    }
  }

  /// A ring on the point being read, and above it what was read there.
  List<Widget> _probeMarker(Offset point) {
    final session = widget.session;
    final at = lineToScreen(point, session.settings.crop, _picture);
    if (!_area.contains(at)) return const [];
    const ring = 22.0;
    final readout = probeReadout(session);
    return [
      Positioned(
        left: at.dx - ring / 2,
        top: at.dy - ring / 2,
        width: ring,
        height: ring,
        child: const IgnorePointer(
          child: CustomPaint(painter: _ProbeRingPainter()),
        ),
      ),
      if (readout != null)
        Positioned(
          left: at.dx,
          top: at.dy - ring,
          child: IgnorePointer(
            child: FractionalTranslation(
              translation: const Offset(-0.5, -1),
              // Turned back upright: the picture may be upside down, the
              // words never are.
              child: Transform.flip(
                flipX: session.flipped,
                flipY: session.flipped,
                child: readout,
              ),
            ),
          ),
        ),
    ];
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
            split: session.settings.split,
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
                  // A finger held still while lining up a sketch, or a press
                  // held on a line's end before dragging it, is fine-tuning,
                  // not asking to peek.
                  if (!_aligning && !_editing)
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
                    // A peek is at the photograph alone, so it lifts the
                    // drawing off too: holding the picture flicks between
                    // the two.
                    if ((session.sketchImage, session.settings.sketch) case (
                      final image?,
                      final sketch?,
                    ) when !session.peeking)
                      CustomPaint(
                        painter: _SketchPainter(
                          image: image,
                          sketch: sketch,
                          crop: session.settings.crop,
                          picture: _picture,
                          visible: _area,
                          outline: _aligning,
                        ),
                      ),
                    // Over the drawing, so the drawing's shadow shape can be
                    // held against the picture's. A peek is at the
                    // photograph alone, so it lifts this off too.
                    if (session.settings.shadowBands != null &&
                        !session.peeking)
                      ListenableBuilder(
                        listenable: session.blur,
                        builder: (context, _) => switch (session.blur.image) {
                          final pass? => CustomPaint(
                            size: Size.infinite,
                            painter: FamilyOutlinePainter(
                              shader: widget.shader,
                              source: session.image!,
                              blurred: pass,
                              blurredView: session.blur.imageView,
                              blurredSize: session.blur.imageOutputPx,
                              settings: session.settings,
                              view: session.view,
                              devicePixelRatio: dpr,
                              disposer: _disposer,
                            ),
                          ),
                          null => const SizedBox.shrink(),
                        },
                      ),
                    if (session.probing)
                      if (session.probePoint case final point?)
                        ..._probeMarker(point),
                    // Its own layer, so following the mouse repaints the
                    // handles and not the picture under them.
                    if (_editing)
                      CustomPaint(
                        painter: _LineEditPainter(
                          lines: session.settings.lines,
                          crop: session.settings.crop,
                          picture: _picture,
                          visible: _area,
                          photo: session.photoSize,
                          selected: session.selectedLine,
                          start: session.lineStart,
                          hover: switch ((session.lineStart, _hover)) {
                            (final start?, final hover?) => _lineEnd(
                              lineToScreen(
                                start,
                                session.settings.crop,
                                _picture,
                              ),
                              hover,
                            ),
                            _ => _hover,
                          },
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

/// The photograph of the drawing over the picture, ruled round its edge
/// while it is being lined up.
class _SketchPainter extends CustomPainter {
  _SketchPainter({
    required this.image,
    required this.sketch,
    required this.crop,
    required this.picture,
    required this.visible,
    required this.outline,
  });

  final ui.Image image;
  final SketchOverlay sketch;
  final Rect crop;
  final Rect picture;
  final Rect visible;
  final bool outline;

  @override
  void paint(Canvas canvas, Size size) => paintSketch(
    canvas,
    image,
    sketch,
    crop,
    picture,
    visible,
    outline: outline
        ? (Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = AskanceColors.accent)
        : null,
  );

  @override
  bool shouldRepaint(_SketchPainter old) =>
      old.image != image ||
      old.sketch != sketch ||
      old.crop != crop ||
      old.picture != picture ||
      old.visible != visible ||
      old.outline != outline;
}

/// What only shows while lines are being ruled: a handle on every end, the
/// selected line picked out with every line's length as a multiple of it,
/// and the line being ruled following the mouse from its first end.
class _LineEditPainter extends CustomPainter {
  _LineEditPainter({
    required this.lines,
    required this.crop,
    required this.picture,
    required this.visible,
    required this.photo,
    required this.selected,
    required this.start,
    required this.hover,
  });

  final List<BoardLine> lines;
  final Rect crop;
  final Rect picture;
  final Rect visible;
  final Size? photo;
  final int? selected;
  final Offset? start;
  final Offset? hover;

  static const double _handleRadius = 4.5;

  /// The gap between a length label and the middle of its line, clear of
  /// the middle tick.
  static const double _labelGap = 7;

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

    if ((selected, photo) case (final unit?, final size?)) {
      if (lengthsIn(lines, unit, size) case final lengths?) {
        for (var i = 0; i < lines.length; i++) {
          _label(
            canvas,
            lineToScreen(lines[i].a, crop, picture),
            lineToScreen(lines[i].b, crop, picture),
            i == unit ? '1' : '×${lengths[i].toStringAsFixed(2)}',
          );
        }
      }
    }

    if (start case final first?) {
      final from = lineToScreen(first, crop, picture);
      if (hover case final to?) {
        final rubber = Paint()
          ..color = AskanceColors.accent.withValues(alpha: 0.6)
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(from, to, rubber);
        paintTicks(canvas, from, to, rubber);
      }
      handle(from, filled: true);
    }
    canvas.restore();
  }

  /// [text] on a paper tab beside the middle of the line from [a] to [b], on
  /// its upper side, so it reads whichever way the line runs.
  void _label(Canvas canvas, Offset a, Offset b, String text) {
    final along = b - a;
    final length = along.distance;
    var normal = length == 0
        ? const Offset(0, -1)
        : Offset(-along.dy / length, along.dx / length);
    if (normal.dy > 0 || (normal.dy == 0 && normal.dx < 0)) normal = -normal;
    final painter = TextPainter(
      text: TextSpan(text: text, style: AskanceText.number(12)),
      textDirection: TextDirection.ltr,
    )..layout();
    final width = painter.width + 10;
    final height = painter.height + 6;
    // Out far enough that the tab's nearest edge, not its centre, is the gap
    // away: a wide tab beside a plumb line needs more room than above a
    // level one.
    final reach =
        _labelGap + (normal.dx.abs() * width + normal.dy.abs() * height) / 2;
    final centre = (a + b) / 2 + normal * reach;
    final tab = Rect.fromCenter(center: centre, width: width, height: height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(tab, const Radius.circular(AskanceRadius.small)),
      Paint()..color = AskanceColors.paper,
    );
    painter.paint(
      canvas,
      centre - Offset(painter.width / 2, painter.height / 2),
    );
    painter.dispose();
  }

  @override
  bool shouldRepaint(_LineEditPainter old) =>
      old.lines != lines ||
      old.crop != crop ||
      old.picture != picture ||
      old.visible != visible ||
      old.photo != photo ||
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

/// The dropper's mark: a ring with a dark and a light edge, so it reads on
/// any value it lands on.
class _ProbeRingPainter extends CustomPainter {
  const _ProbeRingPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 2;
    canvas.drawCircle(
      centre,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = AskanceColors.graphite,
    );
    canvas.drawCircle(
      centre,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = AskanceColors.paper,
    );
  }

  @override
  bool shouldRepaint(_ProbeRingPainter old) => false;
}
