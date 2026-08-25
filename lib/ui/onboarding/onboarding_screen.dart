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
  const OnboardingScreen({super.key, this.onDone});

  /// Set when the tour is embedded — the desktop shelf plays it in the pane
  /// beside the rail — so finishing hands control back instead of popping a
  /// route that is not there.
  final VoidCallback? onDone;

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

  /// The backdrop crossfade, in three acts. [_below] is the pass on screen.
  /// A step change mounts a second backdrop over it, invisible until its own
  /// pass has rendered ([_incomingSettled]), then fades it in. Once faded,
  /// [_below] adopts the same settings and the overlay is dropped only when
  /// the lower pass has caught up — so nothing ever cuts back.
  late StudySettings _below = _panels[0].settings;
  StudySettings? _incoming;
  bool _incomingSettled = false;
  bool _awaitingBelow = false;

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

  static const _fade = Duration(milliseconds: 320);

  void _finish() {
    ref.read(onboardingSeenProvider.notifier).markSeen();
    final onDone = widget.onDone;
    if (onDone != null) {
      onDone();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _next() {
    if (_step >= _panels.length - 1) {
      _finish();
      return;
    }
    setState(() {
      _step += 1;
      final settings = _panels[_step].settings;
      if (settings != _below) {
        _incoming = settings;
        _incomingSettled = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = DesignScale.of(context);
    final panel = _panels[_step];

    // The whole pane arrives on a fade — it appears inside the desktop
    // shelf as much as it owns a phone screen, and popping into existence
    // reads wrong in a pane.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      // Quicker than the content's slide, so the arrival is watched rather
      // than finished behind the fade.
      duration: const Duration(milliseconds: 200),
      curve: AskanceMotion.slide,
      builder: (context, opacity, child) =>
          Opacity(opacity: opacity, child: child!),
      child: ColoredBox(
        color: AskanceColors.ink,
        child: Stack(
          fit: StackFit.expand,
          children: [
            OnboardingBackdrop(
              key: const ValueKey('backdrop-below'),
              settings: _below,
              onSettled: (settings) {
                if (_awaitingBelow && settings == _below) {
                  setState(() {
                    _incoming = null;
                    _incomingSettled = false;
                    _awaitingBelow = false;
                  });
                }
              },
            ),
            if (_incoming case final incoming?)
              AnimatedOpacity(
                opacity: _incomingSettled ? 1 : 0,
                duration: _fade,
                curve: AskanceMotion.slide,
                onEnd: () {
                  if (_incomingSettled && _incoming != null) {
                    setState(() {
                      _below = _incoming!;
                      _awaitingBelow = true;
                    });
                  }
                },
                child: OnboardingBackdrop(
                  key: const ValueKey('backdrop-incoming'),
                  settings: incoming,
                  onSettled: (settings) {
                    if (settings == _incoming) {
                      setState(() => _incomingSettled = true);
                    }
                  },
                ),
              ),
            const OnboardingScrim(),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, viewport) => Align(
                  // Full width in the hand; capped and held to the left on a
                  // desk, where rules and a call to action stretched across
                  // the whole pane read wrong.
                  alignment: Alignment.topLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1000),
                    // The copy crosses the whole pane, once, from the right
                    // edge to its resting place; steps change with the
                    // quieter fade below.
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 1, end: 0),
                      duration: const Duration(milliseconds: 550),
                      curve: AskanceMotion.slide,
                      builder: (context, t, child) => Transform.translate(
                        offset: Offset(t * viewport.maxWidth, 0),
                        child: child!,
                      ),
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
                                      padding: EdgeInsets.symmetric(
                                        vertical: 12 * s,
                                      ),
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
                                // A quick, quiet crossfade between panels.
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 180),
                                  switchInCurve: AskanceMotion.slide,
                                  switchOutCurve: AskanceMotion.slide,
                                  layoutBuilder: (current, previous) => Stack(
                                    alignment: Alignment.bottomLeft,
                                    children: [...previous, ?current],
                                  ),
                                  child: Column(
                                    key: ValueKey(_step),
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                        style: AskanceText.onboardingTitle().by(
                                          s,
                                        ),
                                      ),
                                      SizedBox(height: 16 * s),
                                      ConstrainedBox(
                                        constraints: BoxConstraints(
                                          maxWidth: 250 * s,
                                        ),
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
                                  if (i < _panels.length - 1)
                                    SizedBox(width: 8 * s),
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
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
