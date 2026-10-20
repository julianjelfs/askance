import 'package:flutter/material.dart'
    show TextField, InputDecoration, InputBorder;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/crop.dart';
import '../../engine/engine.dart';
import '../../model/study.dart';
import '../../state/canvas_session.dart';
import '../../state/providers.dart';
import '../../theme.dart';
import '../fullscreen/fullscreen_stub.dart'
    if (dart.library.js_interop) '../fullscreen/fullscreen_web.dart';
import '../canvas/canvas_surface.dart';
import '../canvas/tool_panel.dart';
import '../crop/crop_screen.dart';
import '../share/share_sheet.dart';
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
  /// Set while a crop is being chosen. The rail gives way to the crop's own
  /// controls and the stage to the whole photograph, rather than a phone
  /// screen being stretched over the window.
  CropDraft? _cropDraft;

  void _startCrop(CanvasSession session) =>
      setState(() => _cropDraft = CropDraft(session));

  void _endCrop({required bool apply}) {
    final draft = _cropDraft;
    if (draft == null) return;
    if (apply) draft.apply();
    setState(() => _cropDraft = null);
    // After the frame: the stage may still be listening to it until then.
    WidgetsBinding.instance.addPostFrameCallback((_) => draft.dispose());
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final draft = _cropDraft;
    if (draft != null) {
      return ColoredBox(
        color: AskanceColors.gesso,
        child: SafeArea(
          child: Row(
            children: [
              SizedBox(
                width: _railWidth,
                child: _CropRail(
                  draft: draft,
                  onCancel: () => _endCrop(apply: false),
                  onApply: () => _endCrop(apply: true),
                ),
              ),
              Expanded(
                child: ColoredBox(
                  color: AskanceColors.surround,
                  child: CropPicture(draft: draft),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ColoredBox(
      color: AskanceColors.gesso,
      child: SafeArea(
        child: ListenableBuilder(
          listenable: session,
          builder: (context, _) => Row(
            children: [
              SizedBox(
                width: _railWidth,
                child: _Rail(
                  session: session,
                  onCrop: () => _startCrop(session),
                  // Leaving the study: the route's disposal clears the
                  // session and drops fullscreen, so the shelf arrives with
                  // nothing selected.
                  onShelf: () => Navigator.of(context).maybePop(),
                ),
              ),
              Expanded(child: _Stage(session: session)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Wide enough for six stage swatches side by side at a size worth tapping.
const double _railWidth = 340;

/// The floating palette beside the picture: wide enough that each colour can
/// be judged on its own, which a strip in the rail was too small for.
const double _paletteWidth = 88;
const double _paletteGap = 24;

/// The picture whole on the middle-grey surround, with its palette beside it.
class _Stage extends ConsumerWidget {
  const _Stage({required this.session});

  final CanvasSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shader = ref.watch(shaderProvider).valueOrNull;
    if (!session.hasImage || shader == null) {
      return const ColoredBox(color: AskanceColors.surround);
    }

    return ColoredBox(
      color: AskanceColors.surround,
      child: Center(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // The frame takes the shape of the photograph and as much of the
            // stage as it can. A fixed 496x744 frame, as the design has it,
            // strands the picture in the middle of a large window, and now
            // that images are shown whole it would letterbox a landscape
            // inside a portrait frame on top of that.
            const margin = 28.0;
            // The palette floats beside the picture, so the picture gives up
            // that much width rather than being overlapped by it.
            final palette = session.settings.mode.paintsOnlyPalette;
            final paletteRoom = palette ? _paletteWidth + _paletteGap : 0.0;
            final available = Size(
              (constraints.maxWidth - margin * 2 - paletteRoom).clamp(
                80.0,
                double.infinity,
              ),
              (constraints.maxHeight - margin * 2).clamp(80.0, double.infinity),
            );
            final image = session.image!;
            final frame = containRect(
              croppedSize(
                Size(image.width.toDouble(), image.height.toDouble()),
                session.settings.crop,
              ),
              available,
            ).size;

            final picture = Container(
              width: frame.width,
              height: frame.height,
              decoration: const BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Color(0x40000000),
                    blurRadius: 40,
                    offset: Offset(0, 16),
                  ),
                ],
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
            if (!palette) return picture;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                picture,
                const SizedBox(width: _paletteGap),
                // On a card of its own: the middle value is the surround's
                // own grey, and would vanish against it.
                Container(
                  width: _paletteWidth,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AskanceColors.gesso,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 24,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: PaletteSwatch(
                    session: session,
                    // Seven of these still fit a 760px window with room over.
                    chipHeight: 64,
                  ),
                ),
              ],
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
    required this.onCrop,
  });

  final CanvasSession session;
  final VoidCallback onShelf;
  final VoidCallback onCrop;

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
    final mode = session.settings.mode;

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AskanceColors.gesso,
        border: Border(
          right: BorderSide(color: AskanceColors.rule, width: kRule),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _brand(),
          const Rule(),
          _studyBlock(session),
          const Rule(),
          // Brand, study and footer are pinned; the controls scroll, because
          // the tallest state overflows a laptop's height.
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedControl<ViewMode>(
                    values: ViewMode.values,
                    selected: mode,
                    labelOf: (mode) => mode.railLabel,
                    onChanged: session.setMode,
                    height: 36,
                    fontSize: 12.5,
                  ),
                  if (mode == ViewMode.random) ...[
                    const SizedBox(height: 10),
                    ActionButton(
                      label: 'New colours',
                      solid: false,
                      centred: true,
                      height: 38,
                      fontSize: 14,
                      leadingIcon: const GlyphIcon(
                        Glyph.dice,
                        size: 18,
                        color: AskanceColors.graphite,
                      ),
                      onPressed: session.dealColours,
                    ),
                  ],
                  // Like the phone's tool bar, the rail only offers what
                  // adjusts the view on screen: the photograph has its tone,
                  // and nothing of the value map's.
                  if (mode == ViewMode.photo)
                    _section('Tone', null, ToneControl(session: session))
                  else ...[
                    _section(
                      'Stages',
                      StageControl.readout(session.settings),
                      StageControl(session: session, height: 36),
                    ),
                    _gap,
                    Row(
                      children: [
                        Expanded(
                          child: Text('Values', style: AskanceText.label(14.5)),
                        ),
                        RuleStepper(
                          value: session.settings.steps,
                          min: StudySettings.minSteps,
                          max: StudySettings.maxSteps,
                          onChanged: session.setSteps,
                          size: 34,
                        ),
                      ],
                    ),
                    _gap,
                    ControlLabelRow(
                      label: 'Where the steps fall',
                      value: BiasControl.readout(session.settings.bias),
                    ),
                    BiasControl(session: session),
                    if (mode == ViewMode.skeleton)
                      _section(
                        'Blocked in under the lines',
                        null,
                        FillControl(session: session),
                      ),
                    _section(
                      'Shapes',
                      null,
                      SmoothingControl(session: session, height: 52),
                    ),
                    _gap,
                    ControlLabelRow(
                      label: 'Detail',
                      value: '${(session.settings.detail * 100).round()}',
                    ),
                    DetailControl(session: session),
                    const SizedBox(height: 4),
                    LockDetailControl(session: session),
                    if (kShowTint)
                      _section(
                        'Root of the scale',
                        null,
                        ScaleControl(session: session),
                      ),
                  ],
                  _section(
                    'Board',
                    null,
                    BoardControl(session: session, onEditCrop: widget.onCrop),
                    showLabel: false,
                  ),
                ],
              ),
            ),
          ),
          const Rule(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
            child: Text(
              '${studies.length} ${studies.length == 1 ? 'study' : 'studies'} '
              'on the shelf · scroll to zoom · hold to peek',
              style: AskanceText.caption(12),
            ),
          ),
        ],
      ),
    );
  }

  static const _gap = SizedBox(height: 16);

  /// A group of controls, set off from the one above by a hairline.
  Widget _section(
    String label,
    String? value,
    Widget control, {
    bool showLabel = true,
  }) => Padding(
    padding: const EdgeInsets.only(top: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Rule(),
        const SizedBox(height: 16),
        if (showLabel) ControlLabelRow(label: label, value: value),
        control,
      ],
    ),
  );

  Widget _brand() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
    child: Row(
      children: [
        const AskanceMark(size: 22),
        const SizedBox(width: 10),
        Expanded(child: Text('Askance', style: AskanceText.display(22))),
        // Web only: a landscape tablet in a browser lands in this layout,
        // and reference use wants the glass to itself there too.
        if (canToggleFullscreen) ...[
          Semantics(
            button: true,
            label: 'Full screen',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: toggleFullscreen,
              child: const SizedBox(
                width: 36,
                height: 36,
                child: Center(
                  child: GlyphIcon(
                    Glyph.expand,
                    size: 18,
                    color: AskanceColors.graphite,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
        ActionButton(
          label: 'Shelf',
          height: 34,
          fontSize: 13.5,
          solid: false,
          onPressed: widget.onShelf,
        ),
      ],
    ),
  );

  Widget _studyBlock(CanvasSession session) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 14, 16, 16),
    child: Row(
      children: [
        Expanded(
          child: _editingName
              ? TextField(
                  controller: _controller,
                  focusNode: _focus,
                  autofocus: true,
                  style: AskanceText.title(18),
                  cursorColor: AskanceColors.accent,
                  cursorWidth: 2,
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
                    setState(() => _editingName = true);
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.hasImage ? session.name : 'No study open',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AskanceText.title(18),
                      ),
                      if (session.hasImage) ...[
                        const SizedBox(height: 3),
                        Text(
                          '${session.settings.steps} values · '
                          '${cropSummary(session)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AskanceText.caption(13),
                        ),
                      ],
                    ],
                  ),
                ),
        ),
        const SizedBox(width: 12),
        ActionButton(
          label: 'Share',
          height: 38,
          fontSize: 14,
          onPressed: session.hasImage
              ? () => showShareSheet(context, ref)
              : null,
        ),
      ],
    ),
  );
}

/// The rail while a crop is being chosen: the shape, which way round, and
/// the way out.
class _CropRail extends StatelessWidget {
  const _CropRail({
    required this.draft,
    required this.onCancel,
    required this.onApply,
  });

  final CropDraft draft;
  final VoidCallback onCancel;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: AskanceColors.gesso,
      border: Border(
        right: BorderSide(color: AskanceColors.rule, width: kRule),
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            "Match the board you're painting on",
            style: AskanceText.heading(24),
          ),
          const SizedBox(height: 10),
          Text(
            'Pick the shape of the board, then drag the frame to the part '
            'of the photograph you want. Scroll to make it larger or '
            'smaller.',
            style: AskanceText.body(13.5, color: AskanceColors.muted),
          ),
          const SizedBox(height: 22),
          CropShapeControls(draft: draft),
          const Spacer(),
          CropActions(onCancel: onCancel, onApply: onApply),
        ],
      ),
    ),
  );
}

/// SHELF covers the stage with a light panel. Picking a study loads its
/// settings and closes the overlay.
