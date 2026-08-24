import 'dart:ui' show Offset;

import '../engine/engine.dart';
import '../engine/value_scale.dart';

enum GridMode {
  off('OFF'),
  square('SQUARE'),
  diamond('DIAMOND');

  const GridMode(this.label);
  final String label;
}

/// Everything a study remembers. Zoom, pan, peek, chrome visibility and the
/// open tool are deliberately absent: they are view state, not the study.
class StudySettings {
  const StudySettings({
    this.steps = 3,
    this.scale = ValueScale.grey,
    this.detail = 0.5,
    this.mode = ViewMode.value,
    this.grid = GridMode.off,
    this.gridDivisions = 4,
    this.skeletonFill = 0,
    this.smoothing = Smoothing.gaussian,
    this.lockDetail = false,
    this.bias = 0,
    this.splitPosition = 0.5,
    this.randomSeed = 0,
    this.splitBase = ViewMode.value,
    this.view = const ViewTransform(),
  });

  final int steps;
  final ValueScale scale;
  final double detail;
  final ViewMode mode;
  final GridMode grid;
  final int gridDivisions;

  /// Skeleton only: how many bands, darkest first, are blocked in with their
  /// ramp colour over the white ground — the way a painting is actually
  /// begun. 0 is edges alone; [steps] is every value placed.
  final int skeletonFill;

  /// How the photograph is simplified before it is quantised.
  final Smoothing smoothing;

  /// Whether the detail is locked against the zoom. Unlocked, the blur is
  /// in screen space — zooming in resolves finer shapes, the way leaning
  /// closer to a scene does. Locked, the simplification holds still against
  /// the photograph and zooming magnifies the same shapes instead.
  final bool lockDetail;

  /// Slides every threshold together, in fractions of the L* range.
  ///
  /// The steps stay evenly spaced, so a value still means what it always did;
  /// this only decides which side of a boundary a borderline passage falls
  /// on, which is what an under- or over-exposed photograph needs.
  final double bias;
  final double splitPosition;

  /// Which deal of colours the RANDOM mode is showing. Kept with the study so
  /// a palette that sparked something survives closing it; tapping RANDOM
  /// again moves the seed on.
  final int randomSeed;

  /// What split and skeleton lay their colours over: the scale's ramp or the
  /// random palette, whichever was on screen when the mode was entered — a
  /// split compares it against the photograph, the skeleton's fill blocks it
  /// in. Only [ViewMode.value] or [ViewMode.random].
  final ViewMode splitBase;

  /// Where the study was left: zoom, and pan as a fraction of the frame.
  ///
  /// The handoff notes list zoom and pan as view-only state, but a study you
  /// come back to should look like the one you left, and the shelf thumbnail
  /// should show the passage you were actually working on.
  final ViewTransform view;

  static const int minSteps = 2;
  static const int maxSteps = 7;
  static const int minDivisions = 2;
  static const int maxDivisions = 10;

  /// A quarter of the L* range in either direction is far more than anyone
  /// needs and still leaves every step reachable.
  static const double maxBias = 0.25;

  StudySettings copyWith({
    int? steps,
    ValueScale? scale,
    double? detail,
    ViewMode? mode,
    GridMode? grid,
    int? gridDivisions,
    int? skeletonFill,
    Smoothing? smoothing,
    bool? lockDetail,
    double? bias,
    double? splitPosition,
    int? randomSeed,
    ViewMode? splitBase,
    ViewTransform? view,
  }) => StudySettings(
    steps: steps ?? this.steps,
    scale: scale ?? this.scale,
    detail: detail ?? this.detail,
    mode: mode ?? this.mode,
    grid: grid ?? this.grid,
    gridDivisions: gridDivisions ?? this.gridDivisions,
    skeletonFill: skeletonFill ?? this.skeletonFill,
    smoothing: smoothing ?? this.smoothing,
    lockDetail: lockDetail ?? this.lockDetail,
    bias: bias ?? this.bias,
    splitPosition: splitPosition ?? this.splitPosition,
    randomSeed: randomSeed ?? this.randomSeed,
    splitBase: splitBase ?? this.splitBase,
    view: view ?? this.view,
  );

  Map<String, Object?> toJson() => {
    'steps': steps,
    'scale': scale.toJson(),
    'detail': detail,
    'mode': mode.name,
    'grid': grid.name,
    'gridDivisions': gridDivisions,
    'skeletonFill': skeletonFill,
    'smoothing': smoothing.name,
    'lockDetail': lockDetail,
    'bias': bias,
    'splitPosition': splitPosition,
    'randomSeed': randomSeed,
    'splitBase': splitBase.name,
    'zoom': view.zoom,
    'panX': view.offset.dx,
    'panY': view.offset.dy,
  };

