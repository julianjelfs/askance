import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../../theme.dart';
import '../widgets/controls.dart';

/// Bottom-anchored: content sits at the bottom of the screen, not centred.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _step = 0;

  static const _panels = [
    (
      title: 'Value before colour.',
      body:
          'Askance flattens a photograph into a handful of values, so you can '
          'see the shapes light actually makes. The steps are spaced the way '
          'the eye reads them, not the way a camera measures them — so they '
          'line up with the value scale on your desk.',
      cta: 'Next',
    ),
    (
      title: 'Look askance.',
      body:
          'Hold the image to peek at the photo. Split it down the middle. '
          'Strip it back to edges and number every value.',
      cta: 'Next',
    ),
    (
      title: 'Grid when you want it.',
      body:
          'Square or diamond, as fine as you like — then get it out of the way '
          'with a single tap.',
      cta: 'Start a study',
    ),
  ];

  void _finish() {
    ref.read(onboardingSeenProvider.notifier).markSeen();
    Navigator.of(context).maybePop();
  }

  void _next() {
    if (_step < _panels.length - 1) {
      setState(() => _step++);
    } else {
      _finish();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = DesignScale.of(context);
    final panel = _panels[_step];

    return ColoredBox(
      color: AskanceColors.ink,
      child: SafeArea(
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
              const Spacer(),
              Container(
                width: 44 * s,
                height: kRule,
                color: AskanceColors.accent,
              ),
              SizedBox(height: 18 * s),
              Text(panel.title, style: AskanceText.onboardingTitle().by(s)),
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
              SizedBox(height: 28 * s),
              Row(
                children: [
                  for (var i = 0; i < _panels.length; i++) ...[
                    Expanded(
                      child: Container(
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
    );
  }
}
