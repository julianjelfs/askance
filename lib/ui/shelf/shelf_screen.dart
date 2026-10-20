import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../build_stamp.dart';
import '../../model/study.dart';
import '../../state/providers.dart';
import '../../theme.dart';
import '../onboarding/onboarding_backdrop.dart';
import '../onboarding/onboarding_screen.dart';
import '../layout.dart';
import '../pick_image.dart';
import '../study_screen.dart';
import '../widgets/askance_mark.dart';
import '../widgets/controls.dart';
import '../widgets/glyphs.dart';
import 'qr_scan_screen.dart';
import 'study_card.dart';

/// The shelf, and the launch screen: what you have made, and two ways to start
/// something new.
class ShelfScreen extends ConsumerStatefulWidget {
  const ShelfScreen({super.key});

  @override
  ConsumerState<ShelfScreen> createState() => _ShelfScreenState();
}

class _ShelfScreenState extends ConsumerState<ShelfScreen> {
  /// The tour, replayed from the rail's HOW IT WORKS. First-run showing is
  /// driven by the seen flag instead, so it survives a rebuild.
  bool _replayingTour = false;

  /// Starting a study while the tour is playing is the strongest possible
  /// "I've got it": the tour stops, and stays stopped for the return.
  void _dismissTour() {
    if (_replayingTour) setState(() => _replayingTour = false);
    final seen = ref.read(onboardingSeenProvider).valueOrNull ?? true;
    if (!seen) ref.read(onboardingSeenProvider.notifier).markSeen();
  }

  @override
  Widget build(BuildContext context) {
    final s = DesignScale.of(context);
    final studies = ref.watch(studiesProvider).valueOrNull ?? const <Study>[];
    final wide = isWideLayout(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    // One card per row in the hand; across a desk, as many columns of them
    // as fit.
    final columns = wide
        ? (MediaQuery.sizeOf(context).width ~/ 420).clamp(1, 4)
        : 1;

    final grid = SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        14 * s,
        wide ? 24 : 8 * s,
        14 * s,
        // On a phone the ways in sit over the end of the list.
        (wide ? 24 : 150 * s) + bottom,
      ),
      child: ShelfGrid(
        studies: studies,
        columns: columns,
        onOpen: (study) => openStudy(context, ref, study),
        onNew: () => showImportSheet(context, ref),
      ),
    );

    return ColoredBox(
      color: AskanceColors.gesso,
      child: SafeArea(
        bottom: false,
        child: wide
            // On a desk the ways in live in a rail, so a first-run shelf is
            // an invitation rather than a blank sheet.
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 320,
                    child: _ShelfRail(
                      onHowItWorks: () => setState(() => _replayingTour = true),
                      onAction: _dismissTour,
                    ),
                  ),
                  Expanded(
                    // The tour plays in the shelf's own pane, rail still
                    // standing: first run, and on request.
                    child:
                        _replayingTour ||
                            !(ref.watch(onboardingSeenProvider).valueOrNull ??
                                true)
                        ? OnboardingScreen(
                            onDone: () =>
                                setState(() => _replayingTour = false),
                          )
                        : Align(alignment: Alignment.topLeft, child: grid),
                  ),
                ],
              )
            : Stack(
                children: [
                  Column(
                    children: [
                      _TitleRow(count: studies.length),
                      Expanded(child: grid),
                    ],
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _WaysIn(bottomInset: bottom),
                  ),
                ],
              ),
      ),
    );
  }
}

/// The card grid, shared by the phone shelf and the desktop shelf, which
/// differ only in column count.
class ShelfGrid extends ConsumerWidget {
  const ShelfGrid({
    super.key,
    required this.studies,
    required this.columns,
    required this.onOpen,
    this.onNew,
  });

  final List<Study> studies;
  final int columns;
  final void Function(Study) onOpen;

  /// What tapping the empty shelf does; null leaves it inert.
  final VoidCallback? onNew;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = DesignScale.of(context);
    final gap = 10 * s;

    if (studies.isEmpty) return EmptySlotCard(onNew: onNew);

    return LayoutBuilder(
      builder: (context, constraints) {
        // The first frame on Android can arrive with zero width, and a gap
        // subtracted from nothing is a negative cell, which is a constraints
        // assertion rather than an empty shelf.
        final cellWidth =
            ((constraints.maxWidth - gap * (columns - 1)) / columns).clamp(
              0.0,
              double.infinity,
            );
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
          ],
        );
      },
    );
  }
}

/// The phone's ways in, over the foot of the list: a new study from a
/// photograph, the camera, and a study sent from another device.
class _WaysIn extends ConsumerWidget {
  const _WaysIn({required this.bottomInset});

