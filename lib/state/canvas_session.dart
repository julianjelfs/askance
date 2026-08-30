import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/scheduler.dart';

import '../engine/engine.dart';
import '../engine/blur_pass.dart';
import '../engine/value_scale.dart';
import '../model/study.dart';

enum CanvasTool { steps, detail, scale, grid }

/// The open study, plus the view state that is deliberately *not* part of a
/// study: zoom, pan, peek, chrome visibility and which tool is open.
class CanvasSession extends ChangeNotifier {
  ui.Image? image;

  /// Owned here rather than by the canvas widget so that every view of this
  /// study — the canvas, and the copy that flies during the open transition —
  /// shares one finished pass instead of each starting from nothing.
  final BlurPass blur = BlurPass();

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
  bool chromeVisible = true;
  CanvasTool? openTool;

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
    notifyListeners();
  }

  // --- study settings -----------------------------------------------------

  void setSteps(int steps) {
    if (steps == settings.steps) return;
    settings = settings.copyWith(
      steps: steps.clamp(StudySettings.minSteps, StudySettings.maxSteps),
    );
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
      // A fresh draw, not seed + 1: every study starts at seed 0, so an
      // incrementing seed dealt every study the same palette sequence. The
      // draw is still stored, so the palette survives repaint and reopening.
      settings = settings.copyWith(randomSeed: math.Random().nextInt(1 << 31));
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
    _persistSoon();
    notifyListeners();
  }

  void setGrid(GridMode grid) {
    if (grid == settings.grid) return;
    settings = settings.copyWith(grid: grid);
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
      : Size(image!.width.toDouble(), image!.height.toDouble());

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
    );
    await blur.settled;
  }

  @override
  void dispose() {
    blur.dispose();
    _persistDebounce?.cancel();
    image?.dispose();
    super.dispose();
  }
}
