import 'package:flutter/foundation.dart';

/// Fullscreen is a browser concern: the native apps are already edge to edge.
const bool canToggleFullscreen = false;

/// Never changes off the web.
final ValueNotifier<bool> fullscreenActive = ValueNotifier(false);

void toggleFullscreen() {}
