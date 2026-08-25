import 'package:flutter/widgets.dart';

import '../theme.dart';
import 'fullscreen/fullscreen_stub.dart'
    if (dart.library.js_interop) 'fullscreen/fullscreen_web.dart';

/// Whether this build should wear the rail-and-stage layout.
///
/// Width alone does not decide it: in browser fullscreen the point is the
/// picture, so even a desktop-wide window drops to the phone layout — full
/// bleed canvas, dismissable chrome — for as long as fullscreen lasts.
bool isWideLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kDesktopBreakpoint &&
    !fullscreenActive.value;
