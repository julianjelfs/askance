import 'dart:math' as math;

/// How PHOTO shows the photograph: in colour or black and white, with
/// brightness, contrast and blur. PHOTO, a peek and SPLIT's photograph show
/// it, and the value map is made from the photograph as it leaves.
class PhotoTone {
  const PhotoTone({
    this.mono = false,
    this.brightness = 0,
    this.contrast = 0,
    this.blur = 0,
  });

  final bool mono;

  /// -1..1, 0 untouched.
  final double brightness;

  /// -1..1, 0 untouched.
  final double contrast;

  /// 0..1, 0 sharp. Squinting at the photograph: the same screen-space blur
  /// the study simplifies with, at full travel as soft as the lowest detail.
  final double blur;

  /// Brightness and contrast, the part of the tone that moves a pixel's
  /// value: [v], a channel or a lightness from 0 to 1, as PHOTO shows it.
  /// Contrast pivots on the middle; full travel either way is 4x steeper or
  /// flatter. Brightness slides by up to half the range. `shaders/photo.frag`
  /// and `shaders/askance.frag` hold the same curve.
  double curve(double v) =>
      ((v - 0.5) * math.pow(4, contrast) + 0.5 + brightness * 0.5).clamp(
        0.0,
        1.0,
      );

  /// The [v] that [curve] takes to [toned], unclamped: below 0 or above 1
  /// when no value reaches it.
  double uncurve(double toned) =>
      (toned - 0.5 - brightness * 0.5) / math.pow(4, contrast) + 0.5;

  /// Whether [curve] leaves every value where it was.
  bool get keepsValues => brightness == 0 && contrast == 0;

  bool get isNeutral => !mono && brightness == 0 && contrast == 0 && blur == 0;

  PhotoTone copyWith({
    bool? mono,
    double? brightness,
    double? contrast,
    double? blur,
  }) => PhotoTone(
    mono: mono ?? this.mono,
    brightness: brightness ?? this.brightness,
    contrast: contrast ?? this.contrast,
    blur: blur ?? this.blur,
  );

  Map<String, Object?> toJson() => {
    'mono': mono,
    'brightness': brightness,
    'contrast': contrast,
    'blur': blur,
  };

  static PhotoTone fromJson(Object? json) {
    if (json is! Map) return const PhotoTone();
    return PhotoTone(
      mono: json['mono'] == true,
      brightness: _number(json['brightness'], 0).clamp(-1.0, 1.0),
      contrast: _number(json['contrast'], 0).clamp(-1.0, 1.0),
      blur: _number(json['blur'], 0).clamp(0.0, 1.0),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PhotoTone &&
      other.mono == mono &&
      other.brightness == brightness &&
      other.contrast == contrast &&
      other.blur == blur;

  @override
  int get hashCode => Object.hash(mono, brightness, contrast, blur);
}

double _number(Object? value, double fallback) =>
    value is num ? value.toDouble() : fallback;
