import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:super_clipboard/super_clipboard.dart';

import 'image_output.dart';

/// Desktop gets a save dialog; phones get the system share sheet, which is
/// where "save to Photos" and "save to Files" both live.
Future<OutputResult> saveImageBytes(Uint8List bytes, String filename) async {
  try {
    if (defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux) {
      final location = await getSaveLocation(
        suggestedName: filename,
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'PNG',
            extensions: ['png'],
            uniformTypeIdentifiers: ['public.png'],
          ),
        ],
      );
      if (location == null) return (ok: false, message: '');
      await File(location.path).writeAsBytes(bytes, flush: true);
      return (ok: true, message: 'Saved');
    }

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);
    final result = await Share.shareXFiles([
      XFile(file.path, mimeType: 'image/png', name: filename),
    ]);
    return result.status == ShareResultStatus.dismissed
        ? (ok: false, message: '')
        : (ok: true, message: 'Saved');
  } catch (e) {
    return (ok: false, message: 'Could not save');
  }
}

Future<OutputResult> copyImageToClipboard(
  Uint8List bytes,
  String filename,
) async {
  final clipboard = SystemClipboard.instance;
  if (clipboard == null) return (ok: false, message: 'Clipboard unavailable');
  final item = DataWriterItem(suggestedName: filename);
  item.add(Formats.png(bytes));
  await clipboard.write([item]);
  return (ok: true, message: 'Copied to clipboard');
}
