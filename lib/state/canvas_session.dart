import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../engine/engine.dart';
import '../engine/regions.dart';
import '../engine/value_painter.dart';
import '../engine/value_scale.dart';
import '../model/study.dart';

enum CanvasTool { steps, detail, scale, grid }

/// The open study, plus the view state that is deliberately *not* part of a
/// study: zoom, pan, peek, chrome visibility and which tool is open.
class CanvasSession extends ChangeNotifier {
  ui.Image? image;

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
    studyId = study.id;
    name = study.name;
    imageKey = study.imageKey;
    settings = study.settings;
    splitPosition = study.settings.splitPosition;
    view = const ViewTransform();
    openTool = null;
    chromeVisible = true;
    _scheduleRegions();
    notifyListeners();
  }

  void startFreshStudy() {
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
    settings: settings.copyWith(splitPosition: splitPosition),
  );

  // --- study settings -----------------------------------------------------

  void setSteps(int steps) {
    if (steps == settings.steps) return;
    settings = settings.copyWith(
      steps: steps.clamp(StudySettings.minSteps, StudySettings.maxSteps),
    );
    _scheduleRegions();
    notifyListeners();
  }

  void setDetail(double detail) {
    final next = detail.clamp(0.0, 1.0);
    if (next == settings.detail) return;
    settings = settings.copyWith(detail: next);
    _scheduleRegions();
    notifyListeners();
  }

  void setScale(ValueScale scale) {
    if (scale == settings.scale) return;
    settings = settings.copyWith(scale: scale);
    notifyListeners();
  }

  void setMode(ViewMode mode) {
    if (mode == settings.mode) return;
    settings = settings.copyWith(mode: mode);
    if (mode == ViewMode.skeleton) _scheduleRegions();
    notifyListeners();
  }

  void setGrid(GridMode grid) {
    if (grid == settings.grid) return;
    settings = settings.copyWith(grid: grid);
    notifyListeners();
  }

  void setGridDivisions(int divisions) {
    final next = divisions.clamp(
      StudySettings.minDivisions,
      StudySettings.maxDivisions,
    );
    if (next == settings.gridDivisions) return;
    settings = settings.copyWith(gridDivisions: next);
    notifyListeners();
  }

  void toggleNumbers() {
    settings = settings.copyWith(numbers: !settings.numbers);
    if (settings.numbers) _scheduleRegions();
    notifyListeners();
  }

  void rename(String value) {
    name = value;
    notifyListeners();
  }

  // --- view state ---------------------------------------------------------

  void setSplitPosition(double value, {bool settle = false}) {
    splitPosition = value.clamp(0.0, 1.0);
    if (settle) settings = settings.copyWith(splitPosition: splitPosition);
    notifyListeners();
  }

  void setView(ViewTransform next) {
    if (next == view) return;
    view = next;
    _scheduleRegions();
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
    final stride = labelStride(outputPx.width);
    final gw = (outputPx.width / stride).floor();
    final gh = (outputPx.height / stride).floor();
    final found = await computeRegions(
      source: source,
      outputPx: outputPx,
      detail: settings.detail,
      view: view,
      steps: settings.steps,
    );
    // A newer request landed while this one was in flight.
    if (request != _regionRequest) return;
    regions = RegionOverlay(regions: found, gridWidth: gw, gridHeight: gh);
    notifyListeners();
  }

  @override
  void dispose() {
    _regionDebounce?.cancel();
    image?.dispose();
    super.dispose();
  }
}
