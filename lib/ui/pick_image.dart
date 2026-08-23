import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

/// A picked source image, with a suggested name to seed nothing in particular —
/// studies are auto-named and renamed in place.
typedef PickedImage = ({Uint8List bytes, String extension});

/// True where a camera capture is a real thing to offer: native mobile, and
/// mobile *web* — browsers there open the camera for a capture request, and
/// on web [defaultTargetPlatform] reflects the device. Desktop browsers would
/// degrade a capture to a plain file dialog, so they stay excluded.
bool get canTakePhoto =>
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.android;

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
  // ImagePicker's camera source works on mobile web too: it becomes a file
  // input with a capture attribute, which the browser answers with a camera.
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
