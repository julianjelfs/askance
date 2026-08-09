// Generates every launcher icon from the mark in design/logo/.
//
// Run with:
//   flutter test tool/generate_icons.dart
//
// It is a test file only because that is the least ceremonious way to get a
// real dart:ui with a rasteriser attached. Nothing here asserts anything; it
// writes PNGs and prints what it wrote.
//
// The artwork is redrawn rather than traced from the SVG: it is a circle, a
// vertical gradient, three bands and a rule, so painting it with the same
// engine the app uses keeps the colours exact and gives proper antialiasing at
// every size.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:askance/ui/widgets/askance_mark.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

// The ground behind the mark; the mark itself comes from lib/, so the icons
// and the app header cannot drift apart.
const _ink = Color(0xFF201E1D);

/// Disc diameter as a fraction of the frame, from the source SVG: r 332 of 1024.
const _sourceDiscFraction = 664 / 1024;

/// Below this the source proportions stop reading and the disc is scaled up.
/// A 16px favicon drawn at the source ratio is a 10px disc carrying three
/// bands and a hairline; it turns to mush.
const _opticalFloor = 120.0;
const _opticalMaxDiscFraction = 0.80;

double _discFractionFor(double size) {
  if (size >= _opticalFloor) return _sourceDiscFraction;
  final t = ((size - 16) / (_opticalFloor - 16)).clamp(0.0, 1.0);
  return _opticalMaxDiscFraction +
      (_sourceDiscFraction - _opticalMaxDiscFraction) * t;
}

/// How the frame behind the disc is treated.
enum Ground {
  /// Edge-to-edge ink. iOS, Android's legacy icon and the web icons.
  fullBleed,

  /// Ink in a rounded square with a transparent margin, the macOS convention.
  roundedSquare,

  /// Nothing behind the disc at all, for an Android adaptive foreground.
  none,
}

/// macOS draws its icon into 824 of a 1024 canvas, with a corner radius of
/// about 22.5% of that content square.
const _macContentFraction = 824 / 1024;
const _macCornerFraction = 0.225;

/// The Android adaptive safe zone is a 66dp circle inside a 108dp layer.
/// Staying a little inside it survives the more aggressive launcher masks.
const _adaptiveDiscFraction = 60 / 108;

void _paintIcon(
  Canvas canvas,
  double size, {
  required Ground ground,
  double? discFractionOverride,
}) {
  final rect = Rect.fromLTWH(0, 0, size, size);

  switch (ground) {
    case Ground.fullBleed:
      canvas.drawRect(rect, Paint()..color = _ink);
    case Ground.roundedSquare:
      final content = size * _macContentFraction;
      final inset = (size - content) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(inset, inset, content, content),
          Radius.circular(content * _macCornerFraction),
        ),
        Paint()..color = _ink,
      );
    case Ground.none:
      break;
  }

  final discFraction = discFractionOverride ?? _discFractionFor(size);
  paintAskanceMark(
    canvas,
    Rect.fromCircle(
      center: Offset(size / 2, size / 2),
      radius: size * discFraction / 2,
    ),
  );
}

Future<void> _write(
  String path,
  double size, {
  required Ground ground,
  double? discFractionOverride,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size, size));
  _paintIcon(
    canvas,
    size,
    ground: ground,
    discFractionOverride: discFractionOverride,
  );
  final picture = recorder.endRecording();
  final side = size.round();
  final image = await picture.toImage(side, side);
  picture.dispose();
  final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();

  // Anything with a transparent margin has to keep its alpha; everything else
  // sheds it. iOS in particular rejects an app icon that has an alpha channel
  // at all, even one that is opaque throughout, and dart:ui's PNG encoder
  // always writes RGBA.
  final keepAlpha = ground != Ground.fullBleed;
  final png = _encodePng(
    raw!.buffer.asUint8List(),
    side,
    side,
    alpha: keepAlpha,
  );

  final file = File(path);
  file.parent.createSync(recursive: true);
  await file.writeAsBytes(png, flush: true);
  // ignore: avoid_print
  print(
    '  ${side.toString().padLeft(4)}px  '
    '${keepAlpha ? 'RGBA' : ' RGB'}  $path',
  );
}

