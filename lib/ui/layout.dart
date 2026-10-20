import 'package:flutter/widgets.dart';

import '../theme.dart';

/// Whether this build should wear the rail-and-stage layout: width alone
/// decides it.
///
/// Browser fullscreen once dropped a desktop window to the phone layout, on
/// the reasoning that fullscreen is for the picture. In practice the layout
/// changing under you read as the app breaking; fullscreen now only gives the
/// same layout more room.
bool isWideLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kDesktopBreakpoint;
