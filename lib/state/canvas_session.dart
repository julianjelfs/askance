import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../engine/engine.dart';
import '../engine/blur_pass.dart';
import '../engine/regions.dart';
import '../engine/value_painter.dart';
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

  RegionOverlay? regions;

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
  Timer? _regionDebounce;
  int _regionRequest = 0;

  bool get hasImage => image != null;

  void loadImage(ui.Image decoded, Uint8List bytes, {String? key}) {
    image?.dispose();
    image = decoded;
    imageBytes = bytes;
    imageKey = key ?? imageKey;
    view = const ViewTransform();
    _scheduleRegions();
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
    _scheduleRegions();
    notifyListeners();
  }

  void startFreshStudy() {
    flushPersist();
    studyId = null;
    name = 'Untitled study';
    settings = const StudySettings();
    splitPosition = settings.splitPosition;
    view = const ViewTransform();
    openTool = null;
    chromeVisible = true;
    regions = null;
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

  // --- study settings -----------------------------------------------------

  void setSteps(int steps) {
    if (steps == settings.steps) return;
    settings = settings.copyWith(
      steps: steps.clamp(StudySettings.minSteps, StudySettings.maxSteps),
    );
    _scheduleRegions();
    _persistSoon();
    notifyListeners();
  }

  void setDetail(double detail) {
    final next = detail.clamp(0.0, 1.0);
    if (next == settings.detail) return;
    settings = settings.copyWith(detail: next);
    _scheduleRegions();
    _persistSoon();
    notifyListeners();
  }

  void setSmoothing(Smoothing smoothing) {
    if (smoothing == settings.smoothing) return;
    settings = settings.copyWith(smoothing: smoothing);
    _scheduleRegions();
    _persistSoon();
    notifyListeners();
  }

  void setBias(double bias) {
    final next = bias.clamp(-StudySettings.maxBias, StudySettings.maxBias);
    if (next == settings.bias) return;
    settings = settings.copyWith(bias: next);
    _scheduleRegions();
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
      settings = settings.copyWith(randomSeed: settings.randomSeed + 1);
    } else {
      settings = settings.copyWith(
        mode: mode,
        // A split is a comparison laid over whatever was showing, so it keeps
        // the colours it was entered from; from anywhere else it keeps the
        // base it last had.
        splitBase: mode == ViewMode.split
            ? (settings.mode == ViewMode.random
                  ? ViewMode.random
                  : settings.mode == ViewMode.value
                  ? ViewMode.value
                  : settings.splitBase)
            : null,
      );
      if (mode == ViewMode.skeleton) _scheduleRegions();
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

  void setGridDivisions(int divisions) {
    final next = divisions.clamp(
      StudySettings.minDivisions,
      StudySettings.maxDivisions,
    );
    if (next == settings.gridDivisions) return;
    settings = settings.copyWith(gridDivisions: next);
    _persistSoon();
    notifyListeners();
  }

  void toggleNumbers() {
    settings = settings.copyWith(numbers: !settings.numbers);
    if (settings.numbers) _scheduleRegions();
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
    _scheduleRegions();
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
    _scheduleRegions();
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

  // --- value numbers ------------------------------------------------------

  void _scheduleRegions() {
    if (settings.mode != ViewMode.skeleton || !settings.numbers) return;
    _regionDebounce?.cancel();
    _regionDebounce = Timer(
      const Duration(milliseconds: 150),
      _recomputeRegions,
    );
  }

  Future<void> _recomputeRegions() async {
    final source = image;
    if (source == null || viewportSize.isEmpty) return;
    final request = ++_regionRequest;
    final outputPx = Size(
      viewportSize.width * devicePixelRatio,
      viewportSize.height * devicePixelRatio,
    );
    final found = await computeRegions(
      source: source,
      outputPx: outputPx,
      detail: settings.detail,
      view: view,
      steps: settings.steps,
      bias: settings.bias,
      smoothing: settings.smoothing,
    );
    // A newer request landed while this one was in flight.
    if (request != _regionRequest) return;
    regions = RegionOverlay(
      regions: found.regions,
      gridWidth: found.gridWidth,
      gridHeight: found.gridHeight,
    );
    notifyListeners();
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
    );
    await blur.settled;
  }

  @override
  void dispose() {
    blur.dispose();
    _persistDebounce?.cancel();
    _regionDebounce?.cancel();
    image?.dispose();
    super.dispose();
  }
}
