import 'package:askance/ui/shelf/shelf_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Opening a study should look like its shelf thumbnail growing into the
/// canvas, so the route has to give the [Hero] room to fly.
class _Card extends StatelessWidget {
  const _Card();

  @override
  Widget build(BuildContext context) =>
      const ColoredBox(color: Color(0xFFEC3013));
}

void main() {
  const tag = 'study-a';
  const thumbnail = Size(120, 150);

  Widget harness({required Duration heroDuration}) => MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: GestureDetector(
            onTap: () => Navigator.of(context).push(
              NoTransitionRoute<void>(
                heroDuration: heroDuration,
                builder: (_) => const Hero(tag: tag, child: _Card()),
              ),
            ),
            child: SizedBox(
              width: thumbnail.width,
              height: thumbnail.height,
              child: const Hero(tag: tag, child: _Card()),
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('the thumbnail grows into the canvas rather than cutting', (
    tester,
  ) async {
    await tester.pumpWidget(harness(heroDuration: kStudyOpenDuration));
    final screen = tester.getSize(find.byType(MaterialApp));

    expect(tester.getSize(find.byType(_Card)), thumbnail);

    await tester.tap(find.byType(GestureDetector));
    await tester.pump(); // start the flight

    // Partway through there should be exactly one card on screen — the one in
    // flight — at a size between the thumbnail and the full screen.
    await tester.pump(kStudyOpenDuration ~/ 2);
    final midFlight = tester.getSize(find.byType(_Card));
    expect(
      midFlight.width,
      greaterThan(thumbnail.width),
      reason: 'should have grown past the thumbnail',
    );
    expect(
      midFlight.width,
      lessThan(screen.width),
      reason: 'should not have snapped straight to full screen',
    );

    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(_Card)), screen);
  });

  testWidgets('without a hero duration the screen simply replaces', (
    tester,
  ) async {
    await tester.pumpWidget(harness(heroDuration: Duration.zero));
    final screen = tester.getSize(find.byType(MaterialApp));

    await tester.tap(find.byType(GestureDetector));
    await tester.pump();
    await tester.pump();

    // Nothing to interpolate: it is already full size.
    expect(tester.getSize(find.byType(_Card)), screen);
  });
}
