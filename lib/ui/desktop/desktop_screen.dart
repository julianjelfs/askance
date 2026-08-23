import 'package:flutter/material.dart'
    show TextField, InputDecoration, InputBorder;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/engine.dart';
import '../../model/study.dart';
import '../../state/canvas_session.dart';
import '../../state/providers.dart';
import '../../theme.dart';
import '../canvas/canvas_surface.dart';
import '../canvas/tool_panel.dart';
import '../onboarding/onboarding_screen.dart';
import '../share/share_sheet.dart';
import '../shelf/qr_scan_screen.dart';
import '../shelf/shelf_screen.dart';
import '../widgets/askance_mark.dart';
import '../widgets/controls.dart';
import '../widgets/glyphs.dart';

/// Designed at 1180 x 760: the rail is fixed and the stage flexes.
class DesktopScreen extends ConsumerStatefulWidget {
  const DesktopScreen({super.key});

  @override
  ConsumerState<DesktopScreen> createState() => _DesktopScreenState();
}

class _DesktopScreenState extends ConsumerState<DesktopScreen> {
  bool _shelfOpen = false;

  @override
  void initState() {
    super.initState();
    // Nothing is open yet, so the shelf is the honest place to start.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !ref.read(sessionProvider).hasImage) {
        setState(() => _shelfOpen = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);

    return ColoredBox(
      color: AskanceColors.surface,
      child: SafeArea(
        child: ListenableBuilder(
          listenable: session,
          builder: (context, _) => Row(
            children: [
              SizedBox(
                width: 284,
                child: _Rail(
                  session: session,
                  // Opens only: closing is the overlay's own ×, so the
                  // button cannot strand you on an empty stage.
                  onShelf: () => setState(() => _shelfOpen = true),
                  onKept: () => setState(() => _shelfOpen = true),
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(child: _Stage(session: session)),
                    if (_shelfOpen)
                      Positioned.fill(
                        child: _ShelfOverlay(
                          onClose: () => setState(() => _shelfOpen = false),
                          onOpened: () => setState(() => _shelfOpen = false),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ground #eae9e9, with the image centred in a 496 x 744 frame. The image sits
/// *whole on the ground* here rather than filling the frame.
class _Stage extends ConsumerWidget {
  const _Stage({required this.session});

  final CanvasSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shader = ref.watch(shaderProvider).valueOrNull;
    if (!session.hasImage || shader == null) {
      return const ColoredBox(color: AskanceColors.surface);
    }

    return ColoredBox(
      color: AskanceColors.surface,
      child: Center(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // The frame takes the shape of the photograph and as much of the
            // stage as it can. A fixed 496x744 frame, as the design has it,
            // strands the picture in the middle of a large window, and now
            // that images are shown whole it would letterbox a landscape
            // inside a portrait frame on top of that.
            const margin = 28.0;
            final available = Size(
              (constraints.maxWidth - margin * 2).clamp(80.0, double.infinity),
              (constraints.maxHeight - margin * 2).clamp(80.0, double.infinity),
            );
            final image = session.image!;
            final frame = containRect(
              Size(image.width.toDouble(), image.height.toDouble()),
              available,
            ).size;

            return Container(
              width: frame.width,
              height: frame.height,
              foregroundDecoration: const BoxDecoration(
                border: Border.fromBorderSide(
                  BorderSide(color: AskanceColors.dividerLight, width: kRule),
                ),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CanvasSurface(
                      session: session,
                      shader: shader,
                      // The desktop chrome is a fixed rail; there is nothing to
                      // dismiss, so a tap should not hide it.
                      allowChromeToggle: false,
                    ),
                  ),
                  if (session.settings.mode == ViewMode.split &&
                      !session.peeking)
                    Positioned.fill(child: SplitHandle(session: session)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Rail extends ConsumerStatefulWidget {
  const _Rail({
    required this.session,
    required this.onShelf,
    required this.onKept,
  });

  final CanvasSession session;
  final VoidCallback onShelf;

  /// Where keeping a study lands: on the shelf, showing what was just kept.
  final VoidCallback onKept;

  @override
  ConsumerState<_Rail> createState() => _RailState();
}

class _RailState extends ConsumerState<_Rail> {
  bool _editingName = false;
  late final _controller = TextEditingController(text: widget.session.name);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _editingName) _commit();
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
    setState(() => _editingName = false);
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final studies = ref.watch(studiesProvider).valueOrNull ?? const <Study>[];

    return ColoredBox(
      color: AskanceColors.ink,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _brand(),
          const SizedBox(height: kRule),
          _studyBlock(session),
          const SizedBox(height: kRule),
          // Brand, study and footer are pinned; View through Grid scrolls,
          // because the tallest state overflows 760px.
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _viewBlock(session),
                  const SizedBox(height: kRule),
                  _controlBlock(
                    'VALUES',
                    '${session.settings.steps} STEPS',
                    ValuesControl(session: session),
                  ),
                  const SizedBox(height: kRule),
                  _controlBlock(
                    'WHERE THE STEPS FALL',
                    BiasControl.readout(session.settings.bias),
                    BiasControl(session: session),
                  ),
                  const SizedBox(height: kRule),
                  _controlBlock(
                    'HOW THE SHAPES FORM',
                    null,
                    SmoothingControl(session: session),
                  ),
                  const SizedBox(height: kRule),
                  _controlBlock(
                    'DETAIL',
                    '${(session.settings.detail * 100).round()}',
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DetailControl(session: session),
                        const SizedBox(height: 12),
                        LockDetailControl(session: session),
                      ],
                    ),
                  ),
                  const SizedBox(height: kRule),
                  _controlBlock(
                    'ROOT OF THE SCALE',
                    null,
                    ScaleControl(session: session),
                  ),
                  const SizedBox(height: kRule),
                  _controlBlock('GRID', null, GridControl(session: session)),
                ],
              ),
            ),
          ),
          const SizedBox(height: kRule),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Text(
              '${studies.length} ${studies.length == 1 ? 'study' : 'studies'} '
              'on the shelf · scroll to zoom · hold to peek',
              style: AskanceText.body(11, color: const Color(0x8CF3F2F2)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _brand() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
    child: Row(
      children: [
        const AskanceMark(size: 22),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            'Askance',
            style: AskanceText.screenTitle(
              color: AskanceColors.ground,
            ).copyWith(fontSize: 22, letterSpacing: 22 * -0.02),
          ),
        ),
        ActionButton(
          label: 'SHELF',
          height: 30,
          fontSize: 10,
          solid: false,
          onDark: true,
          onPressed: widget.onShelf,
        ),
      ],
    ),
  );

  Widget _studyBlock(CanvasSession session) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('STUDY', style: AskanceText.sectionLabel()),
        const SizedBox(height: 10),
        if (_editingName)
          TextField(
            controller: _controller,
            focusNode: _focus,
            autofocus: true,
            style: AskanceText.cardName(
              color: AskanceColors.ground,
            ).copyWith(fontSize: 14),
            cursorColor: AskanceColors.accent,
            cursorWidth: kRule,
            onSubmitted: (_) => _commit(),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
            ),
          )
        else
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              _controller.text = session.name;
              setState(() => _editingName = true);
            },
            child: Text(
              session.hasImage ? session.name : 'No study open',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AskanceText.cardName(
                color: AskanceColors.ground,
              ).copyWith(fontSize: 14),
            ),
          ),
        const SizedBox(height: 14),
        ActionButton(
          label: 'SHARE',
          trailingIcon: const GlyphIcon(
            Glyph.arrowUpRight,
            size: 13,
            color: AskanceColors.ground,
          ),
          height: 38,
          fontSize: 11,
          onPressed: session.hasImage
              ? () => showShareSheet(context, ref)
              : null,
        ),
      ],
    ),
  );

  Widget _viewBlock(CanvasSession session) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('VIEW', style: AskanceText.sectionLabel()),
        const SizedBox(height: 10),
        for (final mode in ViewMode.values)
          _railButton(
            label: mode.longLabel,
            active: session.settings.mode == mode,
            onTap: () => session.setMode(mode),
          ),
        if (session.settings.mode == ViewMode.skeleton)
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: _railButton(
              label: '№  NUMBER THE REGIONS',
              active: session.settings.numbers,
              onTap: session.toggleNumbers,
            ),
          ),
      ],
    ),
  );

  Widget _railButton({
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Container(
      height: 38,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: active ? AskanceColors.accent : null,
      child: Text(label, style: AskanceText.controlLabel(11, tracking: 0.06)),
    ),
  );

  Widget _controlBlock(String label, String? value, Widget control) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(label, style: AskanceText.sectionLabel()),
            const Spacer(),
            if (value != null)
              Text(
                value,
                style: AskanceText.controlLabel(
                  10,
                  tracking: 0.06,
                  color: AskanceColors.accent,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        control,
      ],
    ),
  );
}

