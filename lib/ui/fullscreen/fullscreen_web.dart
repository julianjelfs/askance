import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

/// The browser's own chrome is the only thing between the study and the
/// glass; the Fullscreen API removes it. Only callable from a user gesture,
/// which the button provides.
const bool canToggleFullscreen = true;

/// Tracks the browser's fullscreen state however it changes — our button,
/// Esc, or a system gesture — so the layout can follow it.
final ValueNotifier<bool> fullscreenActive = _watch();

ValueNotifier<bool> _watch() {
  final notifier = ValueNotifier(web.document.fullscreenElement != null);
  void update(web.Event _) {
    notifier.value = web.document.fullscreenElement != null;
  }

  // Safari kept the webkit prefix for longer than anyone.
  web.document.addEventListener('fullscreenchange', update.toJS);
  web.document.addEventListener('webkitfullscreenchange', update.toJS);
  return notifier;
}

void toggleFullscreen() {
  if (web.document.fullscreenElement != null) {
    web.document.exitFullscreen();
  } else {
    web.document.documentElement?.requestFullscreen();
  }
}
