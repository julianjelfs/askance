import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/canvas_session.dart';
import '../state/providers.dart';
import 'canvas/canvas_screen.dart';
import 'desktop/desktop_screen.dart';
import 'fullscreen/fullscreen_stub.dart'
    if (dart.library.js_interop) 'fullscreen/fullscreen_web.dart';
import 'layout.dart';

/// The open study, in whichever presentation fits the width: the phone's
/// canvas, or the desktop's rail and stage.
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
  Widget build(BuildContext context) => StudyKeys(
    session: _session,
    child: isWideLayout(context) ? const DesktopScreen() : const CanvasScreen(),
  );
}

/// The study's keyboard shortcuts: the up arrow flips the picture, and while
/// lines are being ruled, Delete or Backspace removes the selected one and
/// Escape lets go of a half-ruled line or a selection, then stops ruling.
///
/// Heard from the keyboard directly rather than bound through focus: the
/// name's text field takes focus by autofocus, which a focus node held here
/// would refuse it. A focused text field keeps its arrow keys for the caret,
/// and a screen opened over the study, the crop, keeps them too.
class StudyKeys extends StatefulWidget {
  const StudyKeys({super.key, required this.session, required this.child});

  final CanvasSession session;
  final Widget child;

  @override
  State<StudyKeys> createState() => _StudyKeysState();
}

class _StudyKeysState extends State<StudyKeys> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (ModalRoute.of(context)?.isCurrent == false) return false;
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused?.findAncestorWidgetOfExactType<EditableText>() != null) {
      return false;
    }
    final session = widget.session;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp) {
      session.setFlipped(!session.flipped);
      return true;
    }
    if (!session.drawingLines) return false;
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      return session.deleteSelectedLine();
    }
    if (key == LogicalKeyboardKey.escape) {
      if (!session.cancelLine()) session.setDrawingLines(false);
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
