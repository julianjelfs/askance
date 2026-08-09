import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../model/study.dart';
import '../../state/providers.dart';
import '../../theme.dart';
import '../canvas/canvas_screen.dart';
import '../onboarding/onboarding_screen.dart';
import '../pick_image.dart';
import '../widgets/askance_mark.dart';
import '../widgets/controls.dart';
import 'study_card.dart';

/// The shelf, and the launch screen: what you have made, and two ways to start
/// something new.
class ShelfScreen extends ConsumerWidget {
  const ShelfScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = DesignScale.of(context);
    final studies = ref.watch(studiesProvider).valueOrNull ?? const <Study>[];

    return ColoredBox(
      color: AskanceColors.ground,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _TitleRow(),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(18 * s, 16 * s, 18 * s, 24 * s),
                child: ShelfGrid(
                  studies: studies,
                  columns: 2,
                  onOpen: (study) => openStudy(context, ref, study),
                ),
              ),
            ),
            _Footer(),
          ],
        ),
      ),
    );
  }
}

/// The card grid, shared by the phone shelf and the desktop shelf overlay,
/// which differ only in column count.
class ShelfGrid extends ConsumerWidget {
  const ShelfGrid({
    super.key,
    required this.studies,
    required this.columns,
    required this.onOpen,
  });

  final List<Study> studies;
  final int columns;
  final void Function(Study) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = DesignScale.of(context);
    final gap = 14 * s;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'RECENT STUDIES',
          style: AskanceText.sectionLabel(color: const Color(0x80201E1D)).by(s),
        ),
        SizedBox(height: 10 * s),
        LayoutBuilder(
          builder: (context, constraints) {
            final cellWidth =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final study in studies)
                  SizedBox(
                    width: cellWidth,
                    child: StudyCard(
                      study: study,
                      onOpen: () => onOpen(study),
                      onDelete: () =>
                          ref.read(studiesProvider.notifier).delete(study.id),
                    ),
                  ),
                SizedBox(
                  width: cellWidth,
                  // Matches a card: 4:5 thumbnail plus the caption block.
                  child: AspectRatio(
                    aspectRatio: 4 / 5.9,
                    child: const EmptySlot(),
                  ),
                ),
              ],
            );
          },
        ),
        if (studies.isEmpty) ...[
          SizedBox(height: 14 * s),
          Text(
            'Nothing here yet. Open a photograph and it will '
            'appear on the shelf once you keep it.',
            style: AskanceText.caption(11).by(s),
          ),
        ],
      ],
    );
  }
}

class _TitleRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final s = DesignScale.of(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 18 * s),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AskanceColors.dividerLight, width: kRule),
        ),
      ),
      child: SizedBox(
        height: 56 * s,
        child: Row(
          children: [
            AskanceMark(size: 26 * s),
            SizedBox(width: 10 * s),
            Expanded(
              child: Text('Askance', style: AskanceText.screenTitle().by(s)),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).push(
                NoTransitionRoute(builder: (_) => const OnboardingScreen()),
              ),
              child: Container(
                width: 28 * s,
                height: 28 * s,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: AskanceColors.dividerLight,
                    width: kRule,
                  ),
                ),
                child: Text(
                  '?',
                  style: AskanceText.button(13, color: AskanceColors.ink).by(s),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Footer extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = DesignScale.of(context);
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: AskanceColors.dividerLight, width: kRule),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        18 * s,
        14 * s,
        18 * s,
        14 * s + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        children: [
          ActionButton(
            label: 'New study from photos',
            trailing: '→',
            onPressed: () => startStudy(context, ref, fromCamera: false),
          ),
          SizedBox(height: 10 * s),
          ActionButton(
            label: canTakePhoto ? 'Take a photo' : 'Open an image file',
            trailing: '→',
            solid: false,
            onPressed: () => startStudy(context, ref, fromCamera: canTakePhoto),
          ),
        ],
      ),
    );
  }
}

/// Picks a photograph and opens it on the canvas. Both shelf actions land here.
Future<void> startStudy(
  BuildContext context,
  WidgetRef ref, {
  required bool fromCamera,
}) async {
  final picked = fromCamera ? await takePhoto() : await pickFromLibrary();
  if (picked == null || !context.mounted) return;

  final session = ref.read(sessionProvider);
  final image = await decodeImage(picked.bytes);
  session.startFreshStudy();
  session.imageKey = null;
  session.loadImage(image, picked.bytes);

  if (!context.mounted) return;
  if (MediaQuery.sizeOf(context).width < kDesktopBreakpoint) {
    await Navigator.of(
      context,
    ).push(NoTransitionRoute(builder: (_) => const CanvasScreen()));
  }
}

/// Loads a saved study's settings and its copied source image.
Future<void> openStudy(BuildContext context, WidgetRef ref, Study study) async {
  final session = ref.read(sessionProvider);
  final bytes = await ref.read(studiesProvider.notifier).imageBytes(study);
  if (bytes == null || !context.mounted) return;
  final image = await decodeImage(bytes);
  session.openStudy(study);
  session.loadImage(image, bytes, key: study.imageKey);

  if (!context.mounted) return;
  if (MediaQuery.sizeOf(context).width < kDesktopBreakpoint) {
    await Navigator.of(
      context,
    ).push(NoTransitionRoute(builder: (_) => const CanvasScreen()));
  }
}

/// The design has no page transitions; screens replace each other outright.
///
/// [heroDuration] gives a [Hero] room to fly — opening a study grows its shelf
/// thumbnail into the full-bleed canvas — while the page itself only fades, so
/// nothing slides.
class NoTransitionRoute<T> extends PageRoute<T> {
  NoTransitionRoute({required this.builder, this.heroDuration = Duration.zero});

  final WidgetBuilder builder;
  final Duration heroDuration;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => heroDuration;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => builder(context);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (heroDuration == Duration.zero) return child;
    // The canvas resolves in under the flying thumbnail, so the two arrive
    // together rather than the destination being visible from the first frame.
    return FadeTransition(
      opacity: CurvedAnimation(
        parent: animation,
        curve: const Interval(0.35, 1),
      ),
      child: child,
    );
  }
}

/// Ties a shelf thumbnail to the canvas it opens into.
String studyHeroTag(String studyId) => 'study-$studyId';

/// Long enough to read as growth rather than a cut.
const Duration kStudyOpenDuration = Duration(milliseconds: 420);
