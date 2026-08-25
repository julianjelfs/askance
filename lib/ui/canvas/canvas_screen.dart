import 'package:flutter/material.dart'
    show TextField, InputDecoration, InputBorder;
import 'package:flutter/services.dart' show TextInputAction;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/engine.dart';
import '../../state/canvas_session.dart';
import '../../state/providers.dart';
import '../../theme.dart';
import '../share/share_sheet.dart';
import '../shelf/shelf_screen.dart';
import '../fullscreen/fullscreen_stub.dart'
    if (dart.library.js_interop) '../fullscreen/fullscreen_web.dart';
import '../widgets/glyphs.dart';
import '../widgets/controls.dart';
import 'canvas_surface.dart';
import 'tool_panel.dart';

/// The app. A fullscreen image with chrome over it that can be dismissed
/// entirely.
class CanvasScreen extends ConsumerWidget {
  const CanvasScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final shader = ref.watch(shaderProvider);

    return Container(
      color: AskanceColors.ink,
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

class _CanvasBody extends ConsumerWidget {
  const _CanvasBody({required this.session, required this.shader});

  final CanvasSession session;
  final ValueShader shader;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = DesignScale.of(context);
    final padding = MediaQuery.paddingOf(context);
    final chromeVisible = session.chromeVisible;
    // While the open transition runs, the canvas is also the widget flying
    // between the card and the screen, and it must not re-render as it grows.
    // Listening to the route's own animation is what lets it start rendering
    // again the moment the flight lands.
    final routeAnimation =
        ModalRoute.of(context)?.animation ??
        const AlwaysStoppedAnimation<double>(1);

    return ListenableBuilder(
      listenable: routeAnimation,
      builder: (context, _) => _body(
        context,
        ref,
        s,
        padding,
        chromeVisible,
        flying: routeAnimation.isAnimating,
      ),
    );
  }

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    double s,
    EdgeInsets padding,
    bool chromeVisible, {
    required bool flying,
  }) {
    return PopScope(
      canPop: true,
      // Settings persist on a short debounce, so leaving immediately after a
      // change would otherwise drop it.
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) session.flushPersist();
      },
      child: Stack(
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
                freezeBlur: flying,
              ),
            )
          else
            CanvasSurface(session: session, shader: shader, freezeBlur: flying),

          if (session.settings.mode == ViewMode.split && !session.peeking)
            SplitHandle(session: session),

          // Chrome fades out entirely on a single tap, and stops taking hits
          // while it is gone.
          IgnorePointer(
            ignoring: !chromeVisible,
            child: AnimatedOpacity(
              opacity: chromeVisible ? 1 : 0,
              duration: AskanceMotion.chromeFade,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: _TopBar(session: session, topInset: padding.top),
                  ),
                  Positioned(
                    top: padding.top + 60 * s,
                    right: 14 * s,
                    child: _ModeRail(session: session),
                  ),
                  // Full-bleed at phone widths; on a desktop-sized screen —
                  // browser fullscreen — a bar stretched across the whole
                  // glass reads wrong, so past kToolsMaxWidth it becomes a
                  // floating panel in the bottom-left corner instead.
                  Positioned(
                    left: 0,
                    right: null,
                    bottom: 0,
                    child: LayoutBuilder(
                      builder: (context, _) {
                        final width = MediaQuery.sizeOf(context).width;
                        final floating = width > kToolsMaxWidth;
                        final tools = Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (session.openTool != null)
                              ToolPanel(
                                session: session,
                                tool: session.openTool!,
                              ),
                            _ToolBar(
                              session: session,
                              bottomInset: floating ? 0 : padding.bottom,
                            ),
                          ],
                        );
                        if (!floating) {
                          return SizedBox(width: width, child: tools);
                        }
                        return Padding(
                          padding: EdgeInsets.fromLTRB(
                            14 * s,
                            0,
                            0,
                            14 * s + padding.bottom,
                          ),
                          child: Container(
                            width: kToolsMaxWidth,
                            decoration: const BoxDecoration(
                              boxShadow: [
                                BoxShadow(
                                  color: Color(0x33201E1D),
                                  blurRadius: 14,
                                  offset: Offset(0, 5),
                                ),
                              ],
                            ),
                            child: tools,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Wider than this and the tool bar stops stretching: a hand-sized control
/// block has no business spanning a desktop.
const double kToolsMaxWidth = 550;

class _TopBar extends ConsumerStatefulWidget {
  const _TopBar({required this.session, required this.topInset});

  final CanvasSession session;
  final double topInset;

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
    final nameStyle =
        AskanceText.controlLabel(
              10,
              tracking: 0.05,
              color: AskanceColors.ground,
            )
            .by(s)
            .copyWith(
              shadows: const [Shadow(color: Color(0x99000000), blurRadius: 6)],
            );

    return Container(
      padding: EdgeInsets.only(top: widget.topInset),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x8C201E1D), Color(0x00201E1D)],
        ),
      ),
      child: SizedBox(
        height: 46 * s,
        child: Row(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                widget.session.flushPersist();
                Navigator.of(context).maybePop();
              },
              child: SizedBox(
                width: 42 * s,
                height: 32 * s,
                child: Center(
                  child: Text(
                    '←',
                    style: AskanceText.button(
                      16,
                      color: AskanceColors.ground,
                    ).by(s),
                  ),
                ),
              ),
            ),
            Expanded(
              child: _editing
                  ? TextField(
                      controller: _controller,
                      focusNode: _focus,
                      autofocus: true,
                      style: nameStyle,
                      cursorColor: AskanceColors.accent,
                      cursorWidth: kRule,
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
                      child: Text(
                        session.name.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: nameStyle,
                      ),
                    ),
            ),
            if (canToggleFullscreen)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: toggleFullscreen,
                child: SizedBox(
                  width: 42 * s,
                  height: 46 * s,
                  child: Center(
                    child: GlyphIcon(
                      Glyph.expand,
                      size: 17 * s,
                      color: AskanceColors.ground,
                    ),
                  ),
                ),
              ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => showShareSheet(context, ref),
              child: SizedBox(
                width: 42 * s,
                height: 46 * s,
                child: Center(
                  child: ShareIcon(size: 18 * s, color: AskanceColors.ground),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeRail extends StatelessWidget {
  const _ModeRail({required this.session});

  final CanvasSession session;

  @override
  Widget build(BuildContext context) {
    final s = DesignScale.of(context);
    final skeleton = session.settings.mode == ViewMode.skeleton;

    Widget cell({
      required String label,
      required bool active,
      required VoidCallback onTap,
    }) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 44 * s,
        height: 44 * s,
        alignment: Alignment.center,
        color: active ? AskanceColors.accent : null,
        child: Text(
          label,
          style: AskanceText.controlLabel(
            9,
            tracking: 0.06,
            color: AskanceColors.ground,
          ).by(s),
        ),
      ),
    );

    return Container(
      color: AskanceColors.ink,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final mode in ViewMode.values)
            cell(
              label: mode.railLabel,
              active: session.settings.mode == mode,
              onTap: () => session.setMode(mode),
            ),
          if (skeleton)
            cell(
              label: session.settings.skeletonFill == 0
                  ? 'FILL'
                  : '${session.settings.skeletonFill.clamp(0, session.settings.steps)}'
                        '/${session.settings.steps}',
              active: session.settings.skeletonFill > 0,
              onTap: session.cycleSkeletonFill,
            ),
        ],
      ),
    );
  }
}

class _ToolBar extends StatelessWidget {
  const _ToolBar({required this.session, required this.bottomInset});

  final CanvasSession session;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final s = DesignScale.of(context);

    String labelFor(CanvasTool tool) => switch (tool) {
      CanvasTool.steps => '${session.settings.steps} VAL',
      CanvasTool.detail => 'DETAIL',
      CanvasTool.scale => 'SCALE',
      CanvasTool.grid => 'GRID',
    };

    return Container(
      color: AskanceColors.ink,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SizedBox(
        height: 44 * s,
        child: Row(
          children: [
            for (final tool in CanvasTool.values)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => session.toggleTool(tool),
                  child: Container(
                    alignment: Alignment.center,
                    color: session.openTool == tool
                        ? AskanceColors.accent
                        : null,
                    child: Text(
                      labelFor(tool),
                      style: AskanceText.controlLabel(
                        10,
                        color: AskanceColors.ground,
                      ).by(s),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
