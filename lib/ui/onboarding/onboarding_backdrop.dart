import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/blur_pass.dart';
import '../../engine/deferred_disposer.dart';
import '../../engine/engine.dart';
import '../../engine/value_painter.dart';
import '../../model/study.dart';
import '../../state/providers.dart';
import '../../theme.dart';

/// The photograph the onboarding panels are drawn over, decoded once.
final onboardingImageProvider = FutureProvider<ui.Image?>((ref) async {
  try {
    final data = await rootBundle.load('assets/onboarding-portrait.jpg');
    final image = await decodeImage(data.buffer.asUint8List());
    ref.onDispose(image.dispose);
    return image;
  } catch (e) {
    // Onboarding without a backdrop is still perfectly readable.
    return null;
  }
});

/// Runs the real engine behind the onboarding copy, so each panel shows the
/// thing it is describing rather than illustrating it.
///
/// Held behind a scrim that goes to solid ink at the bottom, where the title,
/// body and call to action sit.
class OnboardingBackdrop extends ConsumerStatefulWidget {
  const OnboardingBackdrop({super.key, required this.settings});

  final StudySettings settings;

  @override
  ConsumerState<OnboardingBackdrop> createState() => _OnboardingBackdropState();
}

class _OnboardingBackdropState extends ConsumerState<OnboardingBackdrop> {
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
    final image = ref.watch(onboardingImageProvider).valueOrNull;
    final shader = ref.watch(shaderProvider).valueOrNull;
    if (image == null || shader == null) {
      return const ColoredBox(color: AskanceColors.ink);
    }

    final dpr = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (size.isEmpty) return const ColoredBox(color: AskanceColors.ink);

        // A study is shown whole; a backdrop is not a study. Fill the screen,
        // or it hangs in the middle as a panel.
        final view = coveringView(
          const ViewTransform(),
          Size(image.width.toDouble(), image.height.toDouble()),
          size,
        );

        _blur.request(
          source: image,
          outputPx: size * dpr,
          detail: widget.settings.detail,
          view: view,
          smoothing: widget.settings.smoothing,
        );

        return ListenableBuilder(
          listenable: _blur,
          builder: (context, _) => CustomPaint(
            size: Size.infinite,
            painter: ValuePainter(
              shader: shader,
              source: image,
              blurred: _blur.image,
              settings: widget.settings,
              view: view,
              devicePixelRatio: dpr,
              peeking: false,
              splitPosition: widget.settings.splitPosition,
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

/// Darkens the backdrop into the ink ground the copy needs to sit on.
class OnboardingScrim extends StatelessWidget {
  const OnboardingScrim({super.key});

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0x59201E1D),
          Color(0xCC201E1D),
          AskanceColors.ink,
          AskanceColors.ink,
        ],
        stops: [0, 0.42, 0.68, 1],
      ),
    ),
    child: SizedBox.expand(),
  );
}
