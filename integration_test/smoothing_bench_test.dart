import 'dart:ui' as ui;

import 'package:askance/engine/engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// What each way of finding the shapes actually costs on the GPU in your hand.
///
/// The equivalent host test rasterises on the CPU, so its timings are off by
/// orders of magnitude and in the wrong direction. This runs in the real app.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('time every smoothing pass at phone resolution', (tester) async {
    final data = await rootBundle.load('assets/onboarding-portrait.jpg');
    final source = (await (await ui.instantiateImageCodec(
      data.buffer.asUint8List(),
    )).getNextFrame()).image;

    // A full-screen frame at real device pixels.
    const output = Size(1080, 2000);
    const view = ViewTransform();

    Future<int> time(
      Smoothing smoothing,
      double detail,
      double radius,
    ) async {
      // One to warm the shader compile and the texture upload, then measure.
      for (var i = 0; i < 2; i++) {
        final image = await renderBlurredSource(
          source: source,
          outputPx: output,
          detail: detail,
          view: view,
          smoothing: smoothing,
          quadrantRadius: radius,
        );
        image.dispose();
      }
      final clock = Stopwatch()..start();
      const runs = 3;
      for (var i = 0; i < runs; i++) {
        final image = await renderBlurredSource(
          source: source,
          outputPx: output,
          detail: detail,
          view: view,
          smoothing: smoothing,
          quadrantRadius: radius,
        );
        image.dispose();
      }
      return clock.elapsedMilliseconds ~/ runs;
    }

    for (final detail in [0.2, 0.55]) {
      final results = <String, int>{
        'SMOOTH': await time(Smoothing.gaussian, detail, kKuwaharaRadius),
        'ROUGH r=4': await time(Smoothing.kuwahara, detail, 4),
        'ROUGH r=8': await time(Smoothing.kuwahara, detail, 8),
        'ROUGH r=12': await time(Smoothing.kuwahara, detail, 12),
        'FULL': await time(Smoothing.kuwaharaFull, detail, kKuwaharaRadius),
      };
      results.forEach((name, ms) {
        debugPrint('[bench] detail=${(detail * 100).round()} '
            '${name.padRight(11)} ${ms}ms');
      });
    }
    source.dispose();
  }, timeout: const Timeout(Duration(minutes: 15)));
}
