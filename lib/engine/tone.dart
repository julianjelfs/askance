import 'dart:math' as math;

/// The picture's tone: a lightness [v] from 0 to 1 as the study sees it once
/// [shift] and [contrast] have been applied. The value map bands this, and
/// PHOTO, a peek and SPLIT's photograph show it, so what is blocked in is
/// the picture you are looking at.
///
/// Contrast pivots on the middle; full travel either way is 4x steeper or
/// flatter, which spreads the steps apart or squeezes them together. Shift
/// slides every value at once, which moves where the steps fall.
/// `shaders/askance.frag` and `shaders/photo.frag` hold the same curve.
double toneCurve(double v, {required double shift, required double contrast}) =>
    _unclamped(v, shift, contrast).clamp(0.0, 1.0);

/// The lightness [toneCurve] takes to [toned], unclamped: below 0 or above
/// 1 when no lightness reaches it.
double toneUncurve(
  double toned, {
  required double shift,
  required double contrast,
}) => (toned - 0.5 - shift) / math.pow(4, contrast) + 0.5;

/// [toneCurve] before it is clamped: where black and white land.
double toneReach(double v, {required double shift, required double contrast}) =>
    _unclamped(v, shift, contrast);

double _unclamped(double v, double shift, double contrast) =>
    (v - 0.5) * math.pow(4, contrast) + 0.5 + shift;

/// How PHOTO draws the picture: in colour or black and white, sharp or
/// blurred by the study's own detail. Ways of looking only; neither changes
/// the values.
class PhotoTone {
  const PhotoTone({this.mono = false, this.squint = false});

  final bool mono;

  /// Blurred as the study blurs it before banding, so PHOTO shows the
  /// picture the values are cut from.
  final bool squint;

  PhotoTone copyWith({bool? mono, bool? squint}) =>
      PhotoTone(mono: mono ?? this.mono, squint: squint ?? this.squint);

  Map<String, Object?> toJson() => {'mono': mono, 'squint': squint};

  static PhotoTone fromJson(Object? json) {
    if (json is! Map) return const PhotoTone();
    return PhotoTone(
      mono: json['mono'] == true,
      // Written before the blur was the study's detail: any blur at all
      // meant the photograph was being squinted at.
      squint:
          json['squint'] == true ||
          (json['blur'] is num && (json['blur'] as num) > 0),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PhotoTone && other.mono == mono && other.squint == squint;

  @override
  int get hashCode => Object.hash(mono, squint);
}
