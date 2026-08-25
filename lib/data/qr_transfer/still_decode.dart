import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:zxing2/qrcode.dart';

/// Decodes a QR payload from a photograph of the code.
///
/// The fallback for surfaces whose live camera view will not render — some
/// tablet browsers compositing platform views badly — where a still capture
/// through the native camera UI works every time. Pure Dart, no video
/// pipeline at all.
Future<String?> decodeQrFromPhoto(Uint8List bytes) async {
  // Enough resolution to read a dense code off a screen; more only slows the
  // pure-Dart decode down.
  final codec = await ui.instantiateImageCodec(bytes, targetWidth: 1600);
  final frame = await codec.getNextFrame();
  codec.dispose();
  final image = frame.image;
  try {
    final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (rgba == null) return null;
    final bytesView = rgba.buffer.asUint8List();
    final pixels = Int32List(image.width * image.height);
    for (var i = 0; i < pixels.length; i++) {
      final o = i * 4;
      pixels[i] =
          (bytesView[o] << 16) | (bytesView[o + 1] << 8) | bytesView[o + 2];
    }
    final source = RGBLuminanceSource(image.width, image.height, pixels);
    final bitmap = BinaryBitmap(HybridBinarizer(source));
    return QRCodeReader()
        .decode(bitmap, hints: DecodeHints()..put(DecodeHintType.tryHarder))
        .text;
  } on Exception {
    // Not found, or not a QR code: the caller words the apology.
    return null;
  } finally {
    image.dispose();
  }
}
