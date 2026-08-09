import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/blur_pass.dart';
import '../../engine/deferred_disposer.dart';
import '../../engine/engine.dart';
import '../../engine/value_painter.dart';
import '../../model/study.dart';
import '../../state/providers.dart';
import '../../theme.dart';
import '../widgets/controls.dart';
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

/// A shelf card: a 4:5 thumbnail rendered **by the engine** using that study's
/// own settings, a 2px rule, then the caption block.
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

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _confirmingDelete ? null : widget.onOpen,
      onLongPress: () => setState(() => _confirmingDelete = true),
      child: Container(
        decoration: BoxDecoration(
          color: AskanceColors.surface,
          border: Border.all(color: AskanceColors.dividerLight, width: kRule),
        ),
        child: Stack(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AspectRatio(
                  aspectRatio: 4 / 5,
                  // Grows into the canvas when the card is opened. The
                  // default shuttle flies the destination's own child, so the
                  // flight lands on exactly what the canvas will show.
                  child: Hero(
                    tag: studyHeroTag(study.id),
                    child: StudyThumbnail(study: study),
                  ),
                ),
                const Rule(color: AskanceColors.dividerLight),
                Padding(
                  padding: EdgeInsets.fromLTRB(10 * s, 8 * s, 10 * s, 10 * s),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        study.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AskanceText.cardName().by(s),
                      ),
                      SizedBox(height: 4 * s),
                      Text(
                        study.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AskanceText.caption(10).by(s),
                      ),
                    ],
                  ),
                ),
              ],
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
    );
  }
}

/// Long-press reveals this over the card rather than opening a dialog: the
/// design has exactly one sheet and this is not it.
class _DeleteConfirm extends StatelessWidget {
  const _DeleteConfirm({required this.onCancel, required this.onDelete});

  final VoidCallback onCancel;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final s = DesignScale.of(context);
    return Container(
      color: const Color(0xF2F3F2F2),
      foregroundDecoration: const BoxDecoration(
        border: Border.fromBorderSide(
          BorderSide(color: AskanceColors.accent, width: kRule),
        ),
      ),
      padding: EdgeInsets.all(12 * s),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'DELETE THIS STUDY?',
            style: AskanceText.sectionLabel(color: AskanceColors.accent).by(s),
          ),
          SizedBox(height: 14 * s),
          ActionButton(
            label: 'Delete',
            trailing: '×',
            height: 36,
            fontSize: 12,
            onPressed: onDelete,
          ),
          SizedBox(height: 8 * s),
          ActionButton(
            label: 'Cancel',
            height: 36,
            fontSize: 12,
            solid: false,
            onPressed: onCancel,
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

  @override
  void dispose() {
    _disposer.disposeAll();
    _blur.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = ref
        .watch(studyImageProvider(widget.study.imageKey))
        .valueOrNull;
    final shader = ref.watch(shaderProvider).valueOrNull;
    if (image == null || shader == null) {
      return const ColoredBox(color: AskanceColors.surface);
    }
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        _blur.request(
          source: image,
          outputPx: constraints.biggest * dpr,
          detail: widget.study.settings.detail,
          view: const ViewTransform(),
        );
        return ListenableBuilder(
          listenable: _blur,
          builder: (context, _) => CustomPaint(
            painter: ValuePainter(
              shader: shader,
              source: image,
              blurred: _blur.image,
              settings: widget.study.settings,
              view: const ViewTransform(),
              devicePixelRatio: dpr,
              peeking: false,
              splitPosition: widget.study.settings.splitPosition,
              regions: null,
              disposer: _disposer,
              drawGrid: true,
            ),
          ),
        );
      },
    );
  }
}

/// The dashed empty slot that closes the grid. Also stands in as the whole
/// empty state when the shelf has nothing on it.
class EmptySlot extends StatelessWidget {
  const EmptySlot({super.key, this.label = 'empty slot'});

  final String label;

  @override
  Widget build(BuildContext context) {
    final s = DesignScale.of(context);
    return CustomPaint(
      painter: _EmptySlotPainter(),
      child: Padding(
        padding: EdgeInsets.all(12 * s),
        child: Align(
          alignment: Alignment.bottomLeft,
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 9 * s,
              height: 1.3,
              color: AskanceColors.mutedLight,
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptySlotPainter extends CustomPainter {
  static const _stripe = Color(0x0D201E1D);

  @override
  void paint(Canvas canvas, Size size) {
    // 45 degree, 6px stripes at 5% ink.
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final paint = Paint()
      ..color = _stripe
      ..strokeWidth = 3;
    for (var x = -size.height; x < size.width + size.height; x += 6) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x + size.height, size.height),
        paint,
      );
    }
    canvas.restore();

    final dash = Paint()
      ..color = AskanceColors.emptySlot
      ..style = PaintingStyle.stroke
      ..strokeWidth = kRule;
    const on = 6.0, off = 5.0;
    final rect = Rect.fromLTWH(1, 1, size.width - 2, size.height - 2);
    final path = Path()..addRect(rect);
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
  bool shouldRepaint(covariant _EmptySlotPainter old) => false;
}
