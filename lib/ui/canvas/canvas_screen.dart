import 'package:flutter/material.dart'
    show TextField, InputDecoration, InputBorder;
import 'package:flutter/services.dart' show TextInputAction;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/engine.dart';
import '../../state/canvas_session.dart';
import '../../state/providers.dart';
import '../../theme.dart';
import '../crop/crop_screen.dart';
import '../share/share_sheet.dart';
import '../shelf/shelf_screen.dart';
import '../fullscreen/fullscreen_stub.dart'
    if (dart.library.js_interop) '../fullscreen/fullscreen_web.dart';
import '../widgets/controls.dart';
import '../widgets/glyphs.dart';
import 'canvas_surface.dart';
import 'tool_panel.dart';

/// The study on a phone or a tablet held upright: the picture on its grey
/// surround, the view selector above it and the tools below.
class CanvasScreen extends ConsumerWidget {
  const CanvasScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final shader = ref.watch(shaderProvider);

    return Container(
      color: AskanceColors.surround,
      child: ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          if (!session.hasImage || !shader.hasValue) {
            return const SizedBox.expand();
          }
          return _CanvasBody(session: session, shader: shader.requireValue);
        },
      ),
    );
  }
}

class _CanvasBody extends ConsumerStatefulWidget {
  const _CanvasBody({required this.session, required this.shader});

  final CanvasSession session;
  final ValueShader shader;

  @override
  ConsumerState<_CanvasBody> createState() => _CanvasBodyState();
}

class _CanvasBodyState extends ConsumerState<_CanvasBody>
    with SingleTickerProviderStateMixin {
  /// 1 with the controls showing, 0 with the picture alone. A tap on the
  /// picture slides the title bar up and the tools down, out of the way,
  /// while the picture grows into the room they leave.
  late final AnimationController _chrome = AnimationController(
    vsync: this,
    duration: _chromeSlide,
    value: widget.session.chromeVisible ? 1 : 0,
  );

  static const _chromeSlide = Duration(milliseconds: 300);

  /// Where the slide was last sent, so a rebuild mid-slide does not restart
  /// it.
  late double _target = _chrome.value;

  @override
  void dispose() {
    _chrome.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final target = widget.session.chromeVisible ? 1.0 : 0.0;
    if (target != _target) {
      _target = target;
      _chrome.animateTo(target, curve: AskanceMotion.slide);
    }

    // While the open transition runs, the canvas is also the widget flying
    // between the card and the screen, and it must not re-render as it grows.
    // Listening to the route's own animation is what lets it start rendering
    // again the moment the flight lands. The same holds while the controls
    // slide away: the picture is scaled through the slide and rendered once
    // it lands, rather than at every size on the way.
    final routeAnimation =
        ModalRoute.of(context)?.animation ??
        const AlwaysStoppedAnimation<double>(1);

    return ListenableBuilder(
      listenable: Listenable.merge([routeAnimation, _chrome]),
      builder: (context, _) => _body(
        context,
        frozen: routeAnimation.isAnimating || _chrome.isAnimating,
      ),
    );
  }

  Widget _body(BuildContext context, {required bool frozen}) {
    final s = DesignScale.of(context);
    final padding = MediaQuery.paddingOf(context);
    final session = widget.session;
    final shader = widget.shader;
    final shown = CurvedAnimation(parent: _chrome, curve: Curves.linear);

    /// Collapses [child] to nothing as the controls go, sliding it toward
    /// the edge it belongs to.
    Widget collapsing(Widget child, {required bool fromTop}) => ClipRect(
      child: SizeTransition(
        sizeFactor: shown,
        // The title bar keeps its foot and the tools their head, so each
        // slides off toward its own edge.
        alignment: fromTop ? Alignment.bottomCenter : Alignment.topCenter,
        child: FadeTransition(opacity: shown, child: child),
      ),
    );

    final surface = Stack(
      fit: StackFit.expand,
      children: [
        // A study opened from the shelf grows out of its thumbnail. A study
        // that has never been saved has no thumbnail to grow from.
        if (session.studyId case final id?)
          Hero(
            tag: studyHeroTag(id),
            child: CanvasSurface(
              session: session,
              shader: shader,
              freezeBlur: frozen,
            ),
          )
        else
          CanvasSurface(session: session, shader: shader, freezeBlur: frozen),
        if (session.settings.mode == ViewMode.split && !session.peeking)
          SplitHandle(session: session),
      ],
    );

    return PopScope(
      canPop: true,
      // Settings persist on a short debounce, so leaving immediately after a
      // change would otherwise drop it.
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) session.flushPersist();
      },
      // Hidden controls stop taking hits at once, not when the slide ends.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          collapsing(
            IgnorePointer(
              ignoring: !session.chromeVisible,
              child: Container(
                color: AskanceColors.graphite,
                padding: EdgeInsets.only(top: padding.top),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _TopBar(session: session),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        14 * s,
                        4 * s,
                        14 * s,
                        12 * s,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: 520 * s),
                          child: _ViewSelector(session: session),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            fromTop: true,
          ),
          // The picture keeps its size while a tool is open: the tool's
          // sheet rises over it from the bar rather than pushing it up, so
          // what you are judging stays put while you adjust it.
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: surface),
                      if (session.settings.mode.paintsOnlyPalette)
                        collapsing(
                          IgnorePointer(
                            ignoring: !session.chromeVisible,
                            child: Padding(
                              padding: EdgeInsets.only(
                                top: 2 * s,
                                bottom: 12 * s,
                              ),
                              child: PaletteChips(session: session),
                            ),
                          ),
                          fromTop: false,
                        ),
                    ],
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _ToolSheet(session: session),
                ),
              ],
            ),
          ),
          collapsing(
            IgnorePointer(
              ignoring: !session.chromeVisible,
              child: _ToolDeck(session: session, bottomInset: padding.bottom),
            ),
            fromTop: false,
          ),
        ],
      ),
    );
  }
}

