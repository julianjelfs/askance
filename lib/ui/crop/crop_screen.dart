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
import '../widgets/controls.dart';

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
    return ColoredBox(
      color: AskanceColors.ink,
      child: Padding(
        padding: EdgeInsets.only(top: padding.top, bottom: padding.bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(16 * s, 14 * s, 16 * s, 0),
              child: Text(
                'CROP TO THE BOARD',
                style: AskanceText.sectionLabel().by(s),
              ),
            ),
            Expanded(child: CropPicture(draft: _draft)),
            Container(
              constraints: const BoxConstraints(maxWidth: 550),
              padding: EdgeInsets.fromLTRB(16 * s, 4 * s, 16 * s, 14 * s),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CropShapeControls(draft: _draft),
                  SizedBox(height: 14 * s),
                  CropActions(
                    onCancel: () => Navigator.of(context).pop(),
                    onApply: () {
                      _draft.apply();
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              ),
            ),
          ],
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
          SegmentedControl<CropShape>(
            values: CropShape.values,
            selected: draft.shape,
            labelOf: (v) => v.label,
            onChanged: draft.setShape,
            fontSize: 10,
          ),
          SizedBox(height: 10 * s),
          IgnorePointer(
            ignoring: !draft.turnable,
            child: Opacity(
              opacity: draft.turnable ? 1 : 0.35,
              child: SegmentedControl<bool>(
                values: const [false, true],
                selected: draft.landscape,
                labelOf: (v) => v ? 'LANDSCAPE' : 'PORTRAIT',
                onChanged: draft.setLandscape,
                fontSize: 10,
                underline: true,
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
            onDark: true,
            height: 40,
            fontSize: 12,
            onPressed: onCancel,
          ),
        ),
        SizedBox(width: 8 * s),
        Expanded(
          child: ActionButton(
            label: 'Crop',
            trailing: '→',
            height: 40,
            fontSize: 12,
            onPressed: onApply,
          ),
        ),
      ],
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