/// A minimal PNG encoder, so the colour type is ours to choose.
Uint8List _encodePng(
  Uint8List rgba,
  int width,
  int height, {
  required bool alpha,
}) {
  final channels = alpha ? 4 : 3;
  // Each scanline is prefixed with its filter type; 0 means none.
  final raw = Uint8List(height * (1 + width * channels));
  var out = 0;
  for (var y = 0; y < height; y++) {
    raw[out++] = 0;
    var src = y * width * 4;
    for (var x = 0; x < width; x++) {
      raw[out++] = rgba[src];
      raw[out++] = rgba[src + 1];
      raw[out++] = rgba[src + 2];
      if (alpha) raw[out++] = rgba[src + 3];
      src += 4;
    }
  }

  final header = <int>[
    ..._be32(width),
    ..._be32(height),
    8, // bit depth
    alpha ? 6 : 2, // colour type: RGBA or RGB
    0, 0, 0, // deflate, adaptive filtering, no interlace
  ];

  return Uint8List.fromList([
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    ..._chunk('IHDR', header),
    ..._chunk('IDAT', ZLibEncoder().convert(raw)),
    ..._chunk('IEND', const []),
  ]);
}

List<int> _be32(int value) => [
  (value >> 24) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 8) & 0xFF,
  value & 0xFF,
];

List<int> _chunk(String type, List<int> data) {
  final body = <int>[...type.codeUnits, ...data];
  return [..._be32(data.length), ...body, ..._be32(_crc32(body))];
}

final List<int> _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final byte in bytes) {
    crc = _crcTable[(crc ^ byte) & 0xFF] ^ (crc >> 8);
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

void main() {
  test('generate icons', () async {
    // ignore: avoid_print
    print('iOS');
    const iosSizes = {
      'Icon-App-20x20@1x': 20.0,
      'Icon-App-20x20@2x': 40.0,
      'Icon-App-20x20@3x': 60.0,
      'Icon-App-29x29@1x': 29.0,
      'Icon-App-29x29@2x': 58.0,
      'Icon-App-29x29@3x': 87.0,
      'Icon-App-40x40@1x': 40.0,
      'Icon-App-40x40@2x': 80.0,
      'Icon-App-40x40@3x': 120.0,
      'Icon-App-60x60@2x': 120.0,
      'Icon-App-60x60@3x': 180.0,
      'Icon-App-76x76@1x': 76.0,
      'Icon-App-76x76@2x': 152.0,
      'Icon-App-83.5x83.5@2x': 167.0,
      'Icon-App-1024x1024@1x': 1024.0,
    };
    for (final entry in iosSizes.entries) {
      await _write(
        'ios/Runner/Assets.xcassets/AppIcon.appiconset/${entry.key}.png',
        entry.value,
        // iOS masks the corners itself and rejects any alpha channel.
        ground: Ground.fullBleed,
      );
    }

    // ignore: avoid_print
    print('macOS');
    for (final size in [16.0, 32.0, 64.0, 128.0, 256.0, 512.0, 1024.0]) {
      await _write(
        'macos/Runner/Assets.xcassets/AppIcon.appiconset/'
        'app_icon_${size.round()}.png',
        size,
        ground: Ground.roundedSquare,
        // The rounded square already eats a tenth of the frame, so measure the
        // disc against the content square rather than the canvas.
        discFractionOverride:
            _discFractionFor(size * _macContentFraction) * _macContentFraction,
      );
    }

    // ignore: avoid_print
    print('Android');
    const densities = {
      'mdpi': 1.0,
      'hdpi': 1.5,
      'xhdpi': 2.0,
      'xxhdpi': 3.0,
      'xxxhdpi': 4.0,
    };
    for (final entry in densities.entries) {
      await _write(
        'android/app/src/main/res/mipmap-${entry.key}/ic_launcher.png',
        48 * entry.value,
        ground: Ground.fullBleed,
      );
      // The adaptive foreground is a 108dp layer with the mark inside the
      // 66dp safe circle; the ink behind it is a separate colour layer.
      await _write(
        'android/app/src/main/res/mipmap-${entry.key}/ic_launcher_foreground.png',
        108 * entry.value,
        ground: Ground.none,
        discFractionOverride: _adaptiveDiscFraction,
      );
    }

    // ignore: avoid_print
    print('iOS launch image');
    // Sits on the ink launch background set in LaunchScreen.storyboard, so
    // it is the mark alone with nothing behind it.
    for (final (suffix, scale) in [('', 1.0), ('@2x', 2.0), ('@3x', 3.0)]) {
      await _write(
        'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage$suffix.png',
        96 * scale,
        ground: Ground.none,
        discFractionOverride: 1,
      );
    }

    // ignore: avoid_print
    print('Web');
    await _write('web/favicon.png', 32, ground: Ground.fullBleed);
    for (final size in [192.0, 512.0]) {
      await _write(
        'web/icons/Icon-${size.round()}.png',
        size,
        ground: Ground.fullBleed,
      );
      // A maskable icon is cropped to an arbitrary shape, so everything that
      // matters has to sit inside the middle 80%. The disc already does.
      await _write(
        'web/icons/Icon-maskable-${size.round()}.png',
        size,
        ground: Ground.fullBleed,
        discFractionOverride: _sourceDiscFraction * 0.86,
      );
    }
  });
}
