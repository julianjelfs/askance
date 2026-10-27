import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/scheduler.dart';

import '../engine/crop.dart';
import '../engine/engine.dart';
import '../engine/blur_pass.dart';
import '../engine/lines.dart';
import '../engine/value_scale.dart';
import '../model/study.dart';

enum CanvasTool {
  /// How many values, and the stages that set values and detail together.
  steps,

  /// The picture's qualities, which every view shows and the values are cut
  /// from: detail, brightness and contrast.
  picture,

  /// How the shapes form: smooth, rough or straight-edged.
  shapes,

  /// The root of the scale: grey or a tint.
  scale,

  /// The board: crop and grid.
  grid,

  /// Whether PHOTO shows the photograph in colour or black and white.
  tone,

  /// How many values EDGES blocks in under its lines.
  fill;

  /// The tools on the tool bar while [mode] is showing. The view selector
  /// picks how to look and the bar holds what adjusts that view, so it never
  /// offers a control that would change nothing on screen: values, shapes
  /// and scale are all lost on the photograph, colour is lost on everything
  /// else, and fill only means something under the edges. The picture is
  /// in every view.
  static List<CanvasTool> barFor(ViewMode mode) => switch (mode) {
    ViewMode.photo => const [picture, tone, grid],
    ViewMode.skeleton => [
      steps,
      picture,
      shapes,
      if (kShowTint) scale,
      fill,
      grid,
    ],
    _ => [steps, picture, shapes, if (kShowTint) scale, grid],
  };
}

/// Whether the tint (the root of the scale) is offered anywhere. Hidden for
/// now because it went unused; the scale is still stored, rendered and
/// exported, so turning this back on restores it as it was.
const bool kShowTint = false;

/// The open study, plus the view state that is deliberately *not* part of a
/// study: zoom, pan, peek, chrome visibility and which tool is open.
class CanvasSession extends ChangeNotifier {
  ui.Image? image;

  /// Owned here rather than by the canvas widget so that every view of this
  /// study — the canvas, and the copy that flies during the open transition —
  /// shares one finished pass instead of each starting from nothing.
  final BlurPass blur = BlurPass();

  /// The photograph blurred by the study's detail, for PHOTO's squint, a
  /// peek and SPLIT's photograph. Only asked for while PHOTO squints.
  final BlurPass photoBlur = BlurPass();

  /// The original bytes, kept so exports can re-run the engine from the source
  /// rather than upscaling the screen raster.
  Uint8List? imageBytes;

  /// Set once the study has been kept on the shelf.
  String? studyId;
  String? imageKey;

  String name = 'Untitled study';
  StudySettings settings = const StudySettings();
  ViewTransform view = const ViewTransform();

  bool peeking = false;

  /// The one band, darkest first, the picture is showing on its own after a
  /// tap on the palette swatch; null shows them all. View state like
  /// [peeking]: a study never records it.
  int? isolatedBand;

  /// The picture turned upside down, as a painter turns the paper, so its
  /// proportions can be judged as shapes rather than as the things they
  /// depict. View state like
  /// [peeking]: a study never records it, and exports are never flipped.
  bool flipped = false;
  bool chromeVisible = true;
  CanvasTool? openTool;

  /// Whether a click on the picture rules lines rather than doing what it
  /// usually does. View state like [peeking], and with it [lineStart], the
  /// first end of a line still being ruled, and [selectedLine], the one a
  /// delete would remove.
  bool drawingLines = false;
  Offset? lineStart;
  int? selectedLine;

  /// Live split position during a drag. Written back into [settings] when the
  /// drag ends, so the study only records settled values.
  double splitPosition = 0.5;

  Size viewportSize = Size.zero;
  double devicePixelRatio = 1;

  /// Called when a study that is already on the shelf has settled on new
  /// settings, so they can be written back without the user saving again.
  ///
  /// The study id and settings are passed by value rather than read back off
  /// the session, so a write scheduled for one study can never land on
  /// whichever study happens to be open by the time it fires.
  void Function(String studyId, StudySettings settings, String name)? onPersist;

  Timer? _persistDebounce;

  bool get hasImage => image != null;

