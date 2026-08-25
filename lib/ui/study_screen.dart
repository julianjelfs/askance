import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/canvas_session.dart';
import '../state/providers.dart';
import 'canvas/canvas_screen.dart';
import 'desktop/desktop_screen.dart';
import 'fullscreen/fullscreen_stub.dart'
    if (dart.library.js_interop) 'fullscreen/fullscreen_web.dart';
import 'layout.dart';

/// The open study, in whichever presentation fits: the phone's full-bleed
/// canvas, or the desktop's rail and stage. Entering browser fullscreen flips
/// a wide window to the phone presentation live — the point of fullscreen is
/// the picture.
///
/// This route is also where "open" ends: when it leaves the tree — however it
/// was popped, from whichever presentation — the session empties. On the
/// shelf there is no such thing as a selected study; autosave has already
/// written everything worth keeping, so closing costs nothing.
class StudyScreen extends ConsumerStatefulWidget {
  const StudyScreen({super.key});

  @override
  ConsumerState<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends ConsumerState<StudyScreen> {
  // Captured here because ref may not be touched from dispose.
  late final CanvasSession _session;

  @override
  void initState() {
    super.initState();
    _session = ref.read(sessionProvider);
  }

  @override
  void dispose() {
    // Fullscreen belongs to the study; the shelf gets the window back.
    if (fullscreenActive.value) toggleFullscreen();
    // Disposal happens after the pop transition has finished, so the clear
    // cannot pull the image out from under the return flight.
    _session.flushPersist();
    _session.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: fullscreenActive,
    builder: (context, _, _) =>
        isWideLayout(context) ? const DesktopScreen() : const CanvasScreen(),
  );
}
