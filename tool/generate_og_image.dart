// Generates the link-preview card from the onboarding
// portrait: the photograph on the left, the same crop as a four-value map on
// the right.
//
// Run with:
//   flutter test tool/generate_og_image.dart
//
// A test file for the same reason as generate_icons.dart: it is the least
// ceremonious way to get a real dart:ui with a rasteriser attached. Both
// halves come out of renderExport, the path the app's own exports take, so
// the card shows exactly what the app does rather than an illustration of it.
// `make og-image` runs this and then compresses the PNG to the JPEG the page
// links to.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:askance/engine/engine.dart';
import 'package:askance/engine/export.dart';
import 'package:askance/model/study.dart';
import 'package:askance/state/providers.dart';
import 'package:askance/theme.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// What Open Graph consumers expect; anything else is cropped by someone.
const _card = Size(1200, 630);

/// A crop of the portrait with each half's shape, 600 × 630, hair to collar.
/// Fractions of the 900 × 1350 source.
const _crop = Rect.fromLTRB(0, 0.089, 1, 0.789);

/// The rule between the halves, in gesso.
const _rule = 4.0;

void main() {
  test('generate og image', () async {
    final bytes = File('assets/onboarding-portrait.jpg').readAsBytesSync();
    final source = await decodeImage(bytes);
    final shader = await ValueShader.load();

    Future<ui.Image> half(StudySettings settings) async {
      final png = await renderExport(
        shader: shader,
        source: source,
        settings: settings,
        view: const ViewTransform(),
        target: ExportSize.screen,
        splitPosition: settings.splitPosition,
      );
      return decodeImage(png!);
    }

    // PHOTO shows the photograph through the detail blur; at full detail it
    // is the photograph as shot.
    final photo = await half(
      const StudySettings(mode: ViewMode.photo, detail: 1, crop: _crop),
    );
    final values = await half(
      const StudySettings(steps: 4, detail: 0.45, crop: _crop),
    );

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Offset.zero & _card);
    final paint = Paint()..filterQuality = FilterQuality.high;
    canvas.drawRect(Offset.zero & _card, Paint()..color = AskanceColors.gesso);
    final halfWidth = (_card.width - _rule) / 2;
    for (final (i, image) in [photo, values].indexed) {
      final dst = Rect.fromLTWH(
        i * (halfWidth + _rule),
        0,
        halfWidth,
        _card.height,
      );
      final src =
          Offset.zero & Size(image.width.toDouble(), image.height.toDouble());
      // Both halves fill their slot; the crop already has the slot's shape,
      // so the cover is a near-identity scale rather than a second crop.
      final fitted = applyBoxFit(BoxFit.cover, src.size, dst.size);
      canvas.drawImageRect(
        image,
        Alignment.center.inscribe(fitted.source, src),
        dst,
        paint,
      );
    }

    final card = await recorder.endRecording().toImage(
      _card.width.toInt(),
      _card.height.toInt(),
    );
    final out = await card.toByteData(format: ui.ImageByteFormat.png);
    File('build/og-image.png').writeAsBytesSync(out!.buffer.asUint8List());
    // ignore: avoid_print
    print('wrote build/og-image.png');
  });
}