  final double bottomInset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = DesignScale.of(context);
    return Container(
      padding: EdgeInsets.fromLTRB(
        14 * s,
        28 * s,
        14 * s,
        10 * s + bottomInset,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0, 0.3],
          colors: [Color(0x00F3F1EC), AskanceColors.gesso],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: ActionButton(
                  label: 'New study from a photo',
                  trailing: '→',
                  height: 56,
                  fontSize: 16.5,
                  onPressed: () => startStudy(context, ref, fromCamera: false),
                ),
              ),
              // Without a camera, "open a file" would be this same picker
              // wearing a different label — one button, not two.
              if (canTakePhoto) ...[
                SizedBox(width: 10 * s),
                Semantics(
                  button: true,
                  label: 'Take a photo',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => startStudy(context, ref, fromCamera: true),
                    child: Container(
                      width: 56 * s,
                      height: 56 * s,
                      decoration: BoxDecoration(
                        color: AskanceColors.graphite,
                        borderRadius: BorderRadius.circular(
                          AskanceRadius.button * s,
                        ),
                      ),
                      child: Center(
                        child: GlyphIcon(
                          Glyph.camera,
                          size: 26 * s,
                          color: AskanceColors.gesso,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(
              context,
            ).push(NoTransitionRoute(builder: (_) => const QrScanScreen())),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 12 * s),
              child: Text(
                'Receive a study from another device',
                textAlign: TextAlign.center,
                style: AskanceText.body(14, color: AskanceColors.muted).by(s),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The desktop shelf's left rail: the brand, a line of orientation, and the
/// ways to begin — over the sample portrait run through the real engine, so
/// the first thing a new user sees is the thing the app does.
class _ShelfRail extends ConsumerWidget {
  const _ShelfRail({required this.onHowItWorks, required this.onAction});

  final VoidCallback onHowItWorks;

  /// Fired before any of the rail's ways in: leaving the shelf cancels a
  /// playing tour.
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) => LayoutBuilder(
    builder: (context, constraints) => DecoratedBox(
      // Over the portrait too, so the rail keeps its edge all the way down.
      position: DecorationPosition.foreground,
      decoration: const BoxDecoration(
        border: Border(
          right: BorderSide(color: AskanceColors.rule, width: kRule),
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: AskanceColors.gesso),
          // The portrait keeps to the lower half of the rail, whole, so what
          // surfaces under the buttons is a head rendered as a value map
          // rather than an anonymous midriff; its top edge dissolves into the
          // gesso the words sit on.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: constraints.maxHeight * 0.48,
            child: const Stack(
              fit: StackFit.expand,
              children: [
                OnboardingBackdrop(
                  settings: StudySettings(steps: 3, detail: 0.45),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0, 0.45, 1],
                      colors: [
                        AskanceColors.gesso,
                        Color(0x40F3F1EC),
                        Color(0x00F3F1EC),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const AskanceMark(size: 26),
                    const SizedBox(width: 10),
                    Text('Askance', style: AskanceText.display(28)),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  'Flattens a photograph into a handful of values, so you can '
                  'see the shapes light actually makes.',
                  style: AskanceText.body(14.5, color: AskanceColors.muted),
                ),
                const SizedBox(height: 20),
                ActionButton(
                  label: 'New study from a photo',
                  trailing: '→',
                  onPressed: () {
                    onAction();
                    startStudy(context, ref, fromCamera: false);
                  },
                ),
                if (canTakePhoto) ...[
                  const SizedBox(height: 8),
                  ActionButton(
                    label: 'Take a photo',
                    trailing: '→',
                    solid: false,
                    onPressed: () {
                      onAction();
                      startStudy(context, ref, fromCamera: true);
                    },
                  ),
                ],
                const SizedBox(height: 8),
                ActionButton(
                  label: 'Receive from another device',
                  trailing: '→',
                  solid: false,
                  onPressed: () {
                    onAction();
                    Navigator.of(context).push(
                      NoTransitionRoute(builder: (_) => const QrScanScreen()),
                    );
                  },
                ),
                const Spacer(),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onHowItWorks,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text(
                            'How it works',
                            style: AskanceText.label(
                              14,
                              color: AskanceColors.gesso,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Text(
                      kBuildStamp,
                      style: AskanceText.caption(
                        10,
                        color: const Color(0x99F3F1EC),
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

class _TitleRow extends ConsumerWidget {
  const _TitleRow({required this.count});

  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = DesignScale.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20 * s, 16 * s, 14 * s, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AskanceMark(size: 28 * s),
              SizedBox(width: 10 * s),
              Expanded(
                child: Text('Askance', style: AskanceText.display(30).by(s)),
              ),
              Semantics(
                button: true,
                label: 'How Askance works',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).push(
                    NoTransitionRoute(builder: (_) => const OnboardingScreen()),
                  ),
                  child: Container(
                    width: 40 * s,
                    height: 40 * s,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AskanceColors.graphite,
                        width: kRuleStrong,
                      ),
                    ),
                    child: Text('?', style: AskanceText.title(17).by(s)),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 22 * s),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text('Studies', style: AskanceText.label(15.5).by(s)),
              ),
              if (count > 0)
                Text(
                  '$count on the shelf',
                  style: AskanceText.caption(13).by(s),
                ),
            ],
          ),
          SizedBox(height: 10 * s),
        ],
      ),
    );
  }
}

/// The ways in, from the + in the header and the empty slot alike: a bottom
/// sheet in the hand, a centred dialog on a desk, so the shelf itself keeps
/// the whole screen.
Future<void> showImportSheet(BuildContext context, WidgetRef ref) {
  final wide = isWideLayout(context);
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Start a study',
    barrierColor: const Color(0x991C1B1A),
    transitionDuration: AskanceMotion.sheetSlide,
    pageBuilder: (context, _, _) => const SizedBox.shrink(),
    transitionBuilder: (sheetContext, animation, _, _) {
      final s = DesignScale.of(sheetContext);
      final curved = CurvedAnimation(
        parent: animation,
        curve: AskanceMotion.slide,
      );

      // Actions run against the shelf's context: the sheet pops first, and
      // its own context dies with it.
      void closeThen(void Function() action) {
        Navigator.of(sheetContext).pop();
        action();
      }

      Widget presented(Widget panel) => wide
          ? Center(
              child: FadeTransition(
                opacity: curved,
                child: ScaleTransition(
                  scale: Tween(begin: 0.98, end: 1.0).animate(curved),
                  child: SizedBox(width: 360, child: panel),
                ),
              ),
            )
          : Align(
              alignment: Alignment.bottomCenter,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, 1),
                  end: Offset.zero,
                ).animate(curved),
                child: panel,
              ),
            );

      return presented(
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AskanceColors.gesso,
            borderRadius: wide
                ? BorderRadius.circular(AskanceRadius.sheet)
                : BorderRadius.vertical(
                    top: Radius.circular(AskanceRadius.sheet * s),
                  ),
          ),
          padding: EdgeInsets.fromLTRB(
            16 * s,
            20 * s,
            16 * s,
            16 * s + (wide ? 0 : MediaQuery.paddingOf(context).bottom),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(4 * s, 0, 4 * s, 14 * s),
                child: Text(
                  'Start a study',
                  style: AskanceText.heading(22).by(s),
                ),
              ),
              ActionButton(
                label: 'New study from a photo',
                trailing: '→',
                onPressed: () => closeThen(
                  () => startStudy(context, ref, fromCamera: false),
                ),
              ),
              // Without a camera, "open a file" would be this same
              // picker wearing a different label — one button, not two.
              if (canTakePhoto) ...[
                SizedBox(height: 8 * s),
                ActionButton(
                  label: 'Take a photo',
                  trailing: '→',
                  solid: false,
                  onPressed: () => closeThen(
                    () => startStudy(context, ref, fromCamera: true),
                  ),
                ),
              ],
              SizedBox(height: 8 * s),
              ActionButton(
                label: 'Receive from another device',
                trailing: '→',
                solid: false,
                onPressed: () => closeThen(
                  () => Navigator.of(context).push(
                    NoTransitionRoute(builder: (_) => const QrScanScreen()),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
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
  session.loadImage(image, picked.bytes);
  // Straight onto the shelf: with nothing gated there is no keep step, and a
  // photograph you opened should already be safe when you look up.
  await ref.read(studiesProvider.notifier).keep(session);

  if (!context.mounted) return;
  await Navigator.of(
    context,
  ).push(NoTransitionRoute(builder: (_) => const StudyScreen()));
}

/// Loads a saved study's settings and its copied source image.
Future<void> openStudy(BuildContext context, WidgetRef ref, Study study) async {
  final session = ref.read(sessionProvider);
  final bytes = await ref.read(studiesProvider.notifier).imageBytes(study);
  if (bytes == null || !context.mounted) return;
  final image = await decodeImage(bytes);
  session.openStudy(study);
  // resetView belongs to a fresh pick; here it would wipe the restored zoom.
  session.loadImage(image, bytes, key: study.imageKey, resetView: false);

  if (!context.mounted) return;
  final media = MediaQuery.of(context);
  // Render the pass before the push, not during it. The canvas is full
  // bleed, so its output is the screen; without this the flight opens on the
  // untouched photograph and flips to the value map partway across.
  await session.warmBlur(media.size * media.devicePixelRatio);
  if (!context.mounted) return;
  await Navigator.of(context).push(studyRoute());
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

/// The one route in the app that animates: opening a study grows its card into
/// the canvas, and going back shrinks it home again.
///
/// The duration lives here rather than at the call site because a push that
/// forgets it leaves the Hero nothing to animate over, and the result is not a
/// fast transition but no transition at all.
NoTransitionRoute<void> studyRoute() => NoTransitionRoute<void>(
  builder: (_) => const StudyScreen(),
  heroDuration: kStudyOpenDuration,
);

/// Long enough to read as growth rather than a cut, short enough not to make
/// you wait for it.
const Duration kStudyOpenDuration = Duration(milliseconds: 280);
