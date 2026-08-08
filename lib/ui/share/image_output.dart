import 'dart:typed_data';

export 'image_output_io.dart'
    if (dart.library.js_interop) 'image_output_web.dart'
    show copyImageToClipboard, saveImageBytes;

/// Result of an export action, reported on the sheet's status line.
typedef OutputResult = ({bool ok, String message});

/// Shared by both implementations so the sheet does not have to care which one
/// it is talking to.
abstract class ImageOutput {
  static Future<OutputResult> unsupported(String what) async =>
      (ok: false, message: '$what not available here');
}

/// Both platform files implement these.
typedef SaveImage =
    Future<OutputResult> Function(Uint8List bytes, String filename);
typedef CopyImage =
    Future<OutputResult> Function(Uint8List bytes, String filename);
