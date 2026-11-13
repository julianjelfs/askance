import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../engine/landmarks.dart';
import '../../state/canvas_session.dart';
import '../../theme.dart';
import '../widgets/controls.dart';
import 'tool_panel.dart' show pointsPrompt;

/// The picture and the drawing side by side, for marking the same points on
/// each. Laid over one another, a tap could not say which of the two it
/// meant, and a chin is hard to find in a blend of two chins.
///
/// Side by side or one above the other, whichever shows both larger. Each
/// pane zooms and pans on its own, so a point can be placed as finely as
/// the photograph allows.
class PointsCompare extends StatelessWidget {
  const PointsCompare({super.key, required this.session});

  final CanvasSession session;

  @override
  Widget build(BuildContext context) {
    final s = DesignScale.of(context);
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final photo = session.image;
        final drawing = session.sketchImage;
        if (photo == null || drawing == null) return const SizedBox.shrink();
        final fit = session.landmarkFit;
        final landmarks = session.settings.landmarks;
        final marks = session.settings.sketch?.marks ?? const <Offset?>[];
        final photoSize = Size(photo.width.toDouble(), photo.height.toDouble());
        final drawingSize = Size(
          drawing.width.toDouble(),
          drawing.height.toDouble(),
        );
        final crop = session.settings.crop;

        final labels = {
          for (var i = 0; i < landmarks.length; i++)
            i: landmarks[i].name ?? '${i + 1}',
        };

        // Where each drawn point belongs, for those that are out.
        final arrows = <int, Offset>{};
        if (fit != null) {
          for (var k = 0; k < fit.numbers.length; k++) {
            if (fit.error(k).distance < kPointTolerance) continue;
            arrows[fit.numbers[k] - 1] = fit.drawn[k] + fit.errorOnDrawing(k);
          }
        }

        final picturePane = _Pane(
          key: const ValueKey('picture'),
          label: 'Picture',
          image: photo,
          source: Rect.fromLTWH(
            crop.left * photoSize.width,
            crop.top * photoSize.height,
            crop.width * photoSize.width,
            crop.height * photoSize.height,
          ),
          points: {
            for (var i = 0; i < landmarks.length; i++)
              i: Offset(
                landmarks[i].at.dx * photoSize.width,
                landmarks[i].at.dy * photoSize.height,
              ),
          },
          labels: labels,
          selected: session.selectedPoint,
          onSelect: session.selectPoint,
          waiting: session.nextMark,
          ring: false,
          onTap: (at) => session.addLandmark(
            Offset(at.dx / photoSize.width, at.dy / photoSize.height),
          ),
          onDrag: (i, at) => session.moveLandmark(
            i,
            Offset(
              (at.dx / photoSize.width).clamp(0.0, 1.0),
              (at.dy / photoSize.height).clamp(0.0, 1.0),
            ),
          ),
        );
        final sketchPane = _Pane(
          key: const ValueKey('sketch'),
          label: 'Sketch',
          image: drawing,
          source: Offset.zero & drawingSize,
          points: {
            for (var i = 0; i < marks.length && i < landmarks.length; i++)
              if (marks[i] case final m?)
                i: Offset(m.dx * drawingSize.width, m.dy * drawingSize.height),
          },
          arrows: arrows,
          labels: labels,
          selected: session.selectedPoint,
          onSelect: session.selectPoint,
          ring: true,
          onTap: (at) => session.placeMark(
            Offset(at.dx / drawingSize.width, at.dy / drawingSize.height),
          ),
          onDrag: (i, at) => session.moveMark(
            i,
            Offset(at.dx / drawingSize.width, at.dy / drawingSize.height),
          ),
        );

        final selected = session.selectedPoint;
        return ColoredBox(
          color: AskanceColors.surround,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: AskanceColors.paper,
                padding: EdgeInsets.fromLTRB(14 * s, 10 * s, 10 * s, 10 * s),
                child: Row(
                  children: [
                    Expanded(
                      // What is out shows as arrows on the sketch; the
                      // words wait in the panel, behind Details.
                      child: Text(
                        pointsPrompt(session),
                        style: AskanceText.body(13.5).by(s),
                      ),
                    ),
                    SizedBox(width: 10 * s),
                    ActionButton(
                      label: 'Undo',
                      solid: false,
                      height: 36,
                      fontSize: 13.5,
                      enabled: landmarks.isNotEmpty,
                      onPressed: session.undoPoint,
                    ),
                    SizedBox(width: 8 * s),
                    ActionButton(
                      label: 'Clear',
                      solid: false,
                      height: 36,
                      fontSize: 13.5,
                      enabled: landmarks.isNotEmpty,
                      onPressed: session.clearPoints,
                    ),
                    SizedBox(width: 8 * s),
                    ActionButton(
                      label: 'Done',
                      height: 36,
                      fontSize: 13.5,
                      onPressed: () => session.setMarkingPoints(false),
                    ),
                  ],
                ),
              ),
              if (selected != null && selected < landmarks.length)
                _NameChips(
                  key: ValueKey(selected),
                  index: selected,
                  current: landmarks[selected].name,
                  taken: {for (final l in landmarks) ?l.name},
                  onName: (name) => session.nameLandmark(selected, name),
                ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, room) {
                    final wide = sideBySide(
                      room.biggest,
                      Size(
                        crop.width * photoSize.width,
                        crop.height * photoSize.height,
                      ),
                      drawingSize,
                      gap: 2 * s,
                    );
                    return Flex(
                      direction: wide ? Axis.horizontal : Axis.vertical,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: picturePane),
                        SizedBox(width: 2 * s, height: 2 * s),
                        Expanded(child: sketchPane),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Whether [a] and [b] show larger side by side in [room] than one above
/// the other, each contained in half of it less [gap]. Larger means the
/// smaller of the two is larger: neither should be squeezed to make room
/// for the other. Portrait photographs go side by side in a square room.
bool sideBySide(Size room, Size a, Size b, {double gap = 0}) {
  double fit(Size pane, Size image) =>
      math.min(pane.width / image.width, pane.height / image.height);
  final across = Size((room.width - gap) / 2, room.height);
  final down = Size(room.width, (room.height - gap) / 2);
  return math.min(fit(across, a), fit(across, b)) >=
      math.min(fit(down, a), fit(down, b));
}

/// Names to call point [index] by, one tap each, and a way to type another.
/// Names other points already have are left out.
class _NameChips extends StatefulWidget {
  const _NameChips({
    super.key,
    required this.index,
    required this.current,
    required this.taken,
    required this.onName,
  });

  final int index;
  final String? current;
  final Set<String> taken;
  final ValueChanged<String?> onName;

  @override
  State<_NameChips> createState() => _NameChipsState();
}

class _NameChipsState extends State<_NameChips> {
  bool _typing = false;
  final _focus = FocusNode();
  late final _text = TextEditingController(
    text: kLandmarkNames.contains(widget.current) ? '' : widget.current,
  );

  @override
  void dispose() {
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    widget.onName(_text.text);
    setState(() => _typing = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = DesignScale.of(context);
    Widget chip(String label, VoidCallback onTap, {bool on = false}) =>
        GestureDetector(
          onTap: onTap,
          child: Container(
            margin: EdgeInsets.only(right: 6 * s),
            padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 6 * s),
            decoration: BoxDecoration(
              color: on ? AskanceColors.accent : AskanceColors.paper,
              borderRadius: BorderRadius.circular(AskanceRadius.small * s),
              border: Border.all(
                color: on ? AskanceColors.accent : AskanceColors.ruleStrong,
              ),
            ),
            child: Text(
              label,
              style: AskanceText.label(
                12.5,
                color: on ? AskanceColors.paper : AskanceColors.graphite,
              ).by(s),
            ),
          ),
        );

    final current = widget.current;
    return Container(
      color: AskanceColors.gesso,
      padding: EdgeInsets.fromLTRB(14 * s, 8 * s, 8 * s, 8 * s),
      child: Row(
        children: [
          Text(
            'Point ${widget.index + 1}',
            style: AskanceText.label(12.5).by(s),
          ),
          SizedBox(width: 10 * s),
          Expanded(
            child: _typing
                ? Row(
                    children: [
                      Expanded(
                        child: EditableText(
                          controller: _text,
                          focusNode: _focus,
                          autofocus: true,
                          style: AskanceText.body(13.5).by(s),
                          cursorColor: AskanceColors.accent,
                          backgroundCursorColor: AskanceColors.muted,
                          onSubmitted: (_) => _submit(),
                        ),
                      ),
                      chip('Use', _submit, on: true),
                    ],
                  )
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final name in kLandmarkNames)
                          if (name == current || !widget.taken.contains(name))
                            chip(
                              name,
                              () =>
                                  widget.onName(name == current ? null : name),
                              on: name == current,
                            ),
                        if (current != null &&
                            !kLandmarkNames.contains(current))
                          chip(current, () => widget.onName(null), on: true),
                        chip('Other…', () => setState(() => _typing = true)),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// One of the two images, zoomable, with its points over it. Everything
/// below is in pixels of [image].
class _Pane extends StatefulWidget {
  const _Pane({
    super.key,
    required this.label,
    required this.image,
    required this.source,
    required this.points,
    required this.ring,
    required this.labels,
    required this.selected,
    required this.onSelect,
    required this.onTap,
    required this.onDrag,
    this.waiting,
    this.arrows = const {},
  });

  final String label;
  final ui.Image image;

  /// The part of [image] shown.
  final Rect source;

  /// Each point by its index, numbered from one on screen.
  final Map<int, Offset> points;

  /// Where each point that is out belongs, by its index.
  final Map<int, Offset> arrows;

  /// The point waiting for its partner in the other pane, ringed.
  final int? waiting;

  /// Points drawn as rings, the drawing's, rather than dots.
  final bool ring;

  /// What each point is labelled with: its name, or its number.
  final Map<int, String> labels;

  /// The point the name chips act on, its label marked out.
  final int? selected;
  final ValueChanged<int> onSelect;

  final ValueChanged<Offset> onTap;
  final void Function(int index, Offset at) onDrag;

  @override
  State<_Pane> createState() => _PaneState();
}

class _PaneState extends State<_Pane> {
  final _zoom = TransformationController();
  final _content = GlobalKey();

  /// How far the point being dragged sits from the finger, in the pane's
  /// own unzoomed space, so it moves with the finger rather than jumping
  /// under it.
  Offset _grab = Offset.zero;

  /// How near, on screen, a finger has to come to a point to take hold of
  /// it: a finger covers what it reaches for.
  static const double _reach = 22;

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  Rect _shown(Size room) {
    final src = widget.source.size;
    final k = math.min(room.width / src.width, room.height / src.height);
    final size = src * k;
    return Rect.fromCenter(
      center: room.center(Offset.zero),
      width: size.width,
      height: size.height,
    );
  }

  Offset _toImage(Offset local, Rect shown) =>
      widget.source.topLeft +
      Offset(
        (local.dx - shown.left) / shown.width * widget.source.width,
        (local.dy - shown.top) / shown.height * widget.source.height,
      );

  Offset _toLocal(Offset at, Rect shown) => Offset(
    shown.left +
        (at.dx - widget.source.left) / widget.source.width * shown.width,
    shown.top +
        (at.dy - widget.source.top) / widget.source.height * shown.height,
  );

  Offset? _local(Offset global) {
    final box = _content.currentContext?.findRenderObject() as RenderBox?;
    return box?.globalToLocal(global);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final room = constraints.biggest;
        final shown = _shown(room);
        return ClipRect(
          child: Stack(
            children: [
              InteractiveViewer(
                transformationController: _zoom,
                maxScale: 10,
                child: ListenableBuilder(
                  listenable: _zoom,
                  builder: (context, _) {
                    final zoom = _zoom.value.getMaxScaleOnAxis();
                    final reach = _reach / zoom;
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (d) {
                        if (!shown.contains(d.localPosition)) return;
                        widget.onTap(_toImage(d.localPosition, shown));
                      },
                      child: SizedBox(
                        key: _content,
                        width: room.width,
                        height: room.height,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: CustomPaint(
                                painter: _PanePainter(
                                  image: widget.image,
                                  source: widget.source,
                                  shown: shown,
                                  points: {
                                    for (final e in widget.points.entries)
                                      e.key: _toLocal(e.value, shown),
                                  },
                                  arrows: {
                                    for (final e in widget.arrows.entries)
                                      e.key: _toLocal(e.value, shown),
                                  },
                                  waiting: widget.waiting,
                                  labels: widget.labels,
                                  selected: widget.selected,
                                  ring: widget.ring,
                                  zoom: zoom,
                                ),
                              ),
                            ),
                            // A handle on each point, so a drag that starts
                            // on one moves it rather than the view: a
                            // drag wins the arena before a pan does.
                            for (final e in widget.points.entries)
                              Positioned(
                                left: _toLocal(e.value, shown).dx - reach,
                                top: _toLocal(e.value, shown).dy - reach,
                                width: reach * 2,
                                height: reach * 2,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  // A tap on a point picks it to name, rather
                                  // than placing a new one.
                                  onTap: () => widget.onSelect(e.key),
                                  onPanStart: (d) {
                                    final at = _local(d.globalPosition);
                                    if (at == null) return;
                                    _grab = _toLocal(e.value, shown) - at;
                                  },
                                  onPanUpdate: (d) {
                                    final at = _local(d.globalPosition);
                                    if (at == null) return;
                                    final to = at + _grab;
                                    widget.onDrag(
                                      e.key,
                                      _toImage(
                                        Offset(
                                          to.dx.clamp(shown.left, shown.right),
                                          to.dy.clamp(shown.top, shown.bottom),
                                        ),
                                        shown,
                                      ),
                                    );
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              Positioned(
                left: 8,
                top: 8,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AskanceColors.paper,
                      borderRadius: BorderRadius.circular(AskanceRadius.small),
                    ),
                    child: Text(widget.label, style: AskanceText.label(12)),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The image and its points, all in the pane's own unzoomed space. Marks
/// are drawn at a size divided by [zoom], so they stay the same size on
/// screen however far the pane is zoomed.
class _PanePainter extends CustomPainter {
  _PanePainter({
    required this.image,
    required this.source,
    required this.shown,
    required this.points,
    required this.arrows,
    required this.waiting,
    required this.labels,
    required this.selected,
    required this.ring,
    required this.zoom,
  });

  final Map<int, String> labels;
  final int? selected;

  final ui.Image image;
  final Rect source;
  final Rect shown;
  final Map<int, Offset> points;
  final Map<int, Offset> arrows;
  final int? waiting;
  final bool ring;
  final double zoom;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      source,
      shown,
      Paint()..filterQuality = FilterQuality.medium,
    );
    final u = 1 / zoom;

    final arrow = Paint()
      ..strokeWidth = 2 * u
      ..strokeCap = StrokeCap.round
      ..color = AskanceColors.accent;
    for (final MapEntry(key: i, value: to) in arrows.entries) {
      final from = points[i];
      if (from == null) continue;
      canvas.drawLine(from, to, arrow);
      final back = from - to;
      if (back.distance == 0) continue;
      final d = back / back.distance * 8 * u;
      for (final turn in [0.5, -0.5]) {
        final c = math.cos(turn);
        final s = math.sin(turn);
        canvas.drawLine(
          to,
          to + Offset(d.dx * c - d.dy * s, d.dx * s + d.dy * c),
          arrow,
        );
      }
    }

    for (final MapEntry(key: i, value: at) in points.entries) {
      if (i == waiting) {
        canvas.drawCircle(
          at,
          11 * u,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2 * u
            ..color = AskanceColors.accent,
        );
      }
      if (ring) {
        canvas.drawCircle(
          at,
          6 * u,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4 * u
            ..color = AskanceColors.paper,
        );
        canvas.drawCircle(
          at,
          6 * u,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2 * u
            ..color = AskanceColors.graphite,
        );
      } else {
        canvas.drawCircle(at, 6 * u, Paint()..color = AskanceColors.paper);
        canvas.drawCircle(at, 4.5 * u, Paint()..color = AskanceColors.accent);
      }
      _number(canvas, at, labels[i] ?? '${i + 1}', u, on: i == selected);
    }
  }

  void _number(
    Canvas canvas,
    Offset at,
    String text,
    double u, {
    bool on = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: AskanceText.number(
          11,
          color: on ? AskanceColors.paper : AskanceColors.graphite,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.scale(u);
    final tab = Rect.fromLTWH(
      8,
      -10 - painter.height - 4,
      painter.width + 8,
      painter.height + 4,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(tab, const Radius.circular(AskanceRadius.small)),
      Paint()..color = on ? AskanceColors.accent : AskanceColors.paper,
    );
    painter.paint(canvas, tab.topLeft + const Offset(4, 2));
    canvas.restore();
    painter.dispose();
  }

  @override
  bool shouldRepaint(_PanePainter old) => true;
}
