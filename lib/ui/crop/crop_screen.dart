import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../../engine/crop.dart';
import '../../engine/engine.dart';
import '../../engine/value_painter.dart';
import '../../model/study.dart';
import '../../state/canvas_session.dart';
import '../../theme.dart';
import '../shelf/shelf_screen.dart' show NoTransitionRoute;
import '../canvas/tool_panel.dart' show GridControl;
import '../widgets/controls.dart';
import '../widgets/glyphs.dart';

Future<void> showCropScreen(BuildContext context, CanvasSession session) =>
    Navigator.of(
      context,
    ).push(NoTransitionRoute(builder: (_) => CropScreen(session: session)));

/// A crop being chosen, before it reaches the study.
///
/// The shape is picked from a short list rather than dragged out by hand: the
/// reason to crop is to match a board, and a board is a known shape. Drag
/// moves the crop, pinch or scroll resizes it, and nothing reaches the study
/// until [apply].
class CropDraft extends ChangeNotifier {
  CropDraft(this.session) {
    final crop = session.settings.crop;
    final found = cropShapeOf(imageSize, crop);
    // A crop that matches no shape can only come from a hand-edited manifest;
    // it is kept as it stands unless a shape is picked.
    shape = found?.shape ?? CropShape.whole;
    landscape = found == null || found.shape == CropShape.whole
        ? imageSize.width > imageSize.height
        : found.landscape;
    _centre = crop.center;
    _scale = cropScaleOf(imageSize, crop);
  }

  final CanvasSession session;

  late CropShape shape;
  late bool landscape;
  late Offset _centre;
  late double _scale;
  double _gestureScale = 1;

  Size get imageSize {
    final image = session.image!;
    return Size(image.width.toDouble(), image.height.toDouble());
  }

  /// Only a shape with a long side can be turned.
  bool get turnable => shape.shortOverLong != null && shape.shortOverLong! < 1;

  Rect get crop => switch (shape.aspect(landscape: landscape)) {
    null => kWholeImage,
    final aspect => fitCrop(imageSize, aspect, centre: _centre, scale: _scale),
  };

  void setShape(CropShape next) {
    if (shape == CropShape.whole) {
      // Coming from the whole photograph there is nothing to keep: start
      // from the largest crop of the new shape, in the middle.
      _centre = const Offset(0.5, 0.5);
      _scale = 1;
    }
    shape = next;
    notifyListeners();
  }

  void setLandscape(bool next) {
    landscape = next;
    // The same scale the other way round is a different crop entirely; the
    // largest is the only one that is obviously the same choice turned.
    _scale = 1;
    notifyListeners();
  }

  void startGesture() => _gestureScale = _scale;

  /// [delta] is a fraction of the photograph; [scale] is the gesture's own,
  /// relative to where it started.
  void updateGesture(Offset delta, double scale) {
    if (shape == CropShape.whole) return;
    _centre += delta;
    _scale = _gestureScale * scale;
    _settle();
  }

  void resizeBy(double factor) {
    if (shape == CropShape.whole) return;
    _scale *= factor;
    _settle();
  }

  /// Folds the clamping back in, so a drag past the edge does not have to be
  /// undone before the crop moves the other way.
  void _settle() {
    final settled = crop;
    _centre = settled.center;
    _scale = cropScaleOf(imageSize, settled);
    notifyListeners();
  }

  void apply() => session.setCrop(crop);
}

/// The phone's crop: the whole screen, picture above, controls below.
class CropScreen extends StatefulWidget {
  const CropScreen({super.key, required this.session});

