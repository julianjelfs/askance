import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart'
    show HardwareKeyboard, KeyEvent, LogicalKeyboardKey;
import 'package:flutter/widgets.dart';

import '../../engine/boxes.dart';
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

  /// Whether guides, lines and boxes, can be drawn here while the session is
  /// drawing them. Only
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

  /// Shift pressed or let go with the mouse still: the guide being drawn
  /// snaps, or lets go of the snap, without waiting for the mouse to move.
  bool _onKey(KeyEvent event) {
    final key = event.logicalKey;
    if ((key == LogicalKeyboardKey.shiftLeft ||
            key == LogicalKeyboardKey.shiftRight) &&
        _editing &&
        _draft != null) {
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

  /// The box being resized from a corner, and the corner across from it,
  /// on the photograph, which stays put. [_grabOffset] keeps the corner
  /// under the pointer where it was taken.
  ({int box, Offset anchor})? _resizing;

  /// The box being moved by a side, as it was when taken hold of.
  ({int box, BoardBox start})? _moving;

  /// The line being moved whole, as it was when taken hold of.
  ({int line, BoardLine start})? _movingLine;

  /// A new guide being dragged out, on screen: where the drag began and
  /// where the pointer is now, held inside the picture. Where the far end
  /// lands is [_draftEnd], which snaps with shift.
  ({GuideShape shape, Offset anchor, Offset pointer})? _draft;

  /// The mouse over the picture while guides are being drawn, for the
  /// cursor.
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
    _resizing = null;
    _moving = null;
    _movingLine = null;
    _draft = null;
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
        return;
      }
      final boxes = session.settings.boxes;
      if (boxCornerAt(boxes, _downAt, crop, _picture) case final corner?) {
        final box = boxes[corner.box];
        _resizing = (box: corner.box, anchor: box.opposite(corner.corner));
        _grabOffset =
            lineToScreen(box.corners[corner.corner], crop, _picture) - _downAt;
        session.selectBox(corner.box);
        return;
      }
      final lines = session.settings.lines;
      if (lineAt(lines, _downAt, crop, _picture) case final index?) {
        _movingLine = (line: index, start: lines[index]);
        session.selectLine(index);
        return;
      }
      if (boxEdgeAt(boxes, _downAt, crop, _picture) case final index?) {
        _moving = (box: index, start: boxes[index]);
        session.selectBox(index);
        return;
      }
      if (_area.contains(_downAt)) {
        setState(
          () => _draft = (
            shape: session.guideShape,
            anchor: _downAt,
            pointer: _downAt,
          ),
        );
      }
    }
  }

  /// Where the far end of [draft] lands on screen: for a line, snapped to
  /// 15 degrees with shift held; for a box, square.
  Offset _draftEnd(({GuideShape shape, Offset anchor, Offset pointer}) draft) =>
      switch (draft.shape) {
        GuideShape.line => _lineEnd(draft.anchor, draft.pointer),
        GuideShape.box => _boxCorner(draft.anchor, draft.pointer),
      };

  void _onScaleEnd(ScaleEndDetails details) {
    if (_sketchStart != null) setState(() => _sketchStart = null);
    if (_draft case final draft?) {
      final session = widget.session;
      final crop = session.settings.crop;
      final end = _draftEnd(draft);
      final a = screenToLine(draft.anchor, crop, _picture);
      final b = screenToLine(end, crop, _picture);
      switch (draft.shape) {
        case GuideShape.line:
          if ((end - draft.anchor).distance >= kMinGuideDrag) {
            session.addLine(BoardLine(a, b));
          }
        case GuideShape.box:
          final r = Rect.fromPoints(draft.anchor, end);
          if (r.width >= kMinGuideDrag && r.height >= kMinGuideDrag) {
            session.addBox(BoardBox.spanning(a, b));
          }
      }
    }
    if (_draggingEnd == null &&
        _resizing == null &&
        _moving == null &&
        _movingLine == null &&
        _draft == null) {
      return;
    }
    setState(() {
      _draggingEnd = null;
      _resizing = null;
      _moving = null;
      _movingLine = null;
      _draft = null;
    });
  }

  /// [at] held inside the picture as it shows: a corner or an end dragged
  /// off it would be out of reach.
  Offset _clampToArea(Offset at) {
    final area = _area;
    return Offset(
      at.dx.clamp(area.left, area.right),
      at.dy.clamp(area.top, area.bottom),
    );
  }

  /// Where the dragged corner of a box from [anchor], on screen, goes for
  /// the pointer at [to]: with shift held the box is square.
  Offset _boxCorner(Offset anchor, Offset to) =>
      HardwareKeyboard.instance.isShiftPressed
      ? squaredBoxCorner(anchor, to, _area)
      : to;

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
    if (_draft case final draft?) {
      setState(
        () => _draft = (
          shape: draft.shape,
          anchor: draft.anchor,
          pointer: _clampToArea(details.localFocalPoint),
        ),
      );
      return;
    }
    if (_resizing case final resizing?) {
      final crop = session.settings.crop;
      final anchor = lineToScreen(resizing.anchor, crop, _picture);
      final corner = _boxCorner(
        anchor,
        _clampToArea(details.localFocalPoint + _grabOffset),
      );
      session.setBox(
        resizing.box,
        BoardBox.spanning(
          resizing.anchor,
          screenToLine(corner, crop, _picture),
        ),
      );
      return;
    }
    if (_moving case final moving?) {
      final crop = session.settings.crop;
      final by =
          screenToLine(details.localFocalPoint, crop, _picture) -
          screenToLine(_downAt, crop, _picture);
      session.setBox(moving.box, moving.start.movedBy(by));
      return;
    }
    if (_movingLine case final moving?) {
      final crop = session.settings.crop;
      final by =
          screenToLine(details.localFocalPoint, crop, _picture) -
          screenToLine(_downAt, crop, _picture);
      session.setLine(moving.line, moving.start.movedBy(by));
      return;
    }
    if (_draggingEnd case final dragging?) {
      final clamped = _clampToArea(details.localFocalPoint + _grabOffset);
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
      _onGuideClick(position);
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

  /// A click while drawing guides. Acts at once, with no wait for a second
  /// click: drawing takes the double click's zoom, and the scroll wheel
  /// still zooms. Guides are drawn by dragging, so a click only selects the
  /// line or box under it, or lets go of the selection.
  void _onGuideClick(Offset position) {
    final session = widget.session;
    final crop = session.settings.crop;
    final picture = _picture;
    final lines = session.settings.lines;
    final hit =
        lineEndAt(lines, position, crop, picture)?.line ??
        lineAt(lines, position, crop, picture);
    if (hit != null) {
      session.selectLine(hit == session.selectedLine ? null : hit);
      return;
    }
    final boxes = session.settings.boxes;
    final box =
        boxCornerAt(boxes, position, crop, picture)?.box ??
        boxEdgeAt(boxes, position, crop, picture);
    if (box != null) {
      session.selectBox(box == session.selectedBox ? null : box);
      return;
    }
    session.deselectGuide();
  }

  MouseCursor get _cursor {
    if (_aligning) {
      return _sketchStart != null
          ? SystemMouseCursors.grabbing
          : SystemMouseCursors.grab;
    }
    if (!_editing) return MouseCursor.defer;
    if (_draggingEnd != null || _moving != null || _movingLine != null) {
      return SystemMouseCursors.grabbing;
    }
    if (_resizing != null || _draft != null) return SystemMouseCursors.precise;
    final hover = _hover;
    if (hover == null || _size.isEmpty) return SystemMouseCursors.precise;
    final session = widget.session;
    final crop = session.settings.crop;
    final lines = session.settings.lines;
    if (lineEndAt(lines, hover, crop, _picture) != null) {
      return SystemMouseCursors.grab;
    }
    final boxes = session.settings.boxes;
    if (boxCornerAt(boxes, hover, crop, _picture) case final corner?) {
      return corner.corner.isEven
          ? SystemMouseCursors.resizeUpLeftDownRight
          : SystemMouseCursors.resizeUpRightDownLeft;
    }
    if (lineAt(lines, hover, crop, _picture) != null ||
        boxEdgeAt(boxes, hover, crop, _picture) != null) {
      return SystemMouseCursors.move;
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
                    // Every box says its proportions, drawing or not: they
                    // are what it is for. On screen only; the export carries
                    // the boxes without the words.
                    if (widget.drawGrid &&
                        session.settings.boxes.isNotEmpty &&
                        session.photoSize != null)
                      IgnorePointer(
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: _BoxLabelPainter(
                            boxes: session.settings.boxes,
                            crop: session.settings.crop,
                            picture: _picture,
                            visible: _area,
                            photo: session.photoSize!,
                            flipped: session.flipped,
                          ),
                        ),
                      ),
                    // Its own layer, so following the mouse repaints the
                    // handles and not the picture under them.
                    if (_editing)
                      CustomPaint(
                        painter: _LineEditPainter(
                          lines: session.settings.lines,
                          boxes: session.settings.boxes,
                          crop: session.settings.crop,
                          picture: _picture,
                          visible: _area,
                          photo: session.photoSize,
                          flipped: session.flipped,
                          selected: session.selectedLine,
                          selectedBox: session.selectedBox,
                          draftLine: switch (_draft) {
                            final d? when d.shape == GuideShape.line => (
                              d.anchor,
                              _draftEnd(d),
                            ),
                            _ => null,
                          },
                          draftBox: switch (_draft) {
                            final d? when d.shape == GuideShape.box =>
                              Rect.fromPoints(d.anchor, _draftEnd(d)),
                            _ => null,
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

/// What only shows while guides are being drawn: a handle on every end and
/// corner, the selected line picked out with every other line's length as a
/// multiple of it, the selected box picked out, and the line or box being
/// dragged out.
class _LineEditPainter extends CustomPainter {
  _LineEditPainter({
    required this.lines,
    required this.boxes,
    required this.crop,
    required this.picture,
    required this.visible,
    required this.photo,
    required this.flipped,
    required this.selected,
    required this.selectedBox,
    required this.draftLine,
    required this.draftBox,
  });

  final List<BoardLine> lines;
  final List<BoardBox> boxes;
  final Rect crop;
  final Rect picture;
  final Rect visible;
  final Size? photo;
  final bool flipped;
  final int? selected;
  final int? selectedBox;

  /// The line being dragged out, on screen, from where the drag began.
  final (Offset, Offset)? draftLine;

  /// The box being dragged out, on screen.
  final Rect? draftBox;

  static const double _handleRadius = 4.5;

  /// The gap between a length label and the middle of its line, clear of
  /// the middle tick.
  static const double _labelGap = 6;

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

    if (selectedBox case final index? when index < boxes.length) {
      canvas.drawRect(
        boxToScreen(boxes[index], crop, picture),
        Paint()
          ..style = PaintingStyle.stroke
          ..color = AskanceColors.accent
          ..strokeWidth = 4,
      );
    }

    for (var i = 0; i < lines.length; i++) {
      handle(lineToScreen(lines[i].a, crop, picture), filled: i == selected);
      handle(lineToScreen(lines[i].b, crop, picture), filled: i == selected);
    }
    for (var i = 0; i < boxes.length; i++) {
      for (final corner in boxes[i].corners) {
        handle(lineToScreen(corner, crop, picture), filled: i == selectedBox);
      }
    }

    if ((draftBox, photo) case (final r?, final size?)) {
      final rubber = Paint()
        ..color = AskanceColors.accent.withValues(alpha: 0.6)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      paintBoxOutline(
        canvas,
        r,
        Paint()
          ..color = rubber.color
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
        rubber,
      );
      final box = BoardBox.spanning(
        screenToLine(r.topLeft, crop, picture),
        screenToLine(r.bottomRight, crop, picture),
      );
      if (boxRatioLabel(box, size) case final text?) {
        paintBoxLabel(canvas, r, text, visible, flipped: flipped);
      }
    }

    if ((selected, photo) case (final unit?, final size?)) {
      if (lengthsIn(lines, unit, size) case final lengths?) {
        for (var i = 0; i < lines.length; i++) {
          // The unit is 1 by definition, and already picked out.
          if (i == unit) continue;
          _label(
            canvas,
            lineToScreen(lines[i].a, crop, picture),
            lineToScreen(lines[i].b, crop, picture),
            '×${lengths[i].toStringAsFixed(2)}',
          );
        }
      }
    }

    if (draftLine case (final from, final to)) {
      final rubber = Paint()
        ..color = AskanceColors.accent.withValues(alpha: 0.6)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(from, to, rubber);
      paintTicks(canvas, from, to, rubber);
      handle(from, filled: true);
    }
    canvas.restore();
  }

  /// [text] on a paper tab along the line from [a] to [b], beside its
  /// middle and turned to run with it, so the label's angle says which line
  /// it belongs to. Never upside down: a line steeper than plumb reads the
  /// other way, and a plumb one reads upwards, like a book's spine.
  void _label(Canvas canvas, Offset a, Offset b, String text) {
    final along = b - a;
    var angle = along == Offset.zero ? 0.0 : along.direction;
    if (angle >= math.pi / 2) angle -= math.pi;
    if (angle < -math.pi / 2) angle += math.pi;
    final painter = TextPainter(
      text: TextSpan(text: text, style: AskanceText.number(12)),
      textDirection: TextDirection.ltr,
    )..layout();
    final width = painter.width + 10;
    final height = painter.height + 6;
    canvas.save();
    canvas.translate((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
    canvas.rotate(angle);
    // Turned with the line, "up" is off its upper side.
    final tab = Rect.fromCenter(
      center: Offset(0, -(_labelGap + height / 2)),
      width: width,
      height: height,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(tab, const Radius.circular(AskanceRadius.small)),
      Paint()..color = AskanceColors.paper,
    );
    painter.paint(
      canvas,
      tab.center - Offset(painter.width / 2, painter.height / 2),
    );
    canvas.restore();
    painter.dispose();
  }

  @override
  bool shouldRepaint(_LineEditPainter old) =>
      old.lines != lines ||
      old.boxes != boxes ||
      old.crop != crop ||
      old.picture != picture ||
      old.visible != visible ||
      old.photo != photo ||
      old.flipped != flipped ||
      old.selected != selected ||
      old.selectedBox != selectedBox ||
      old.draftLine != draftLine ||
      old.draftBox != draftBox;
}

/// Each box's proportions, on a tab above it.
class _BoxLabelPainter extends CustomPainter {
  _BoxLabelPainter({
    required this.boxes,
    required this.crop,
    required this.picture,
    required this.visible,
    required this.photo,
    required this.flipped,
  });

  final List<BoardBox> boxes;
  final Rect crop;
  final Rect picture;
  final Rect visible;
  final Size photo;
  final bool flipped;

  @override
  void paint(Canvas canvas, Size size) {
    if (visible.isEmpty || picture.isEmpty) return;
    canvas.save();
    canvas.clipRect(visible);
    for (final box in boxes) {
      if (boxRatioLabel(box, photo) case final text?) {
        paintBoxLabel(
          canvas,
          boxToScreen(box, crop, picture),
          text,
          visible,
          flipped: flipped,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BoxLabelPainter old) =>
      old.boxes != boxes ||
      old.crop != crop ||
      old.picture != picture ||
      old.visible != visible ||
      old.photo != photo ||
      old.flipped != flipped;
}

/// The gap between a box and the tab with its proportions.
const double _boxLabelGap = 4;

/// [text] on a paper tab centred over the top of [box], on screen. Inside
/// the box when there is no room above it in [visible]. [flipped] when the
/// picture is shown upside down, so the words are turned back upright and
/// sit over what reads as the top.
void paintBoxLabel(
  Canvas canvas,
  Rect box,
  String text,
  Rect visible, {
  required bool flipped,
}) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: AskanceText.number(12)),
    textDirection: TextDirection.ltr,
  )..layout();
  final width = painter.width + 10;
  final height = painter.height + 6;
  // Upside down, what reads as the top is the bottom.
  final edge = flipped ? box.bottom : box.top;
  final outward = flipped ? 1.0 : -1.0;
  var centreY = edge + outward * (_boxLabelGap + height / 2);
  final room = flipped
      ? visible.bottom - (centreY + height / 2)
      : (centreY - height / 2) - visible.top;
  if (room < 0) centreY = edge - outward * (_boxLabelGap + height / 2);
  final tab = Rect.fromCenter(
    center: Offset(box.center.dx, centreY),
    width: width,
    height: height,
  );
  canvas.save();
  if (flipped) {
    canvas.translate(tab.center.dx, tab.center.dy);
    canvas.rotate(math.pi);
    canvas.translate(-tab.center.dx, -tab.center.dy);
  }
  canvas.drawRRect(
    RRect.fromRectAndRadius(tab, const Radius.circular(AskanceRadius.small)),
    Paint()..color = AskanceColors.paper,
  );
  painter.paint(
    canvas,
    tab.center - Offset(painter.width / 2, painter.height / 2),
  );
  canvas.restore();
  painter.dispose();
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
