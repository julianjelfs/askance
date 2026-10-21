import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/blur_pass.dart';
import '../../engine/crop.dart';
import '../../engine/engine.dart';
import '../../engine/deferred_disposer.dart';
import '../../engine/value_painter.dart';
import '../../model/study.dart';
import '../../state/providers.dart';
import '../../theme.dart';
import '../widgets/controls.dart';
import '../widgets/glyphs.dart';
import 'shelf_screen.dart';

/// Decoded source images, cached per study so a shelf of thumbnails decodes
/// each photograph once.
final studyImageProvider = FutureProvider.family<ui.Image?, String>((
  ref,
  key,
) async {
  final bytes = await ref.read(repositoryProvider).readImage(key);
  if (bytes == null) return null;
  final image = await decodeImage(bytes);
  ref.onDispose(image.dispose);
  return image;
});

/// A shelf card: the study's thumbnail at its own crop's proportion,
/// rendered **by the engine** using that study's own settings, beside its
/// name, its board, and the palette it paints in.
///
/// The thumbnails show the value map rather than the source photograph on
/// purpose — the shelf shows what you made, not what you started from.
class StudyCard extends ConsumerStatefulWidget {
  const StudyCard({
    super.key,
    required this.study,
    required this.onOpen,
    required this.onDelete,
  });

  final Study study;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  ConsumerState<StudyCard> createState() => _StudyCardState();
}

class _StudyCardState extends ConsumerState<StudyCard> {
  bool _confirmingDelete = false;

