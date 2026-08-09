import 'dart:ui' as ui;

import 'package:askance/engine/engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// How long one blur update takes in each mode, at the zoom levels a pinch
/// passes through. A pinch redraws every frame while the blur is still being
/// rendered, and the shader stretches whatever blur it has across the rect
/// being drawn now — so this latency is visible as distortion, not just as
/// softness.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('blur latency through a pinch', (tester) async {
    final data = await rootBundle.load('assets/onboarding-portrait.jpg');
    final source = (await (await ui.instantiateImageCodec(
      data.buffer.asUint8List(),
    )).getNextFrame()).image;
    const output = Size(1080, 2000);

    Future<int> median(Smoothing smoothing, double zoom, double detail) async {
      final view = ViewTransform(zoom: zoom);
      final samples = <int>[];
      for (var i = 0; i < 12; i++) {
        final clock = Stopwatch()..start();
        final image = await renderBlurredSource(
          source: source, outputPx: output, detail: detail,
          view: view, smoothing: smoothing,
        );
        clock.stop();
        if (i >= 4) samples.add(clock.elapsedMicroseconds);
        image.dispose();
      }
      samples.sort();
      return samples[samples.length ~/ 2] ~/ 1000;
    }

    for (final detail in [0.3, 0.6]) {
      for (final zoom in [1.0, 1.6, 2.5]) {
        final s = await median(Smoothing.gaussian, zoom, detail);
        final k = await median(Smoothing.kuwahara, zoom, detail);
        debugPrint('[lat] detail=${(detail * 100).round()} zoom=$zoom '
            'SMOOTH ${s}ms  ROUGH ${k}ms');
      }
    }
    source.dispose();
  }, timeout: const Timeout(Duration(minutes: 15)));
}
