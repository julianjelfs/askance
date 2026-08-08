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
    this.scale = ValueScale.graphite,
    this.detail = 0.5,
    this.mode = ViewMode.value,
    this.grid = GridMode.off,
    this.gridDivisions = 4,
    this.numbers = true,
    this.splitPosition = 0.5,
  });

  final int steps;
  final ValueScale scale;
  final double detail;
  final ViewMode mode;
  final GridMode grid;
  final int gridDivisions;
  final bool numbers;
  final double splitPosition;

  static const int minSteps = 2;
  static const int maxSteps = 7;
  static const int minDivisions = 2;
  static const int maxDivisions = 10;

  StudySettings copyWith({
    int? steps,
    ValueScale? scale,
    double? detail,
    ViewMode? mode,
    GridMode? grid,
    int? gridDivisions,
    bool? numbers,
    double? splitPosition,
  }) => StudySettings(
    steps: steps ?? this.steps,
    scale: scale ?? this.scale,
    detail: detail ?? this.detail,
    mode: mode ?? this.mode,
    grid: grid ?? this.grid,
    gridDivisions: gridDivisions ?? this.gridDivisions,
    numbers: numbers ?? this.numbers,
    splitPosition: splitPosition ?? this.splitPosition,
  );

  Map<String, Object?> toJson() => {
    'steps': steps,
    'scale': scale.name,
    'detail': detail,
    'mode': mode.name,
    'grid': grid.name,
    'gridDivisions': gridDivisions,
    'numbers': numbers,
    'splitPosition': splitPosition,
  };

  /// Tolerant by design: a manifest written by an older build, or one that has
  /// been hand-edited, should cost the affected field rather than the shelf.
  static StudySettings fromJson(Map<String, Object?> json) => StudySettings(
    steps: _int(json['steps'], 3).clamp(minSteps, maxSteps),
    scale: _enumByName(ValueScale.values, json['scale'], ValueScale.graphite),
    detail: _double(json['detail'], 0.5).clamp(0.0, 1.0),
    mode: _enumByName(ViewMode.values, json['mode'], ViewMode.value),
    grid: _enumByName(GridMode.values, json['grid'], GridMode.off),
    gridDivisions: _int(
      json['gridDivisions'],
      4,
    ).clamp(minDivisions, maxDivisions),
    numbers: json['numbers'] is bool ? json['numbers']! as bool : true,
    splitPosition: _double(json['splitPosition'], 0.5).clamp(0.0, 1.0),
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
      other.numbers == numbers &&
      other.splitPosition == splitPosition;

  @override
  int get hashCode => Object.hash(
    steps,
    scale,
    detail,
    mode,
    grid,
    gridDivisions,
    numbers,
    splitPosition,
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