  @override
  Widget build(BuildContext context) {
    final s = DesignScale.of(context);
    final study = widget.study;
    final settings = study.settings;
    final image = ref.watch(studyImageProvider(study.imageKey)).valueOrNull;

    // Every card is the same height, so a shelf reads as rows, and the
    // thumbnail has the same slot on every card, so the names line up. The
    // picture takes the crop's shape inside its slot.
    final picture = image == null
        ? null
        : croppedSize(
            Size(image.width.toDouble(), image.height.toDouble()),
            settings.crop,
          );
    final aspect = picture == null || picture.isEmpty
        ? 0.75
        : (picture.width / picture.height).clamp(0.6, 1.4);
    final thumbHeight = 130 * s;
    final slotWidth = 110 * s;
    final thumbWidth = (thumbHeight * aspect).clamp(0.0, slotWidth);
    final thumbSize = Size(thumbWidth, thumbWidth / aspect);
    final radius = BorderRadius.circular(AskanceRadius.card * s);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _confirmingDelete ? null : widget.onOpen,
      onLongPress: () => setState(() => _confirmingDelete = true),
      child: Container(
        decoration: BoxDecoration(
          color: AskanceColors.paper,
          borderRadius: radius,
          boxShadow: const [
            BoxShadow(color: AskanceColors.rule, offset: Offset(0, 1)),
          ],
        ),
        // While the card is asking about deletion the accent frames it,
        // painted in the foreground so the content does not shift.
        foregroundDecoration: _confirmingDelete
            ? BoxDecoration(
                borderRadius: radius,
                border: Border.all(color: AskanceColors.accent, width: 2),
              )
            : null,
        child: ClipRRect(
          borderRadius: radius,
          child: Stack(
            children: [
              Padding(
                padding: EdgeInsets.all(12 * s),
                child: SizedBox(
                  height: thumbHeight,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: slotWidth,
                        child: Center(
                          child: SizedBox.fromSize(
                            size: thumbSize,
                            // Grows into the canvas when the card is opened.
                            // The default shuttle flies the destination's own
                            // child, so the flight lands on exactly what the
                            // canvas will show.
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(3 * s),
                              child: Hero(
                                tag: studyHeroTag(study.id),
                                child: StudyThumbnail(study: study),
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: 14 * s),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              // Clear of the trash in the corner.
                              padding: EdgeInsets.only(
                                right: 24 * s,
                                top: 2 * s,
                              ),
                              child: Text(
                                study.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AskanceText.title(17.5).by(s),
                              ),
                            ),
                            SizedBox(height: 4 * s),
                            Text(
                              _board(image, settings),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AskanceText.caption(13).by(s),
                            ),
                            // The palette and the count sit along the foot, level
                            // from card to card whatever the name's length.
                            const Spacer(),
                            // The palette it paints in, darkest first, outlined
                            // so the palest value still has an end.
                            Container(
                              foregroundDecoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(4 * s),
                                border: Border.all(
                                  color: AskanceColors.rule,
                                  width: kRule,
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4 * s),
                                child: SizedBox(
                                  height: 16 * s,
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      for (final colour in settings.palette)
                                        Expanded(
                                          child: ColoredBox(color: colour),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(height: 8 * s),
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: '${settings.steps} values',
                                    style: AskanceText.label(13).by(s),
                                  ),
                                  TextSpan(
                                    text:
                                        ' · ${settings.scale.shortName}'
                                        ' · ${study.formattedDate}',
                                    style: AskanceText.caption(13).by(s),
                                  ),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Long press works too, but nothing advertises it.
              Positioned(
                top: 0,
                right: 0,
                child: Semantics(
                  button: true,
                  label: 'Delete this study',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _confirmingDelete = true),
                    child: Padding(
                      padding: EdgeInsets.all(12 * s),
                      child: GlyphIcon(
                        Glyph.trash,
                        size: 16 * s,
                        color: AskanceColors.accent,
                      ),
                    ),
                  ),
                ),
              ),
              if (_confirmingDelete)
                Positioned.fill(
                  child: _DeleteConfirm(
                    onCancel: () => setState(() => _confirmingDelete = false),
                    onDelete: () {
                      setState(() => _confirmingDelete = false);
                      widget.onDelete();
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// "A4 portrait · grid 4 × 4", or as much of it as is known before the
  /// photograph has loaded.
  static String _board(ui.Image? image, StudySettings settings) {
    final grid = settings.grid == GridMode.off
        ? 'no grid'
        : 'grid ${settings.gridDivisions} × ${settings.gridDivisions}';
    if (image == null) return grid;
    final found = cropShapeOf(
      Size(image.width.toDouble(), image.height.toDouble()),
      settings.crop,
    );
    final crop = switch (found) {
      null => 'Custom crop',
      (shape: CropShape.whole, landscape: _) => 'Whole photo',
      (shape: CropShape.square, landscape: _) => 'Square',
      (:final shape, :final landscape) =>
        '${shape.label} ${landscape ? 'landscape' : 'portrait'}',
    };
    return '$crop · $grid';
  }
}

/// Long-press reveals this over the card rather than opening a dialog.
class _DeleteConfirm extends StatelessWidget {
  const _DeleteConfirm({required this.onCancel, required this.onDelete});

  final VoidCallback onCancel;
  final VoidCallback onDelete;

  /// The veil over the card while it asks.
  static const veil = Color(0xF2FFFFFF);

  @override
  Widget build(BuildContext context) {
    final s = DesignScale.of(context);
    return Container(
      // No border of its own: the card's own outline turns red underneath.
      color: veil,
      padding: EdgeInsets.all(14 * s),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Delete this study?', style: AskanceText.title(16).by(s)),
          SizedBox(height: 12 * s),
          Row(
            children: [
              Expanded(
                child: ActionButton(
                  label: 'Cancel',
                  height: 40,
                  fontSize: 14,
                  solid: false,
                  centred: true,
                  onPressed: onCancel,
                ),
              ),
              SizedBox(width: 8 * s),
              Expanded(
                child: ActionButton(
                  label: 'Delete',
                  height: 40,
                  fontSize: 14,
                  centred: true,
                  onPressed: onDelete,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Runs the engine over a study's own settings at thumbnail size.
class StudyThumbnail extends ConsumerStatefulWidget {
  const StudyThumbnail({super.key, required this.study});

  final Study study;

  @override
  ConsumerState<StudyThumbnail> createState() => _StudyThumbnailState();
}

class _StudyThumbnailState extends ConsumerState<StudyThumbnail> {
  final _disposer = DeferredDisposer();
  final _blur = BlurPass();
  final _photoBlur = BlurPass();

  @override
  void dispose() {
    _disposer.disposeAll();
    _blur.dispose();
    _photoBlur.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = ref
        .watch(studyImageProvider(widget.study.imageKey))
        .valueOrNull;
    final shader = ref.watch(shaderProvider).valueOrNull;
    if (image == null || shader == null) {
      return const ColoredBox(color: AskanceColors.well);
    }
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        // Close to where the study was left, but always filling the card: a
        // shelf of letterboxed thumbnails reads as gaps rather than pictures.
        final view = coveringView(
          widget.study.settings.view,
          croppedSize(
            Size(image.width.toDouble(), image.height.toDouble()),
            widget.study.settings.crop,
          ),
          constraints.biggest,
        );

        _blur.request(
          source: image,
          outputPx: constraints.biggest * dpr,
          detail: widget.study.settings.detail,
          view: view,
          smoothing: widget.study.settings.smoothing,
          lockDetail: widget.study.settings.lockDetail,
          crop: widget.study.settings.crop,
          steps: widget.study.settings.steps,
          bias: widget.study.settings.bias,
          tone: widget.study.settings.tone,
        );
        if (widget.study.settings.photoBlurDetail case final detail?) {
          _photoBlur.request(
            source: image,
            outputPx: constraints.biggest * dpr,
            detail: detail,
            view: view,
            crop: widget.study.settings.crop,
          );
        }
        return ListenableBuilder(
          listenable: Listenable.merge([_blur, _photoBlur]),
          builder: (context, _) => CustomPaint(
            painter: ValuePainter(
              shader: shader,
              source: image,
              blurred: _blur.image,
              photoBlurred: _photoBlur.image,
              settings: widget.study.settings,
              view: view,
              devicePixelRatio: dpr,
              peeking: false,
              splitPosition: widget.study.settings.splitPosition,
              disposer: _disposer,
              drawGrid: true,
            ),
          ),
        );
      },
    );
  }
}

/// The empty shelf: a dashed card that starts a study when tapped.
class EmptySlotCard extends StatelessWidget {
  const EmptySlotCard({
    super.key,
    this.label = 'No studies yet. Start one from a photograph.',
    this.onNew,
  });

  final String label;

  /// Tapping the slot starts a study: an empty space that invites filling
  /// should accept the invitation itself.
  final VoidCallback? onNew;

  @override
  Widget build(BuildContext context) {
    final s = DesignScale.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onNew,
      child: CustomPaint(
        painter: _EmptySlotPainter(radius: AskanceRadius.card * s),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 20 * s, vertical: 28 * s),
          child: Column(
            children: [
              if (onNew != null)
                Text(
                  '+',
                  style: AskanceText.display(
                    30,
                    color: AskanceColors.accentInk,
                  ).by(s),
                ),
              SizedBox(height: 8 * s),
              Text(
                label,
                textAlign: TextAlign.center,
                style: AskanceText.body(14, color: AskanceColors.muted).by(s),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptySlotPainter extends CustomPainter {
  _EmptySlotPainter({required this.radius});
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final dash = Paint()
      ..color = AskanceColors.ruleStrong
      ..style = PaintingStyle.stroke
      ..strokeWidth = kRuleStrong;
    const on = 6.0, off = 5.0;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(1, 1, size.width - 2, size.height - 2),
          Radius.circular(radius),
        ),
      );
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + on).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), dash);
        distance = next + off;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _EmptySlotPainter old) => old.radius != radius;
}
