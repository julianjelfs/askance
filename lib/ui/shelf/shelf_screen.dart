import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    // One shelf at every size: two columns in the hand, more across a
    // desk. There is no rail here — with no study open it would have
    // nothing true to say.
    final columns = isWideLayout(context)
        ? (MediaQuery.sizeOf(context).width ~/ 280).clamp(3, 6)
        : 2;

    final grid = SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        18 * s,
        16 * s,
        18 * s,
        24 * s + MediaQuery.paddingOf(context).bottom,
      ),
      // Pinned left: a grid narrower than the screen otherwise floats in
      // the middle of it.
      child: Align(
        alignment: Alignment.topLeft,
        child: ShelfGrid(
          studies: studies,
          columns: columns,
          onOpen: (study) => openStudy(context, ref, study),
          onNew: () => showImportSheet(context, ref),
        ),
      ),
    );

    return ColoredBox(
      color: AskanceColors.ground,
      child: SafeArea(
        bottom: false,
        child: isWideLayout(context)
            // On a desk the ways in live in a rail, so a first-run shelf is
            // an invitation rather than a blank sheet; the phone keeps its
            // header and the + sheet.
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 284,
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
            : Column(
                children: [
                  _TitleRow(),
                  Expanded(child: grid),
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
    this.onNew,
  });

  final List<Study> studies;
  final int columns;
  final void Function(Study) onOpen;

  /// What the + in the empty slot does; null hides it.
  final VoidCallback? onNew;

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
            // The first frame on Android can arrive with zero width, and a
            // gap subtracted from nothing is a negative cell, which is a
            // constraints assertion rather than an empty shelf.
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
                SizedBox(
                  width: cellWidth,
                  child: EmptySlotCard(onNew: onNew),
                ),
              ],
            );
          },
        ),
      ],
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
    builder: (context, constraints) => Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: AskanceColors.ink),
        // The portrait keeps to the lower half of the rail, whole, so what
        // surfaces under the buttons is a head rendered as a value map rather
        // than an anonymous midriff; its top edge dissolves into the ink the
        // words sit on.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: constraints.maxHeight * 0.52,
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
                    stops: [0, 0.5, 1],
                    colors: [
                      AskanceColors.ink,
                      Color(0x59201E1D),
                      Color(0x26201E1D),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const AskanceMark(size: 22),
                  const SizedBox(width: 9),
                  Text(
                    'Askance',
                    style: AskanceText.screenTitle(
                      color: AskanceColors.ground,
                    ).copyWith(fontSize: 22, letterSpacing: 22 * -0.02),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Flattens a photograph into a handful of values, so you can '
                'see the shapes light actually makes. Start with a photograph:',
                style: AskanceText.body(13, color: AskanceColors.mutedDark),
              ),
              const SizedBox(height: 18),
              ActionButton(
                label: 'New study from photos',
                trailing: '→',
                height: 40,
                fontSize: 12,
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
                  height: 40,
                  fontSize: 12,
                  solid: false,
                  onDark: true,
                  onPressed: () {
                    onAction();
                    startStudy(context, ref, fromCamera: true);
                  },
                ),
              ],
              const SizedBox(height: 8),
              ActionButton(
                label: 'Scan from QR code',
                trailing: '→',
                height: 40,
                fontSize: 12,
                solid: false,
                onDark: true,
                onPressed: () {
                  onAction();
                  Navigator.of(context).push(
                    NoTransitionRoute(builder: (_) => const QrScanScreen()),
                  );
                },
              ),
              const Spacer(),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onHowItWorks,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    'HOW IT WORKS',
                    style: AskanceText.controlLabel(
                      10,
                      tracking: 0.06,
                      color: AskanceColors.mutedDark,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _TitleRow extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = DesignScale.of(context);

    Widget headerButton(String glyph, VoidCallback onTap) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 28 * s,
        height: 28 * s,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(
            color: AskanceColors.dividerLight,
            width: kRuleThin,
          ),
        ),
        child: Text(
          glyph,
          style: AskanceText.button(13, color: AskanceColors.ink).by(s),
        ),
      ),
    );

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 18 * s),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AskanceColors.dividerLight,
            width: kRuleThin,
          ),
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
            headerButton('+', () => showImportSheet(context, ref)),
            SizedBox(width: 8 * s),
            headerButton(
              '?',
              () => Navigator.of(context).push(
                NoTransitionRoute(builder: (_) => const OnboardingScreen()),
              ),
            ),
          ],
        ),
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
    barrierColor: const Color(0x99201E1D),
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
          color: AskanceColors.ink,
          foregroundDecoration: BoxDecoration(
            border: wide
                ? Border.all(color: AskanceColors.accent, width: kRule)
                : const Border(
                    top: BorderSide(color: AskanceColors.accent, width: kRule),
                  ),
          ),
          padding: EdgeInsets.fromLTRB(
            18 * s,
            18 * s,
            18 * s,
            18 * s + (wide ? 0 : MediaQuery.paddingOf(context).bottom),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ActionButton(
                label: 'New study from photos',
                trailing: '→',
                onPressed: () => closeThen(
                  () => startStudy(context, ref, fromCamera: false),
                ),
              ),
              // Without a camera, "open a file" would be this same
              // picker wearing a different label — one button, not two.
              if (canTakePhoto) ...[
                SizedBox(height: 10 * s),
                ActionButton(
                  label: 'Take a photo',
                  trailing: '→',
                  solid: false,
                  onDark: true,
                  onPressed: () => closeThen(
                    () => startStudy(context, ref, fromCamera: true),
                  ),
                ),
              ],
              SizedBox(height: 10 * s),
              ActionButton(
                label: 'Scan from QR code',
                trailing: '→',
                solid: false,
                onDark: true,
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
