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

/// Cuts the study down to a part of its photograph, in the shape of the board
/// it will be painted on.
///
/// Shows the whole photograph, untouched, with the crop lit and the rest
/// dimmed. The shape is chosen from a short list rather than dragged out by
/// hand: the reason to crop is to match a board, and a board is a known
/// shape. Drag moves the crop, pinch or scroll resizes it, and nothing
/// reaches the study until CROP is pressed.
class CropScreen extends StatefulWidget {
  const CropScreen({super.key, required this.session});

  final CanvasSession session;

  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  late CropShape _shape;
  late bool _landscape;
  late Offset _centre;
  late double _scale;

  /// Where the photograph is drawn, for turning a drag into a fraction of it.
  Rect _imageRect = Rect.zero;

  double _gestureScale = 1;

  Size get _imageSize {
    final image = widget.session.image!;
    return Size(image.width.toDouble(), image.height.toDouble());
  }

  @override
  void initState() {
    super.initState();
    final crop = widget.session.settings.crop;
    final found = cropShapeOf(_imageSize, crop);
    // A crop that matches no shape can only come from a hand-edited manifest;
    // it is kept as it stands unless a shape is picked.
    _shape = found?.shape ?? CropShape.whole;
    _landscape = found == null || found.shape == CropShape.whole
        ? _imageSize.width > _imageSize.height
        : found.landscape;
    _centre = crop.center;
    _scale = cropScaleOf(_imageSize, crop);
  }

  Rect get _crop => switch (_shape.aspect(landscape: _landscape)) {
    null => kWholeImage,
    final aspect => fitCrop(_imageSize, aspect, centre: _centre, scale: _scale),
  };

  void _setShape(CropShape shape) => setState(() {
    if (_shape == CropShape.whole) {
      // Coming from the whole photograph there is nothing to keep: start
      // from the largest crop of the new shape, in the middle.
      _centre = const Offset(0.5, 0.5);
      _scale = 1;
    }
    _shape = shape;
  });

  void _setLandscape(bool landscape) => setState(() {
    _landscape = landscape;
    // The same scale the other way round is a different crop entirely; the
    // largest is the only one that is obviously the same choice turned.
    _scale = 1;
  });

  /// Folds the clamping back in, so a drag past the edge does not have to be
  /// undone before the crop moves the other way.
  void _settle(Rect crop) {
    _centre = crop.center;
    _scale = cropScaleOf(_imageSize, crop);
  }

  void _onScaleStart(ScaleStartDetails details) => _gestureScale = _scale;

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_shape == CropShape.whole || _imageRect.isEmpty) return;
    setState(() {
      _centre += Offset(
        details.focalPointDelta.dx / _imageRect.width,
        details.focalPointDelta.dy / _imageRect.height,
      );
      _scale = _gestureScale * details.scale;
      _settle(_crop);
    });
  }

  void _onScroll(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || _shape == CropShape.whole) return;
    setState(() {
      _scale *= event.scrollDelta.dy > 0 ? 0.95 : 1.05;
      _settle(_crop);
    });
  }

  void _apply() {
    widget.session.setCrop(_crop);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = DesignScale.of(context);
    final padding = MediaQuery.paddingOf(context);
    final settings = widget.session.settings;
    final turnable = _shape.shortOverLong != null && _shape.shortOverLong! < 1;

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
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final margin = 16 * s;
                  _imageRect = containRect(
                    _imageSize,
                    Size(
                      constraints.maxWidth - margin * 2,
                      constraints.maxHeight - margin * 2,
                    ),
                  ).shift(Offset(margin, margin));
                  return Listener(
                    onPointerSignal: _onScroll,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onScaleStart: _onScaleStart,
                      onScaleUpdate: _onScaleUpdate,
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: _CropPainter(
                          image: widget.session.image!,
                          imageRect: _imageRect,
                          crop: _crop,
                          settings: settings,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Container(
              constraints: const BoxConstraints(maxWidth: 550),
              padding: EdgeInsets.fromLTRB(16 * s, 4 * s, 16 * s, 14 * s),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedControl<CropShape>(
                    values: CropShape.values,
                    selected: _shape,
                    labelOf: (v) => v.label,
                    onChanged: _setShape,
                    fontSize: 10,
                  ),
                  SizedBox(height: 10 * s),
                  IgnorePointer(
                    ignoring: !turnable,
                    child: Opacity(
                      opacity: turnable ? 1 : 0.35,
                      child: SegmentedControl<bool>(
                        values: const [false, true],
                        selected: _landscape,
                        labelOf: (v) => v ? 'LANDSCAPE' : 'PORTRAIT',
                        onChanged: _setLandscape,
                        fontSize: 10,
                        underline: true,
                      ),
                    ),
                  ),
                  SizedBox(height: 14 * s),
                  Row(
                    children: [
                      Expanded(
                        child: ActionButton(
                          label: 'Cancel',
                          solid: false,
                          onDark: true,
                          height: 40,
                          fontSize: 12,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                      SizedBox(width: 8 * s),
                      Expanded(
                        child: ActionButton(
                          label: 'Crop',
                          trailing: '→',
                          height: 40,
                          fontSize: 12,
                          onPressed: _apply,
                        ),
                      ),
                    ],
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
