import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'state/providers.dart';
import 'theme.dart';
import 'ui/layout.dart';
import 'ui/onboarding/onboarding_screen.dart';
import 'ui/shelf/shelf_screen.dart';

class AskanceApp extends StatelessWidget {
  const AskanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Askance',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: AskanceText.family,
        scaffoldBackgroundColor: AskanceColors.gesso,
        // No ripples and no elevation: pressed states are drawn by the controls.
        splashFactory: NoSplash.splashFactory,
        highlightColor: const Color(0x00000000),
        textSelectionTheme: const TextSelectionThemeData(
          cursorColor: AskanceColors.accent,
          selectionColor: Color(0x40E2471F),
          selectionHandleColor: AskanceColors.accent,
        ),
      ),
      // Wraps the Navigator rather than just the home screen, so pushed routes
      // and the share sheet inherit the same scale and text defaults.
      builder: (context, child) => DesignScale(
        // The desktop layout was drawn at 1x with a fixed rail; only the
        // phone screens scale proportionally.
        factor: isWideLayout(context)
            ? 1
            : DesignScale.forWidth(MediaQuery.sizeOf(context).width),
        child: DefaultTextStyle(
          style: AskanceText.body(14),
          child: Material(type: MaterialType.transparency, child: child!),
        ),
      ),
      home: const _Root(),
    );
  }
}

class _Root extends ConsumerWidget {
  const _Root();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seen = ref.watch(onboardingSeenProvider);

    return switch (seen) {
      // In the hand the tour owns the screen; on a desk the shelf embeds it
      // beside the rail.
      AsyncData(value: false) when !isWideLayout(context) =>
        const OnboardingScreen(),
      AsyncData() => const ShelfScreen(),
      _ => const ColoredBox(color: AskanceColors.gesso),
    };
  }
}