  /// [resetView] belongs to a freshly picked image. A reopened study has its
  /// view restored by [openStudy] just before its image arrives here, and
  /// resetting then wiped the restored zoom — and the next autosave wrote the
  /// wiped view back over the study, so the passage was lost for good.
  void loadImage(
    ui.Image decoded,
    Uint8List bytes, {
    String? key,
    bool resetView = true,
  }) {
    image?.dispose();
    image = decoded;
    imageBytes = bytes;
    // Taken verbatim, null included: a fresh image has no stored copy yet.
    // Falling back to the previous study's key here meant a new study could
    // be kept under the *old* study's photograph.
    imageKey = key;
    if (resetView) view = const ViewTransform();
    notifyListeners();
  }

  void openStudy(Study study) {
    flushPersist();
    studyId = study.id;
    name = study.name;
    imageKey = study.imageKey;
    settings = study.settings;
    splitPosition = study.settings.splitPosition;
    // Come back to the passage you were working on, at the zoom you left it.
    view = study.settings.view;
    isolatedBand = null;
    flipped = false;
    _stopDrawingLines();
    openTool = null;
    chromeVisible = true;
    notifyListeners();
  }

  /// Empties the session entirely — deleting the open study from the shelf
  /// must not leave a ghost of it here, still shareable. Nothing is
  /// persisted: the study is going, not settling.
  void clear() {
    _persistDebounce?.cancel();
    _persistDebounce = null;
    studyId = null;
    imageKey = null;
    name = 'Untitled study';
    settings = const StudySettings();
    splitPosition = settings.splitPosition;
    view = const ViewTransform();
    isolatedBand = null;
    flipped = false;
    _stopDrawingLines();
    imageBytes = null;
    final old = image;
    image = null;
    if (old != null) {
      // The stage may still be rasterising the frame that shows it.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        SchedulerBinding.instance.addPostFrameCallback((_) => old.dispose());
        SchedulerBinding.instance.scheduleFrame();
      });
    }
    notifyListeners();
  }

  void startFreshStudy() {
    flushPersist();
    studyId = null;
    imageKey = null;
    name = 'Untitled study';
    settings = const StudySettings();
    splitPosition = settings.splitPosition;
    view = const ViewTransform();
    isolatedBand = null;
    flipped = false;
    _stopDrawingLines();
    openTool = null;
    chromeVisible = true;
    notifyListeners();
  }

  Study toStudy({String? id, DateTime? date}) => Study(
    id: id ?? studyId ?? DateTime.now().microsecondsSinceEpoch.toString(),
    name: name.trim().isEmpty ? 'Untitled study' : name.trim(),
    date: date ?? DateTime.now(),
    imageKey: imageKey ?? '',
    settings: settled,
  );

  /// The study settings as they stand, folding in the two things kept live for
  /// the duration of a gesture.
  StudySettings get settled =>
      settings.copyWith(splitPosition: splitPosition, view: view);

  /// Adopts settings that arrived over the QR transfer, wholesale — including
  /// the view, so the phone lands on the passage the sender was looking at.
  void applyTransferredSettings(StudySettings incoming) {
    settings = incoming;
    splitPosition = incoming.splitPosition;
    view = incoming.view;
    isolatedBand = null;
    lineStart = null;
    selectedLine = null;
    if (incoming.grid == GridMode.off) drawingLines = false;
    notifyListeners();
  }

  // --- study settings -----------------------------------------------------

  void setSteps(int steps) {
    if (steps == settings.steps) return;
    settings = settings.copyWith(
      steps: steps.clamp(StudySettings.minSteps, StudySettings.maxSteps),
    );
    // Band n of five is not band n of three; start from the whole picture.
    isolatedBand = null;
    _persistSoon();
    notifyListeners();
  }

  /// Moves the values and the detail together to one of
  /// [StudySettings.stages].
  void setStage(int index) {
    final stage = StudySettings.stages[index];
    if (stage.steps == settings.steps && stage.detail == settings.detail) {
      return;
    }
    if (stage.steps != settings.steps) isolatedBand = null;
    settings = settings.copyWith(steps: stage.steps, detail: stage.detail);
    _persistSoon();
    notifyListeners();
  }

  void setDetail(double detail) {
    final next = detail.clamp(0.0, 1.0);
    if (next == settings.detail) return;
    settings = settings.copyWith(detail: next);
    _persistSoon();
    notifyListeners();
  }

  void setSmoothing(Smoothing smoothing) {
    if (smoothing == settings.smoothing) return;
    settings = settings.copyWith(smoothing: smoothing);
    _persistSoon();
    notifyListeners();
  }

  void setLockDetail(bool value) {
    if (value == settings.lockDetail) return;
    settings = settings.copyWith(lockDetail: value);
    _persistSoon();
    notifyListeners();
  }

  void setBias(double bias) {
    final next = bias.clamp(-StudySettings.maxBias, StudySettings.maxBias);
    if (next == settings.bias) return;
    settings = settings.copyWith(bias: next);
    _persistSoon();
    notifyListeners();
  }

  void setContrast(double contrast) {
    final next = contrast.clamp(-1.0, 1.0);
    if (next == settings.contrast) return;
    settings = settings.copyWith(contrast: next);
    _persistSoon();
    notifyListeners();
  }

  void setScale(ValueScale scale) {
    if (scale == settings.scale) return;
    settings = settings.copyWith(scale: scale);
    _persistSoon();
    notifyListeners();
  }

  void setMode(ViewMode mode) {
    if (mode == settings.mode) {
      // Tapping RANDOM while it is showing is the gesture of the mode:
      // another deal of colours over the same values. Every other mode,
      // SPLIT included, treats a repeat tap as nothing new.
      if (mode != ViewMode.random) return;
      dealColours();
      return;
    } else {
      settings = settings.copyWith(
        mode: mode,
        // First entry into RANDOM gets a fresh deal too — seed 0 is the
        // never-dealt default, and without this every study's first palette
        // was seed 0's. A study saved in random mode reopens through
        // openStudy, not here, so a kept palette is never redrawn.
        randomSeed: mode == ViewMode.random && settings.randomSeed == 0
            ? math.Random().nextInt(1 << 31)
            : null,
        // Split and skeleton are laid over whatever was showing, so they
        // keep the colours they were entered from — a split compares them
        // against the photograph, the skeleton's fill blocks them in. From
        // anywhere else the base stays as it last was.
        splitBase: mode == ViewMode.split || mode == ViewMode.skeleton
            ? (settings.mode == ViewMode.random
                  ? ViewMode.random
                  : settings.mode == ViewMode.value
                  ? ViewMode.value
                  : settings.splitBase)
            : null,
      );
    }
    // A tool the new view's bar does not offer would be adjusting nothing.
    if (openTool case final tool?
        when !CanvasTool.barFor(settings.mode).contains(tool)) {
      openTool = null;
    }
    // VALUE and RANDOM share bands, so an isolated band survives moving
    // between them, and a new deal; anywhere else has no swatch to undo it.
    if (!settings.mode.paintsOnlyPalette) isolatedBand = null;
    _persistSoon();
    notifyListeners();
  }

  /// Another deal of RANDOM's colours over the same values.
  void dealColours() {
    // A fresh draw, not seed + 1: every study starts at seed 0, so an
    // incrementing seed dealt every study the same palette sequence. The
    // draw is still stored, so the palette survives repaint and reopening.
    settings = settings.copyWith(randomSeed: math.Random().nextInt(1 << 31));
    _persistSoon();
    notifyListeners();
  }

  void setTone(PhotoTone tone) {
    if (tone == settings.tone) return;
    settings = settings.copyWith(tone: tone);
    _persistSoon();
    notifyListeners();
  }

  void setGrid(GridMode grid) {
    if (grid == settings.grid) return;
    settings = settings.copyWith(grid: grid);
    // The lines go with the grid, and ruling ones nobody can see is no use.
    if (grid == GridMode.off) _stopDrawingLines();
    _persistSoon();
    notifyListeners();
  }

  void setGridLevel(int level) {
    final next = level.clamp(
      StudySettings.minGridLevel,
      StudySettings.maxGridLevel,
    );
    if (next == settings.gridLevel) return;
    settings = settings.copyWith(gridLevel: next);
    _persistSoon();
    notifyListeners();
  }

  /// Jump straight to a fill count — the desktop's segmented control.
  void setSkeletonFill(int fill) {
    final next = fill.clamp(0, settings.steps);
    if (next == settings.skeletonFill) return;
    settings = settings.copyWith(skeletonFill: next);
    _persistSoon();
    notifyListeners();
  }

  /// Each tap blocks in one more value, darkest first; past the last it
  /// returns to edges alone. The count survives a steps change by clamping
  /// at paint time rather than resetting here.
  void cycleSkeletonFill() {
    settings = settings.copyWith(
      skeletonFill: (settings.skeletonFill + 1) % (settings.steps + 1),
    );
    _persistSoon();
    notifyListeners();
  }

  /// The part of the picture on screen now, as [StudySettings.gridFrame]
  /// measures it. The zoom stays inside the picture's own frame, so which
  /// part shows does not depend on the room it is shown in, and the picture's
  /// own size will do for one.
  Rect get shownFrame =>
      _sourceSize.isEmpty ? kWholeImage : view.shown(_sourceSize, _sourceSize);

  /// Whether the grid already divides exactly what is on screen.
  bool get gridFitsView => settings.gridFrame == shownFrame;

  /// Lays the grid over what is on screen: the view framed by zooming becomes
  /// the board the grid divides, and zooming from here magnifies it.
  void resetGrid() {
    final frame = shownFrame;
    if (frame == settings.gridFrame) return;
    settings = settings.copyWith(gridFrame: frame);
    _persistSoon();
    notifyListeners();
  }

  /// Crops the study to [crop], a fraction of each side of the photograph,
  /// and shows the new picture whole: a zoom and pan chosen inside the old
  /// crop describe a different passage inside the new one, and so does a
  /// grid reset to one.
  void setCrop(Rect crop) {
    if (crop == settings.crop) return;
    settings = settings.copyWith(crop: crop, gridFrame: kWholeImage);
    view = const ViewTransform();
    _persistSoon();
    notifyListeners();
  }

  // --- lines ----------------------------------------------------------------

  void setDrawingLines(bool value) {
    if (value == drawingLines) return;
    if (value) {
      drawingLines = true;
    } else {
      _stopDrawingLines();
    }
    notifyListeners();
  }

  void _stopDrawingLines() {
    drawingLines = false;
    lineStart = null;
    selectedLine = null;
  }

  /// A click while ruling lines, at [point] on the photograph as [BoardLine]
  /// measures it. The first click of a line places its start; the second
  /// rules it. A second click on the first does nothing but forget it.
  void placeLineEnd(Offset point) {
    final start = lineStart;
    selectedLine = null;
    if (start == null) {
      lineStart = point;
    } else {
      lineStart = null;
      if (point != start) {
        settings = settings.copyWith(
          lines: [...settings.lines, BoardLine(start, point)],
        );
        _persistSoon();
      }
    }
    notifyListeners();
  }

  /// Moves one end, 0 or 1, of line [index] to [point] on the photograph.
  void moveLineEnd(int index, int end, Offset point) {
    final lines = [...settings.lines];
    final next = lines[index].withEnd(end, point);
    if (next == lines[index]) return;
    lines[index] = next;
    settings = settings.copyWith(lines: lines);
    _persistSoon();
    notifyListeners();
  }

  void selectLine(int? index) {
    if (index == selectedLine) return;
    selectedLine = index;
    notifyListeners();
  }

  /// Escape: forgets a half-ruled line or a selection, in that order.
  /// Returns whether there was either.
  bool cancelLine() {
    if (lineStart == null && selectedLine == null) return false;
    lineStart = null;
    selectedLine = null;
    notifyListeners();
    return true;
  }

  /// Removes the selected line. Returns whether there was one.
  bool deleteSelectedLine() {
    final index = selectedLine;
    if (index == null) return false;
    settings = settings.copyWith(lines: [...settings.lines]..removeAt(index));
    selectedLine = null;
    _persistSoon();
    notifyListeners();
    return true;
  }

  void clearLines() {
    if (settings.lines.isEmpty && lineStart == null) return;
    settings = settings.copyWith(lines: const []);
    lineStart = null;
    selectedLine = null;
    _persistSoon();
    notifyListeners();
  }

  void rename(String value) {
    name = value;
    _persistSoon();
    notifyListeners();
  }

  // --- view state ---------------------------------------------------------

  void setSplitPosition(double value, {bool settle = false}) {
    splitPosition = value.clamp(0.0, 1.0);
    if (settle) {
      settings = settings.copyWith(splitPosition: splitPosition);
      _persistSoon();
    }
    notifyListeners();
  }

  void setView(ViewTransform next) {
    if (next == view) return;
    view = next;
    // Debounced, so a pinch writes once when it settles rather than per frame.
    _persistSoon();
    notifyListeners();
  }

  /// Tapping a band shows it alone; tapping it again shows them all.
  void toggleIsolatedBand(int band) {
    isolatedBand = isolatedBand == band ? null : band;
    notifyListeners();
  }

  void setFlipped(bool value) {
    if (value == flipped) return;
    flipped = value;
    notifyListeners();
  }

  void setPeeking(bool value) {
    if (value == peeking) return;
    peeking = value;
    notifyListeners();
  }

  void toggleChrome() {
    chromeVisible = !chromeVisible;
    if (!chromeVisible) openTool = null;
    notifyListeners();
  }

  /// A single tap on the picture. With a tool's sheet open over it, the tap
  /// closes the sheet; otherwise it hides or shows the controls.
  void tapPicture() {
    if (chromeVisible && openTool != null) {
      closeTool();
      return;
    }
    toggleChrome();
  }

  void setChromeVisible(bool value) {
    if (value == chromeVisible) return;
    chromeVisible = value;
    notifyListeners();
  }

  /// Tapping the open tool closes it.
  void toggleTool(CanvasTool tool) {
    openTool = openTool == tool ? null : tool;
    notifyListeners();
  }

  void closeTool() {
    if (openTool == null) return;
    openTool = null;
    notifyListeners();
  }

  void setViewport(Size size, double dpr) {
    if (size == viewportSize && dpr == devicePixelRatio) return;
    viewportSize = size;
    devicePixelRatio = dpr;
  }

  /// Double tap cycles 1x -> 2.4x -> 4x -> 1x, centred on the tap point.
  void cycleZoom(Offset focus) {
    const stops = [1.0, 2.4, 4.0];
    final index = stops.indexWhere((z) => (z - view.zoom).abs() < 0.01);
    final next = stops[(index + 1) % stops.length];
    setView(view.zoomedAt(focus, next, _sourceSize, viewportSize));
  }

  Size get _sourceSize => image == null
      ? Size.zero
      : croppedSize(
          Size(image!.width.toDouble(), image!.height.toDouble()),
          settings.crop,
        );

  // --- keeping a saved study up to date -----------------------------------

  /// Nothing to write until a study has been kept on the shelf; an unsaved
  /// study is still just a view of a photograph.
  void _persistSoon() {
    if (studyId == null) return;
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(milliseconds: 400), _persistNow);
  }

  /// Writes any pending change immediately. Called before the open study is
  /// swapped out and when the canvas is left, so a change made in the last few
  /// hundred milliseconds is not lost.
  void flushPersist() {
    _persistDebounce?.cancel();
    _persistDebounce = null;
    _persistNow();
  }

  void _persistNow() {
    final id = studyId;
    if (id == null) return;
    onPersist?.call(id, settled, name);
  }

  /// Renders the pass this study needs at [outputPx] and waits for it, so the
  /// canvas is never put on screen showing the untouched photograph first.
  Future<void> warmBlur(Size outputPx) async {
    final source = image;
    if (source == null || outputPx.isEmpty) return;
    blur.request(
      source: source,
      outputPx: outputPx,
      detail: settings.detail,
      view: view,
      smoothing: settings.smoothing,
      lockDetail: settings.lockDetail,
      crop: settings.crop,
      steps: settings.steps,
      bias: settings.bias,
      contrast: settings.contrast,
    );
    if (settings.photoNeedsOwnPass) {
      photoBlur.request(
        source: source,
        outputPx: outputPx,
        detail: settings.detail,
        view: view,
        lockDetail: settings.lockDetail,
        crop: settings.crop,
      );
    }
    await Future.wait([blur.settled, photoBlur.settled]);
  }

  @override
  void dispose() {
    blur.dispose();
    photoBlur.dispose();
    _persistDebounce?.cancel();
    image?.dispose();
    super.dispose();
  }
}
