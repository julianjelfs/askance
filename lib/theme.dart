import 'package:flutter/widgets.dart';

/// The Modernist design system: flat, zero corner radius anywhere, 2px rules,
/// flush-left labels, one accent red used sparingly.
abstract final class AskanceColors {
  /// Chrome ground, dark screens, text on light.
  static const ink = Color(0xFF201E1D);

  /// Light screens, text on dark.
  static const ground = Color(0xFFF3F2F2);

  /// Card fills, desktop stage.
  static const surface = Color(0xFFEAE9E9);

  /// Active state, primary action, grid rules, split rule.
  static const accent = Color(0xFFEC3013);

  /// Hover / pressed on primary.
  static const accentPressed = Color(0xFFDD2B0F);

  /// Was 0x66; lightened so the shelf's furniture recedes behind the work.
  static const dividerLight = Color(0x40201E1D);
  static const dividerDark = Color(0x38F3F2F2);
  static const mutedLight = Color(0x8C201E1D);
  static const mutedDark = Color(0x80F3F2F2);

  /// Grid rules, drawn in screen space over everything.
  static const grid = Color(0xA6EC3013);

  /// Track behind a segmented control on a dark ground.
  static const trackDark = Color(0x1AF3F2F2);

  /// Border around an inactive scale swatch.
  static const swatchBorder = Color(0x40F3F2F2);

  /// Dashed border of an empty shelf slot.
  static const emptySlot = Color(0x4D201E1D);
}

/// Radius is 0 everywhere. No exceptions. Rules are 2px, never hairlines.
const double kRule = 2;

/// The one amendment to "2px, never hairlines": grey furniture on the light
/// shelf — card borders, separators, outlined buttons — read heavy at 2px,
/// so those thin down. Structural rules and everything on ink stay [kRule].
const double kRuleThin = 1;

/// Every phone screen was drawn at this width and scales proportionally.
const double kDesignWidth = 320;

/// The width at which the phone layout gives way to the rail-and-stage layout.
const double kDesktopBreakpoint = 900;

/// Motion, all from the design tokens table.
abstract final class AskanceMotion {
  static const Curve slide = Cubic(0.2, 0.8, 0.2, 1);
  static const segmentedMarker = Duration(milliseconds: 220);
  static const chromeFade = Duration(milliseconds: 220);
  static const sheetSlide = Duration(milliseconds: 320);
  static const peekThreshold = Duration(milliseconds: 280);
  static const doubleTapWindow = Duration(milliseconds: 300);
  static const purchase = Duration(milliseconds: 900);
}

/// Proportional scale for the phone layout, so a design drawn at 320pt reads
/// the same on a 430pt phone. Capped so it does not become cartoonish on the
/// widest devices.
class DesignScale extends InheritedWidget {
  const DesignScale({super.key, required this.factor, required super.child});

  final double factor;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DesignScale>()?.factor ?? 1;

  static double forWidth(double width) =>
      (width / kDesignWidth).clamp(1.0, 1.35).toDouble();

  @override
  bool updateShouldNotify(DesignScale old) => old.factor != factor;
}

extension DesignScaleContext on BuildContext {
  /// Scales a design-space measurement into logical pixels.
  double px(double designPx) => designPx * DesignScale.of(this);
}

/// Type roles from the design tokens table. Sizes are in design space; call
/// [AskanceText.scaled] to apply the phone scale factor.
abstract final class AskanceText {
  static const family = 'Archivo';

  static TextStyle _s(
    double size,
    FontWeight weight, {
    double? letterSpacing,
    double? height,
    Color color = AskanceColors.ink,
  }) => TextStyle(
    fontFamily: family,
    fontSize: size,
    fontWeight: weight,
    letterSpacing: letterSpacing,
    height: height,
    color: color,
  );

  static TextStyle screenTitle({Color color = AskanceColors.ink}) => _s(
    26,
    FontWeight.w800,
    letterSpacing: 26 * -0.02,
    height: 1,
    color: color,
  );

  static TextStyle onboardingTitle({Color color = AskanceColors.ground}) => _s(
    34,
    FontWeight.w800,
    letterSpacing: 34 * -0.03,
    height: 1.05,
    color: color,
  );

  static TextStyle sheetTitle({Color color = AskanceColors.ground}) => _s(
    18,
    FontWeight.w800,
    letterSpacing: 18 * -0.02,
    height: 1,
    color: color,
  );

  static TextStyle button(double size, {Color color = AskanceColors.ground}) =>
      _s(size, FontWeight.w800, height: 1, color: color);

  /// 700 9px, 0.16em, uppercase.
  static TextStyle sectionLabel({Color color = AskanceColors.mutedDark}) =>
      _s(9, FontWeight.w700, letterSpacing: 9 * 0.16, height: 1, color: color);

  static TextStyle controlLabel(
    double size, {
    double tracking = 0.08,
    Color color = AskanceColors.ground,
  }) => _s(
    size,
    FontWeight.w700,
    letterSpacing: size * tracking,
    height: 1,
    color: color,
  );

  static TextStyle body(double size, {Color color = AskanceColors.ground}) =>
      _s(size, FontWeight.w400, height: 1.55, color: color);

  static TextStyle caption(
    double size, {
    Color color = AskanceColors.mutedLight,
  }) => _s(size, FontWeight.w400, height: 1.3, color: color);

  static TextStyle cardName({Color color = AskanceColors.ink}) =>
      _s(11, FontWeight.w700, height: 1.2, color: color);

  /// Scales every dimension in [style] by [factor].
  static TextStyle scaled(TextStyle style, double factor) => style.copyWith(
    fontSize: (style.fontSize ?? 14) * factor,
    letterSpacing: style.letterSpacing == null
        ? null
        : style.letterSpacing! * factor,
  );
}

extension ScaledText on TextStyle {
  TextStyle by(double factor) => AskanceText.scaled(this, factor);
}