class _TopBar extends ConsumerStatefulWidget {
  const _TopBar({required this.session});

  final CanvasSession session;

  @override
  ConsumerState<_TopBar> createState() => _TopBarState();
}

class _TopBarState extends ConsumerState<_TopBar> {
  bool _editing = false;
  late final TextEditingController _controller = TextEditingController(
    text: widget.session.name,
  );
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _editing) _commit();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit() {
    final name = _controller.text.trim();
    // A saved study writes its own name back; nothing else to do here.
    widget.session.rename(name.isEmpty ? 'Untitled study' : name);
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = DesignScale.of(context);
    final session = widget.session;
    final nameStyle = AskanceText.title(16.5, color: AskanceColors.gesso).by(s);

    Widget iconButton(Glyph glyph, String label, VoidCallback onTap) =>
        Semantics(
          button: true,
          label: label,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: SizedBox(
              width: 44 * s,
              height: 48 * s,
              child: Center(
                child: GlyphIcon(
                  glyph,
                  size: 22 * s,
                  color: AskanceColors.gesso,
                ),
              ),
            ),
          ),
        );

    return SizedBox(
      height: 56 * s,
      child: Row(
        children: [
          SizedBox(width: 4 * s),
          iconButton(Glyph.back, 'Back to the shelf', () {
            session.flushPersist();
            Navigator.of(context).maybePop();
          }),
          Expanded(
            child: _editing
                ? TextField(
                    controller: _controller,
                    focusNode: _focus,
                    autofocus: true,
                    style: nameStyle,
                    cursorColor: AskanceColors.accent,
                    cursorWidth: 2,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _commit(),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                    ),
                  )
                : GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      _controller.text = session.name;
                      setState(() => _editing = true);
                    },
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: nameStyle,
                        ),
                        SizedBox(height: 2 * s),
                        Text(
                          _caption(session),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AskanceText.caption(
                            12.5,
                            color: AskanceColors.mutedOnDark,
                          ).by(s),
                        ),
                      ],
                    ),
                  ),
          ),
          if (canToggleFullscreen)
            iconButton(Glyph.expand, 'Full screen', toggleFullscreen),
          iconButton(Glyph.share, 'Share', () => showShareSheet(context, ref)),
          SizedBox(width: 6 * s),
        ],
      ),
    );
  }

  /// "4 values · grey · A4 portrait": what the study is, at a glance.
  static String _caption(CanvasSession session) {
    final settings = session.settings;
    // Grey goes without saying while the tint is hidden.
    final scale = settings.scale.hue == null
        ? (kShowTint ? 'grey · ' : '')
        : 'tinted · ';
    return '${settings.steps} values · $scale${cropSummary(session)}';
  }
}

/// How to look at the study, across the top.
class _ViewSelector extends StatelessWidget {
  const _ViewSelector({required this.session});

  final CanvasSession session;

  @override
  Widget build(BuildContext context) => SegmentedControl<ViewMode>(
    values: ViewMode.values,
    selected: session.settings.mode,
    labelOf: (mode) => mode.railLabel,
    // Tapping RANDOM again deals another palette, so a repeat tap is passed
    // through rather than swallowed.
    onChanged: session.setMode,
    onDark: true,
    fontSize: 13,
  );
}

