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
import '../shelf/shelf_screen.dart';
import '../widgets/controls.dart';

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
                  onShelf: () => setState(() => _shelfOpen = !_shelfOpen),
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
            // 496 x 744 at the design size, shrinking to fit a smaller window.
            const designed = Size(496, 744);
            final scale = (constraints.maxHeight - 32) / designed.height;
            final height = designed.height * scale.clamp(0.3, 1.0);
            final width = designed.width * scale.clamp(0.3, 1.0);

            return Container(
              width: width,
              height: height,
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
  const _Rail({required this.session, required this.onShelf});

  final CanvasSession session;
  final VoidCallback onShelf;

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
    widget.session.rename(name.isEmpty ? 'Untitled study' : name);
    final id = widget.session.studyId;
    if (id != null) {
      ref.read(studiesProvider.notifier).rename(id, widget.session.name);
    }
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
          const Rule(),
          _studyBlock(session),
          const Rule(),
          // Brand, study and footer are pinned; View through Grid scrolls,
          // because the tallest state overflows 760px.
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _viewBlock(session),
                  const Rule(),
                  _controlBlock(
                    'VALUES',
                    '${session.settings.steps} STEPS',
                    ValuesControl(session: session),
                  ),
                  const Rule(),
                  _controlBlock(
                    'DETAIL',
                    '${(session.settings.detail * 100).round()}',
                    DetailControl(session: session),
                  ),
                  const Rule(),
                  _controlBlock(
                    'ROOT OF THE SCALE',
                    null,
                    ScaleControl(session: session),
                  ),
                  const Rule(),
                  _controlBlock('GRID', null, GridControl(session: session)),
                ],
              ),
            ),
          ),
          const Rule(),
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
          trailing: '↗',
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
              child: ShelfGrid(
                studies: studies,
                columns: 3,
                onOpen: (study) async {
                  await openStudy(context, ref, study);
                  onOpened();
                },
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
            child: ActionButton(
              label: 'New study from an image',
              trailing: '→',
              onPressed: () async {
                await startStudy(context, ref, fromCamera: false);
                onOpened();
              },
            ),
          ),
        ],
      ),
    );
  }
}