/// SHELF covers the stage with a light panel. Picking a study loads its
/// settings and closes the overlay.
class _ShelfOverlay extends ConsumerWidget {
  const _ShelfOverlay({required this.onClose, required this.onOpened});

  final VoidCallback onClose;
  final VoidCallback onOpened;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studies = ref.watch(studiesProvider).valueOrNull ?? const <Study>[];

    return ColoredBox(
      color: AskanceColors.ground,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: AskanceColors.dividerLight,
                  width: kRule,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text('Studies', style: AskanceText.screenTitle()),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).push(
                    NoTransitionRoute(builder: (_) => const OnboardingScreen()),
                  ),
                  child: Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: AskanceColors.dividerLight,
                        width: kRule,
                      ),
                    ),
                    child: Text(
                      '?',
                      style: AskanceText.button(13, color: AskanceColors.ink),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onClose,
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: Center(
                      child: Text(
                        '×',
                        style: AskanceText.button(20, color: AskanceColors.ink),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
              // Pinned to the left: a grid narrower than the stage otherwise
              // floats in the middle of it.
              child: Align(
                alignment: Alignment.topLeft,
                child: ShelfGrid(
                  studies: studies,
                  columns: 3,
                  onOpen: (study) async {
                    await openStudy(context, ref, study);
                    onOpened();
                  },
                  onNew: () async {
                    await startStudy(context, ref, fromCamera: false);
                    onOpened();
                  },
                ),
              ),
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: AskanceColors.dividerLight,
                  width: kRule,
                ),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 14),
            child: Row(
              children: [
                Expanded(
                  child: ActionButton(
                    label: 'Scan from QR code',
                    solid: false,
                    onPressed: () async {
                      final opened = await Navigator.of(context).push<bool>(
                        NoTransitionRoute(builder: (_) => const QrScanScreen()),
                      );
                      if (opened == true) onOpened();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ActionButton(
                    label: 'New study from photos',
                    trailing: '→',
                    onPressed: () async {
                      await startStudy(context, ref, fromCamera: false);
                      onOpened();
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
