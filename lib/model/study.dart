import 'dart:ui' show Color, Offset, Rect;

import '../engine/crop.dart';
import '../engine/engine.dart';
import '../engine/random_ramp.dart';
import '../engine/tone.dart';
import '../engine/value_scale.dart';

export '../engine/tone.dart' show PhotoTone;

/// The grid divides the photograph, not the view: at every level each cell is
/// halved both ways, so the cells are always the picture's own shape. LINES
/// is the verticals and horizontals alone; DIAGONALS adds both diagonals of
/// every cell as it is halved, which chain corner to corner into rules across
/// the whole picture.
enum GridMode {
  off('Off'),
  lines('Lines'),
  diagonals('Diagonals');

  const GridMode(this.label);
  final String label;

  /// Manifests written before the grid was a division of the whole.
  static GridMode fromLegacyName(Object? name) => switch (name) {
    'square' => lines,
    'diamond' => diagonals,
    _ => off,
  };
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
    this.gridLevel = 2,
    this.skeletonFill = 0,
    this.smoothing = Smoothing.gaussian,
    this.lockDetail = false,
    this.bias = 0,
    this.contrast = 0,
    this.splitPosition = 0.5,
    this.randomSeed = 0,
    this.splitBase = ViewMode.value,
    this.view = const ViewTransform(),
    this.crop = kWholeImage,
    this.gridFrame = kWholeImage,
    this.tone = const PhotoTone(),
  });

  final int steps;
  final ValueScale scale;
  final double detail;
  final ViewMode mode;
  final GridMode grid;

  /// How many times the picture has been halved at 1×: level 1 is the four
  /// quadrants, level 2 halves each of those, and so on. Zooming in halves
  /// further on its own, so this is a density rather than a fixed grid.
  final int gridLevel;

  /// The part of the picture the grid divides, as a fraction of each side of
  /// the crop. The whole of it until the grid is reset to a zoomed view: the
  /// passage framed there is what goes on the board, and zooming further only
  /// magnifies the grid with the picture.
  final Rect gridFrame;

  /// Cells across (and down) at the current level.
  int get gridDivisions => divisionsAt(gridLevel);
  static int divisionsAt(int level) => 1 << level;

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

  /// Spreads the steps apart, -1..1, or squeezes them together, about the
  /// middle of the range. Up, the middle values split into more of the
  /// steps and the darks and lights merge; down, the reverse. With [bias],
  /// the picture's tone curve: the value map bands the photograph through
  /// it, and PHOTO shows the photograph through it.
  final double contrast;
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

  /// The part of the photograph the study is of, as a fraction of each side.
  /// Everything else — the framing, the zoom, the grid, the exports — treats
  /// the crop as the photograph, so a grid laid over an A4 crop divides an A4
  /// board.
  final Rect crop;

  /// How PHOTO draws the photograph.
  final PhotoTone tone;

  /// Whether PHOTO's blurred photograph needs a pass of its own. Smooth's
  /// pass is already the photograph blurred by the detail; ROUGH and BLOCK
  /// shape theirs further.
  bool get photoNeedsOwnPass => smoothing != Smoothing.gaussian;

  /// Whether the tone curve leaves the photograph as it is.
  bool get keepsTone => bias == 0 && contrast == 0;

  /// The colours the processed image is painted in, darkest first: the
  /// scale's ramp, or the random deal when RANDOM is showing or is what split
  /// and skeleton are laid over. The painter and the palette swatch both read
  /// this, so the swatch can never show a colour the picture doesn't use.
  List<Color> get palette =>
      mode == ViewMode.random ||
          ((mode == ViewMode.split || mode == ViewMode.skeleton) &&
              splitBase == ViewMode.random)
      ? randomRamp(scale: scale, steps: steps, seed: randomSeed)
      : scale.ramp(steps);

  /// The stages a drawing is built up through, coarsest first: at each one
  /// the picture gains a value and its shapes get finer together, the way a
  /// study is blocked in with two values and a few big shapes and then
  /// refined. Edit freely; nothing is stored against a stage's position.
  static const List<({int steps, double detail})> stages = [
    (steps: 2, detail: 0.3),
    (steps: 3, detail: 0.4),
    (steps: 4, detail: 0.5),
    (steps: 5, detail: 0.6),
    (steps: 6, detail: 0.7),
    (steps: 7, detail: 0.8),
  ];

  /// Which of [stages] the values and detail are at, or null once either has
  /// been moved by hand.
  int? get stage {
    final index = stages.indexWhere(
      (s) => s.steps == steps && s.detail == detail,
    );
    return index < 0 ? null : index;
  }

  static const int minSteps = 2;
  static const int maxSteps = 7;
  static const int minGridLevel = 1;
  static const int maxGridLevel = 4;

  /// A quarter of the L* range in either direction is far more than anyone
  /// needs and still leaves every step reachable.
  static const double maxBias = 0.25;

  StudySettings copyWith({
    int? steps,
    ValueScale? scale,
    double? detail,
    ViewMode? mode,
    GridMode? grid,
    int? gridLevel,
    int? skeletonFill,
    Smoothing? smoothing,
    bool? lockDetail,
    double? bias,
    double? contrast,
    double? splitPosition,
    int? randomSeed,
    ViewMode? splitBase,
    ViewTransform? view,
    Rect? crop,
    Rect? gridFrame,
    PhotoTone? tone,
  }) => StudySettings(
    steps: steps ?? this.steps,
    scale: scale ?? this.scale,
    detail: detail ?? this.detail,
    mode: mode ?? this.mode,
    grid: grid ?? this.grid,
    gridLevel: gridLevel ?? this.gridLevel,
    skeletonFill: skeletonFill ?? this.skeletonFill,
    smoothing: smoothing ?? this.smoothing,
    lockDetail: lockDetail ?? this.lockDetail,
    bias: bias ?? this.bias,
    contrast: contrast ?? this.contrast,
    splitPosition: splitPosition ?? this.splitPosition,
    randomSeed: randomSeed ?? this.randomSeed,
    splitBase: splitBase ?? this.splitBase,
    view: view ?? this.view,
    crop: crop ?? this.crop,
    gridFrame: gridFrame ?? this.gridFrame,
    tone: tone ?? this.tone,
  );

  Map<String, Object?> toJson() => {
    'steps': steps,
    'scale': scale.toJson(),
    'detail': detail,
    'mode': mode.name,
    'grid': grid.name,
    'gridLevel': gridLevel,
    'skeletonFill': skeletonFill,
    'smoothing': smoothing.name,
    'lockDetail': lockDetail,
    'bias': bias,
    'contrast': contrast,
    'splitPosition': splitPosition,
    'randomSeed': randomSeed,
    'splitBase': splitBase.name,
    'zoom': view.zoom,
    'panX': view.offset.dx,
    'panY': view.offset.dy,
    'crop': cropToJson(crop),
    'gridFrame': cropToJson(gridFrame),
    'tone': tone.toJson(),
  };

  /// Tolerant by design: a manifest written by an older build, or one that has
  /// been hand-edited, should cost the affected field rather than the shelf.
  static StudySettings fromJson(Map<String, Object?> json) => StudySettings(
    steps: _int(json['steps'], 3).clamp(minSteps, maxSteps),
    scale: ValueScale.fromJson(json['scale']),
    detail: _double(json['detail'], 0.5).clamp(0.0, 1.0),
    mode: _enumByName(ViewMode.values, json['mode'], ViewMode.value),
    grid: _enumByName(
      GridMode.values,
      json['grid'],
      GridMode.fromLegacyName(json['grid']),
    ),
    gridLevel: _gridLevel(json),
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
    // Contrast was once PHOTO's alone, kept with the rest of its tone.
    contrast: _double(
      json['contrast'] ??
          (json['tone'] is Map ? (json['tone'] as Map)['contrast'] : null),
      0,
    ).clamp(-1.0, 1.0),
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
    crop: cropFromJson(json['crop']),
    // Stored and checked the same way as the crop: a rect inside the picture.
    gridFrame: cropFromJson(json['gridFrame']),
    tone: PhotoTone.fromJson(json['tone']),
  );

  @override
  bool operator ==(Object other) =>
      other is StudySettings &&
      other.steps == steps &&
      other.scale == scale &&
      other.detail == detail &&
      other.mode == mode &&
      other.grid == grid &&
      other.gridLevel == gridLevel &&
      other.skeletonFill == skeletonFill &&
      other.smoothing == smoothing &&
      other.lockDetail == lockDetail &&
      other.bias == bias &&
      other.contrast == contrast &&
      other.splitPosition == splitPosition &&
      other.randomSeed == randomSeed &&
      other.splitBase == splitBase &&
      other.view == view &&
      other.crop == crop &&
      other.gridFrame == gridFrame &&
      other.tone == tone;

  @override
  int get hashCode => Object.hash(
    steps,
    scale,
    detail,
    mode,
    grid,
    gridLevel,
    skeletonFill,
    smoothing,
    lockDetail,
    bias,
    contrast,
    splitPosition,
    randomSeed,
    splitBase,
    view,
    crop,
    gridFrame,
    tone,
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

/// The level, or the nearest level to a legacy division count: 2–10 cells
/// across becomes 1, 2 or 3 halvings.
int _gridLevel(Map<String, Object?> json) {
  if (json['gridLevel'] is num) {
    return _int(
      json['gridLevel'],
      2,
    ).clamp(StudySettings.minGridLevel, StudySettings.maxGridLevel);
  }
  final divisions = _int(json['gridDivisions'], 4);
  var level = StudySettings.minGridLevel;
  while (level < StudySettings.maxGridLevel &&
      StudySettings.divisionsAt(level + 1) - divisions <
          divisions - StudySettings.divisionsAt(level)) {
    level++;
  }
  return level;
}

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
