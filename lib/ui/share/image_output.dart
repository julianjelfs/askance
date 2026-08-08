export 'image_output_io.dart'
    if (dart.library.js_interop) 'image_output_web.dart'
    show copyImageToClipboard, saveImageBytes;

/// What an export action reports back to the sheet's status line. An empty
/// message means the user cancelled, which is not worth saying out loud.
typedef OutputResult = ({bool ok, String message});
