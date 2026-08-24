import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/engine.dart';
import '../../engine/value_scale.dart';
import '../../model/study.dart';
import '../../state/providers.dart';
import '../../theme.dart';
import '../widgets/controls.dart';
import 'onboarding_backdrop.dart';

/// Bottom-anchored: content sits at the bottom of the screen, not centred.
///
/// Each panel is drawn over the engine doing the thing that panel describes —
/// the value map, then the split, then the grid — so the tour is the app
/// running rather than a picture of it.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

typedef _Panel = ({
  String title,
  String body,
  String cta,
  StudySettings settings,
});

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _step = 0;

  /// The panel waiting for the current one to get out of the way.
  ///
  /// Crossfading the copy meant both panels were legible at once and the two
  /// blocks of text sat on top of each other. One goes before the next
  /// arrives instead.
  int? _pending;

  static const _panels = <_Panel>[
    (
      title: 'Value before colour.',
      body:
          'Askance flattens a photograph into a handful of values, so you can '
          'see the shapes light actually makes. The steps are spaced the way '
          'the eye reads them, not the way a camera measures them — so they '
          'line up with the value scale on your desk.',
      cta: 'Next',
      settings: StudySettings(steps: 3, detail: 0.45),
    ),
    (
      title: 'Look askance.',
      body:
          'Hold the image to peek at the photo. Split it down the middle. '
          'Strip it back to edges, then block the values in, darkest first.',
      cta: 'Next',
      settings: StudySettings(
        steps: 4,
        detail: 0.45,
        mode: ViewMode.split,
        splitPosition: 0.42,
      ),
    ),
    (
      title: 'Spark your creativity.',
      body:
          'Random mode repaints the study in arbitrary colours of exactly the '
          'right values. Deal palette after palette — the picture holds '
          'together every time, because coherence lives in the values, not '
          'the colours. When one sparks something, paint it.',
      cta: 'Next',
      settings: StudySettings(
        steps: 5,
        detail: 0.45,
        mode: ViewMode.random,
        randomSeed: 7,
      ),
    ),
    (
      title: 'Grid when you want it.',
      body:
          'Square or diamond, as fine as you like — then get it out of the way '
          'with a single tap.',
      cta: 'Start a study',
      settings: StudySettings(
        steps: 3,
        detail: 0.45,
        scale: ValueScale.warm,
        grid: GridMode.square,
        gridDivisions: 4,
      ),
    ),
  ];

  /// Each half of the handover: out, then in.
  static const _fade = Duration(milliseconds: 170);

  void _finish() {
    ref.read(onboardingSeenProvider.notifier).markSeen();
    Navigator.of(context).maybePop();
  }

  void _next() {
    if (_pending != null) return;
    if (_step < _panels.length - 1) {
      setState(() => _pending = _step + 1);
    } else {
      _finish();
    }
  }

  /// Fired at the end of both halves; only the fade out has anything to do.
  void _onFaded() {
    final next = _pending;
    if (next == null) return;
    setState(() {
      _step = next;
      _pending = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = DesignScale.of(context);
    final panel = _panels[_step];

    return ColoredBox(
      color: AskanceColors.ink,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedSwitcher(
            duration: _fade * 2,
            switchInCurve: AskanceMotion.slide,
            switchOutCurve: AskanceMotion.slide,
            child: OnboardingBackdrop(
              key: ValueKey(_step),
              settings: panel.settings,
            ),
          ),
          const OnboardingScrim(),
          SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 18 * s),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 46 * s,
                    child: Row(
                      children: [
                        const Spacer(),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _finish,
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 12 * s),
                            child: Text(
                              'SKIP',
                              style: AskanceText.controlLabel(
                                10,
                                color: const Color(0x99F3F2F2),
                              ).by(s),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Takes the room left over and pins the copy to the bottom
                  // of it, scrolling only if a short screen leaves too little.
                  Expanded(
                    child: SingleChildScrollView(
                      reverse: true,
                      child: AnimatedOpacity(
                        opacity: _pending == null ? 1 : 0,
                        duration: _fade,
                        curve: AskanceMotion.slide,
                        onEnd: _onFaded,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 44 * s,
                              height: kRule,
                              color: AskanceColors.accent,
                            ),
                            SizedBox(height: 18 * s),
                            Text(
                              panel.title,
                              style: AskanceText.onboardingTitle().by(s),
                            ),
                            SizedBox(height: 16 * s),
                            ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: 250 * s),
                              child: Text(
                                panel.body,
                                style: AskanceText.body(
                                  14,
                                  color: const Color(0xB3F3F2F2),
                                ).by(s),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 28 * s),
                  Row(
                    children: [
                      for (var i = 0; i < _panels.length; i++) ...[
                        Expanded(
                          child: AnimatedContainer(
                            duration: AskanceMotion.chromeFade,
                            curve: AskanceMotion.slide,
                            height: kRule,
                            color: i <= _step
                                ? AskanceColors.accent
                                : const Color(0x40F3F2F2),
                          ),
                        ),
                        if (i < _panels.length - 1) SizedBox(width: 8 * s),
                      ],
                    ],
                  ),
                  SizedBox(height: 18 * s),
                  // The fill is the same red either side, so only the label
                  // reads as changing.
                  ActionButton(
                    label: panel.cta,
                    trailing: '→',
                    height: 56,
                    onPressed: _next,
                  ),
                  SizedBox(height: 18 * s),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
