import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

/// A picked source image, with a suggested name to seed nothing in particular —
/// studies are auto-named and renamed in place.
typedef PickedImage = ({Uint8List bytes, String extension});

bool get canTakePhoto =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android);

bool get _usesImagePicker =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android);

Future<PickedImage?> pickFromLibrary() async {
  if (_usesImagePicker) {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null) return null;
    return (
      bytes: await file.readAsBytes(),
      extension: _extensionOf(file.name),
    );
  }

  const group = XTypeGroup(
    label: 'Images',
    extensions: ['jpg', 'jpeg', 'png', 'heic', 'webp'],
    uniformTypeIdentifiers: ['public.image'],
    mimeTypes: ['image/*'],
  );
  final file = await openFile(acceptedTypeGroups: const [group]);
  if (file == null) return null;
  return (bytes: await file.readAsBytes(), extension: _extensionOf(file.name));
}

Future<PickedImage?> takePhoto() async {
  if (!canTakePhoto) return pickFromLibrary();
  final file = await ImagePicker().pickImage(source: ImageSource.camera);
  if (file == null) return null;
  return (bytes: await file.readAsBytes(), extension: _extensionOf(file.name));
}

String _extensionOf(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return 'jpg';
  final ext = name.substring(dot + 1).toLowerCase();
  return ext.length > 5 ? 'jpg' : ext;
}