/// The open tool, on a gesso sheet that rises from the tool bar over the
/// foot of the picture. On a tablet held upright the sheet spans the glass
/// but its contents keep to a hand-sized column.
class _ToolSheet extends StatelessWidget {
  const _ToolSheet({required this.session});

  final CanvasSession session;

  @override
  Widget build(BuildContext context) {
    final s = DesignScale.of(context);
    final tool = session.openTool;
    return AnimatedSwitcher(
      duration: AskanceMotion.sheetSlide,
      switchInCurve: AskanceMotion.slide,
      switchOutCurve: AskanceMotion.slide.flipped,
      // Keyed on whether a sheet is open at all, so moving between tools
      // swaps the contents in place and only opening and closing slide.
      transitionBuilder: (child, animation) => SlideTransition(
        position: Tween(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.bottomCenter,
        children: [...previous, ?current],
      ),
      child: tool == null
          ? const SizedBox(key: ValueKey(false), width: double.infinity)
          : Container(
              key: const ValueKey(true),
              width: double.infinity,
              decoration: BoxDecoration(
                color: AskanceColors.gesso,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(AskanceRadius.sheet * s),
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x40000000),
                    blurRadius: 24,
                    offset: Offset(0, -4),
                  ),
                ],
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: kToolsMaxWidth * s),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      18 * s,
                      18 * s,
                      18 * s,
                      16 * s,
                    ),
                    child: ToolPanel(
                      session: session,
                      tool: tool,
                      onEditCrop: () {
                        session.closeTool();
                        showCropScreen(context, session);
                      },
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

/// The tool bar, on gesso. Its top corners round off when it stands alone
/// and square up when a sheet sits on it, so the two read as one piece.
class _ToolDeck extends StatelessWidget {
  const _ToolDeck({required this.session, required this.bottomInset});

  final CanvasSession session;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final s = DesignScale.of(context);
    final open = session.openTool != null;
    return AnimatedContainer(
      duration: AskanceMotion.sheetSlide,
      curve: AskanceMotion.slide,
      decoration: BoxDecoration(
        color: AskanceColors.gesso,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(open ? 0 : AskanceRadius.sheet * s),
        ),
      ),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: kToolsMaxWidth * s),
          child: _ToolBar(session: session, divided: open),
        ),
      ),
    );
  }
}

/// Wider than this and the tools stop stretching: a hand-sized control block
/// has no business spanning a tablet.
const double kToolsMaxWidth = 560;

class _ToolBar extends StatelessWidget {
  const _ToolBar({required this.session, required this.divided});

  final CanvasSession session;

  /// A hairline above the bar, when a panel sits over it.
  final bool divided;

  @override
  Widget build(BuildContext context) {
    final s = DesignScale.of(context);

    (Glyph, String) look(CanvasTool tool) => switch (tool) {
      CanvasTool.steps => (
        Glyph.staircase,
        'Values · ${session.settings.steps}',
      ),
      CanvasTool.detail => (Glyph.shapes, 'Shapes'),
      CanvasTool.scale => (Glyph.tint, 'Tint'),
      CanvasTool.grid => (Glyph.board, 'Board'),
      CanvasTool.tone => (Glyph.tone, 'Tone'),
      CanvasTool.fill => (Glyph.fill, 'Fill'),
    };

    return Container(
      // In the foreground, so the hairline costs the bar no height and the
      // picture above does not move by a pixel when a sheet opens.
      foregroundDecoration: BoxDecoration(
        border: divided
            ? const Border(
                top: BorderSide(color: AskanceColors.rule, width: kRule),
              )
            : null,
      ),
      padding: EdgeInsets.symmetric(vertical: 4 * s),
      child: Row(
        children: [
          for (final tool in CanvasTool.barFor(session.settings.mode))
            Expanded(
              child: Builder(
                builder: (context) {
                  final (glyph, label) = look(tool);
                  final open = session.openTool == tool;
                  final colour = open
                      ? AskanceColors.accentInk
                      : AskanceColors.muted;
                  return Semantics(
                    button: true,
                    selected: open,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      // Tapping the open tool closes it, and the picture takes
                      // the room back.
                      onTap: () => session.toggleTool(tool),
                      child: SizedBox(
                        height: 54 * s,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            GlyphIcon(glyph, size: 21 * s, color: colour),
                            SizedBox(height: 4 * s),
                            Text(
                              label,
                              style: AskanceText.control(
                                12.5,
                                color: colour,
                                weight: open
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                              ).by(s),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