  /// Tolerant by design: a manifest written by an older build, or one that has
  /// been hand-edited, should cost the affected field rather than the shelf.
  static StudySettings fromJson(Map<String, Object?> json) => StudySettings(
    steps: _int(json['steps'], 3).clamp(minSteps, maxSteps),
    scale: ValueScale.fromJson(json['scale']),
    detail: _double(json['detail'], 0.5).clamp(0.0, 1.0),
    mode: _enumByName(ViewMode.values, json['mode'], ViewMode.value),
    grid: _enumByName(GridMode.values, json['grid'], GridMode.off),
    gridDivisions: _int(
      json['gridDivisions'],
      4,
    ).clamp(minDivisions, maxDivisions),
    skeletonFill: _int(json['skeletonFill'], 0).clamp(0, maxSteps),
    smoothing: _enumByName(
      Smoothing.values,
      json['smoothing'],
      Smoothing.gaussian,
    ),
    lockDetail: json['lockDetail'] is bool
        ? json['lockDetail']! as bool
        // One build persisted this inverted, as adaptiveDetail.
        : json['adaptiveDetail'] is bool
        ? !(json['adaptiveDetail']! as bool)
        : false,
    bias: _double(json['bias'], 0).clamp(-maxBias, maxBias),
    splitPosition: _double(json['splitPosition'], 0.5).clamp(0.0, 1.0),
    randomSeed: _int(json['randomSeed'], 0),
    splitBase:
        _enumByName(ViewMode.values, json['splitBase'], ViewMode.value) ==
            ViewMode.random
        ? ViewMode.random
        : ViewMode.value,
    view: ViewTransform(
      zoom: _double(
        json['zoom'],
        1,
      ).clamp(ViewTransform.minZoom, ViewTransform.maxZoom),
      offset: Offset(_double(json['panX'], 0), _double(json['panY'], 0)),
    ),
  );

  @override
  bool operator ==(Object other) =>
      other is StudySettings &&
      other.steps == steps &&
      other.scale == scale &&
      other.detail == detail &&
      other.mode == mode &&
      other.grid == grid &&
      other.gridDivisions == gridDivisions &&
      other.skeletonFill == skeletonFill &&
      other.smoothing == smoothing &&
      other.lockDetail == lockDetail &&
      other.bias == bias &&
      other.splitPosition == splitPosition &&
      other.randomSeed == randomSeed &&
      other.splitBase == splitBase &&
      other.view == view;

  @override
  int get hashCode => Object.hash(
    steps,
    scale,
    detail,
    mode,
    grid,
    gridDivisions,
    skeletonFill,
    smoothing,
    lockDetail,
    bias,
    splitPosition,
    randomSeed,
    splitBase,
    view,
  );
}

/// A study on the shelf. [imageKey] names a copy of the source image held in
/// app storage rather than a photo-library reference, which can be revoked.
class Study {
  const Study({
    required this.id,
    required this.name,
    required this.date,
    required this.imageKey,
    required this.settings,
  });

  final String id;
  final String name;
  final DateTime date;
  final String imageKey;
  final StudySettings settings;

  Study copyWith({String? name, DateTime? date, StudySettings? settings}) =>
      Study(
        id: id,
        name: name ?? this.name,
        date: date ?? this.date,
        imageKey: imageKey,
        settings: settings ?? this.settings,
      );

  /// The shelf caption: "3 values · grey · 8 Aug".
  String get caption =>
      '${settings.steps} values · ${settings.scale.shortName} · $formattedDate';

  String get formattedDate => '${date.day} ${_months[date.month - 1]}';

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'date': date.toIso8601String(),
    'imageKey': imageKey,
    'settings': settings.toJson(),
  };

  /// Returns null for an entry too damaged to be a study — one with no id or
  /// no source image. The shelf drops those rather than failing to load.
  static Study? fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final imageKey = json['imageKey'];
    if (id is! String || id.isEmpty) return null;
    if (imageKey is! String || imageKey.isEmpty) return null;
    final name = json['name'];
    final date = json['date'];
    return Study(
      id: id,
      name: name is String && name.trim().isNotEmpty ? name : 'Untitled study',
      date: (date is String ? DateTime.tryParse(date) : null) ?? DateTime.now(),
      imageKey: imageKey,
      settings: StudySettings.fromJson(
        (json['settings'] as Map?)?.cast<String, Object?>() ?? const {},
      ),
    );
  }
}

int _int(Object? value, int fallback) =>
    value is num ? value.toInt() : fallback;

double _double(Object? value, double fallback) =>
    value is num ? value.toDouble() : fallback;

T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

/// Slugified for an export filename: "portrait-yellow-wall-1200x1800.png".
String slugify(String name) {
  final slug = name
      .toLowerCase()
      .replaceAll(RegExp(r"[^a-z0-9]+"), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.isEmpty ? 'study' : slug;
}
