import 'package:web/web.dart' as web;

/// The browser's own chrome is the only thing between the study and the
/// glass; the Fullscreen API removes it. Only callable from a user gesture,
/// which the button provides.
const bool canToggleFullscreen = true;

void toggleFullscreen() {
  if (web.document.fullscreenElement != null) {
    web.document.exitFullscreen();
  } else {
    web.document.documentElement?.requestFullscreen();
  }
}
