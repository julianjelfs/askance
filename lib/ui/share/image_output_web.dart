import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'image_output.dart';

/// A browser download: a blob URL clicked once and revoked immediately.
Future<OutputResult> saveImageBytes(Uint8List bytes, String filename) async {
  try {
    final url = web.URL.createObjectURL(_blob(bytes));
    final anchor = web.document.createElement('a') as web.HTMLAnchorElement
      ..href = url
      ..download = filename
      ..style.display = 'none';
    web.document.body!.appendChild(anchor);
    anchor.click();
    anchor.remove();
    web.URL.revokeObjectURL(url);
    return (ok: true, message: 'Saved');
  } catch (e) {
    return (ok: false, message: 'Could not save');
  }
}

Future<OutputResult> copyImageToClipboard(
  Uint8List bytes,
  String filename,
) async {
  try {
    final item = web.ClipboardItem(
      {'image/png': _blob(bytes)}.jsify()! as JSObject,
    );
    await web.window.navigator.clipboard.write([item].toJS).toDart;
    return (ok: true, message: 'Copied to clipboard');
  } catch (e) {
    // Safari only allows a clipboard write inside a user gesture, and some
    // browsers refuse image writes entirely.
    return (ok: false, message: 'Clipboard blocked by the browser');
  }
}

web.Blob _blob(Uint8List bytes) =>
    web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: 'image/png'));