  final CanvasSession session;

  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  late final _draft = CropDraft(widget.session);

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = DesignScale.of(context);
    final padding = MediaQuery.paddingOf(context);
    final session = widget.session;
    return ColoredBox(
      color: AskanceColors.gesso,
      child: Padding(
        padding: EdgeInsets.only(top: padding.top, bottom: padding.bottom),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 560 * s),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 52 * s,
                  child: Row(
                    children: [
                      SizedBox(width: 6 * s),
                      Semantics(
                        button: true,
                        label: 'Cancel',
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => Navigator.of(context).pop(),
                          child: SizedBox(
                            width: 44 * s,
                            height: 44 * s,
                            child: Center(
                              child: GlyphIcon(
                                Glyph.close,
                                size: 22 * s,
                                color: AskanceColors.graphite,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          'Board',
                          textAlign: TextAlign.center,
                          style: AskanceText.label(14).by(s),
                        ),
                      ),
                      SizedBox(width: 50 * s),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(20 * s, 6 * s, 20 * s, 14 * s),
                  child: Text(
                    "Match the board you're painting on",
                    style: AskanceText.heading(26).by(s),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14 * s),
                  child: CropShapeControls(draft: _draft),
                ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(14 * s, 14 * s, 14 * s, 0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(
                        AskanceRadius.card * s,
                      ),
                      child: ColoredBox(
                        color: AskanceColors.graphiteRaised,
                        child: CropPicture(draft: _draft),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(14 * s, 14 * s, 14 * s, 0),
                  child: ListenableBuilder(
                    listenable: session,
                    builder: (context, _) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Grid to transfer the drawing',
                          style: AskanceText.label(14.5).by(s),
                        ),
                        SizedBox(height: 8 * s),
                        GridControl(session: session),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(14 * s, 16 * s, 14 * s, 14 * s),
                  child: ActionButton(
                    label: 'Done',
                    centred: true,
                    height: 54,
                    fontSize: 16.5,
                    onPressed: () {
                      _draft.apply();
                      Navigator.of(context).pop();
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The photograph whole, with the crop lit and the rest dimmed, taking drags,
/// pinches and scrolls. Fills whatever room it is given.
class CropPicture extends StatefulWidget {
  const CropPicture({super.key, required this.draft});

  final CropDraft draft;

  @override
  State<CropPicture> createState() => _CropPictureState();
}

class _CropPictureState extends State<CropPicture> {
  /// Where the photograph is drawn, for turning a drag into a fraction of it.
  Rect _imageRect = Rect.zero;

  @override
  Widget build(BuildContext context) {
    final s = DesignScale.of(context);
    final draft = widget.draft;
    return LayoutBuilder(
      builder: (context, constraints) {
        final margin = 16 * s;
        _imageRect = containRect(
          draft.imageSize,
          Size(
            constraints.maxWidth - margin * 2,
            constraints.maxHeight - margin * 2,
          ),
        ).shift(Offset(margin, margin));
        return Listener(
          onPointerSignal: (event) {
            if (event is PointerScrollEvent) {
              draft.resizeBy(event.scrollDelta.dy > 0 ? 0.95 : 1.05);
            }
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: (_) => draft.startGesture(),
            onScaleUpdate: (details) {
              if (_imageRect.isEmpty) return;
              draft.updateGesture(
                Offset(
                  details.focalPointDelta.dx / _imageRect.width,
                  details.focalPointDelta.dy / _imageRect.height,
                ),
                details.scale,
              );
            },
            child: ListenableBuilder(
              listenable: draft,
              builder: (context, _) => CustomPaint(
                size: Size.infinite,
                painter: _CropPainter(
                  image: draft.session.image!,
                  imageRect: _imageRect,
                  crop: draft.crop,
                  settings: draft.session.settings,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Which shape, and which way round.
class CropShapeControls extends StatelessWidget {
  const CropShapeControls({super.key, required this.draft});

  final CropDraft draft;

  @override
  Widget build(BuildContext context) {
    final s = DesignScale.of(context);
    return ListenableBuilder(
      listenable: draft,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (final shape in CropShape.values) ...[
                if (shape.index > 0) SizedBox(width: 8 * s),
                Expanded(
                  child: _ShapeCard(
                    shape: shape,
                    landscape: draft.landscape,
                    selected: draft.shape == shape,
                    onTap: () => draft.setShape(shape),
                  ),
                ),
              ],
            ],
          ),
          SizedBox(height: 10 * s),
          IgnorePointer(
            ignoring: !draft.turnable,
            child: Opacity(
              opacity: draft.turnable ? 1 : 0.4,
              child: SegmentedControl<bool>(
                values: const [false, true],
                selected: draft.landscape,
                labelOf: (v) => v ? 'Landscape' : 'Portrait',
                onChanged: draft.setLandscape,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CropActions extends StatelessWidget {
  const CropActions({super.key, required this.onCancel, required this.onApply});

  final VoidCallback onCancel;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final s = DesignScale.of(context);
    return Row(
      children: [
        Expanded(
          child: ActionButton(
            label: 'Cancel',
            solid: false,
            centred: true,
            height: 46,
            onPressed: onCancel,
          ),
        ),
        SizedBox(width: 8 * s),
        Expanded(
          child: ActionButton(
            label: 'Done',
            centred: true,
            height: 46,
            onPressed: onApply,
          ),
        ),
      ],
    );
  }
}

/// A crop shape drawn at its own proportion, the way round it will be cut.
class _ShapeCard extends StatelessWidget {
  const _ShapeCard({
    required this.shape,
    required this.landscape,
    required this.selected,
    required this.onTap,
  });

  final CropShape shape;
  final bool landscape;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = DesignScale.of(context);
    final ink = selected ? AskanceColors.gesso : AskanceColors.graphite;
    final aspect = shape.aspect(landscape: landscape) ?? 0.68;
    final box = 34 * s;
    final w = aspect >= 1 ? box : box * aspect;
    final h = aspect >= 1 ? box / aspect : box;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: AskanceMotion.chromeFade,
          height: 88 * s,
          decoration: BoxDecoration(
            color: selected ? AskanceColors.graphite : AskanceColors.paper,
            borderRadius: BorderRadius.circular(12 * s),
            border: selected
                ? null
                : Border.all(color: AskanceColors.rule, width: kRule),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: box,
                child: Center(
                  child: Container(
                    width: w,
                    height: h,
                    decoration: BoxDecoration(
                      color: selected && shape != CropShape.whole
                          ? AskanceColors.gesso
                          : null,
                      border: Border.all(
                        color: shape == CropShape.whole
                            ? ink.withValues(alpha: 0.5)
                            : ink,
                        width: kRuleStrong,
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 8 * s),
              Text(
                shape.label,
                style: AskanceText.control(
                  12.5,
                  color: ink,
                  weight: FontWeight.w600,
                ).by(s),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The photograph whole, the outside of the crop dimmed, and the study's grid
/// laid over the crop as it will divide the board.
class _CropPainter extends CustomPainter {
  _CropPainter({
    required this.image,
    required this.imageRect,
    required this.crop,
    required this.settings,
  });

  final ui.Image image;
  final Rect imageRect;
  final Rect crop;
  final StudySettings settings;

  @override
  void paint(Canvas canvas, Size size) {
    if (imageRect.isEmpty) return;
    final source = Size(image.width.toDouble(), image.height.toDouble());
    canvas.drawImageRect(
      image,
      Offset.zero & source,
      imageRect,
      Paint()..filterQuality = FilterQuality.medium,
    );

    final lit = Rect.fromLTRB(
      imageRect.left + crop.left * imageRect.width,
      imageRect.top + crop.top * imageRect.height,
      imageRect.left + crop.right * imageRect.width,
      imageRect.top + crop.bottom * imageRect.height,
    );
    canvas
      ..save()
      ..clipRect(lit, clipOp: ui.ClipOp.difference)
      ..drawRect(imageRect, Paint()..color = const Color(0xB3201E1D))
      ..restore();
    if (settings.grid != GridMode.off) {
      paintGrid(canvas, lit, lit, settings.grid, settings.gridLevel.toDouble());
    }
    canvas.drawRect(
      lit.deflate(kRule / 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = kRule
        ..color = AskanceColors.accent,
    );
  }

  @override
  bool shouldRepaint(covariant _CropPainter old) =>
      old.image != image ||
      old.imageRect != imageRect ||
      old.crop != crop ||
      old.settings != settings;
}
