import 'package:flutter/widgets.dart';

/// Gesso: the studio's own materials. A primed white board for every panel,
/// graphite for type and the dark chrome, one cadmium accent, and a neutral
/// middle grey around the picture — the surround a value is judged against,
/// since black or white beside a passage shifts how light it reads.
abstract final class AskanceColors {
  /// Dark chrome, and type on light.
  static const graphite = Color(0xFF1C1B1A);

  /// A raised control on the dark chrome.
  static const graphiteRaised = Color(0xFF2C2A28);

  /// Every panel, and type on dark.
  static const gesso = Color(0xFFF3F1EC);

  /// Cards and the selected cell of a control, lifted off the gesso.
  static const paper = Color(0xFFFFFFFF);

  /// The sunken track behind a control on gesso.
  static const well = Color(0xFFE7E3DB);

  /// Around the picture: Munsell value 5, L* 50.
  static const surround = Color(0xFF777777);

  /// Fills: the primary action, the selected marker, a thumb's ring.
  static const accent = Color(0xFFE2471F);
  static const accentPressed = Color(0xFFC73B16);

  /// The accent as text or a thin line on gesso, dark enough to read.
  static const accentInk = Color(0xFFB8340F);

  static const muted = Color(0xFF6A655E);
  static const mutedOnDark = Color(0xFFA39E96);

  /// Hairlines on gesso, a heavier one for outlines, and hairlines on dark.
  static const rule = Color(0xFFDDD8CF);
  static const ruleStrong = Color(0xFFCFC9BF);
  static const ruleDark = Color(0xFF3A3734);

  /// Grid rules, drawn in screen space over everything.
  static const grid = Color(0xA6E2471F);
}

/// Hairline weight for every rule and outline.
const double kRule = 1;

/// The heavier outline of a control that can be pressed.
const double kRuleStrong = 1.5;

abstract final class AskanceRadius {
  static const double small = 8;
  static const double control = 11;
  static const double button = 14;
  static const double card = 14;
  static const double sheet = 26;
}

/// Every phone screen was drawn at this width and scales proportionally.
const double kDesignWidth = 390;

/// The width at which the phone layout gives way to the rail-and-stage layout.
const double kDesktopBreakpoint = 900;

abstract final class AskanceMotion {
  static const Curve slide = Cubic(0.2, 0.8, 0.2, 1);
  static const segmentedMarker = Duration(milliseconds: 220);
  static const chromeFade = Duration(milliseconds: 220);
  static const sheetSlide = Duration(milliseconds: 320);
  static const peekThreshold = Duration(milliseconds: 280);
  static const doubleTapWindow = Duration(milliseconds: 300);
}

/// Proportional scale for the phone layout, so a design drawn at 390pt reads
/// the same on a narrower or wider phone. Held close to 1 either way: type
/// that grows with the glass soon looks cartoonish.
class DesignScale extends InheritedWidget {
  const DesignScale({super.key, required this.factor, required super.child});

  final double factor;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DesignScale>()?.factor ?? 1;

  static double forWidth(double width) =>
      (width / kDesignWidth).clamp(0.9, 1.15).toDouble();

  @override
  bool updateShouldNotify(DesignScale old) => old.factor != factor;
}

extension DesignScaleContext on BuildContext {
  /// Scales a design-space measurement into logical pixels.
  double px(double designPx) => designPx * DesignScale.of(this);
}

/// Type roles. Bricolage Grotesque throughout: its text cut for everything a
/// hand reaches for, the display cut for the few large titles. Sizes are in
/// design space; [ScaledText.by] applies the phone's scale factor.
abstract final class AskanceText {
  static const family = 'Bricolage';
  static const displayFamily = 'BricolageDisplay';

  static TextStyle _s(
    double size,
    FontWeight weight, {
    String family = family,
    double? letterSpacing,
    double? height,
    Color color = AskanceColors.graphite,
    List<FontFeature>? features,
  }) => TextStyle(
    fontFamily: family,
    fontSize: size,
    fontWeight: weight,
    letterSpacing: letterSpacing,
    height: height,
    color: color,
    fontFeatures: features,
  );

  /// The wordmark and the shelf's title.
  static TextStyle display(
    double size, {
    Color color = AskanceColors.graphite,
  }) => _s(
    size,
    FontWeight.w800,
    family: displayFamily,
    letterSpacing: size * -0.035,
    height: 1,
    color: color,
  );

  /// A screen or sheet heading.
  static TextStyle heading(
    double size, {
    Color color = AskanceColors.graphite,
  }) => _s(
    size,
    FontWeight.w700,
    family: displayFamily,
    letterSpacing: size * -0.025,
    height: 1.05,
    color: color,
  );

  /// A study's name, a card's title.
  static TextStyle title(double size, {Color color = AskanceColors.graphite}) =>
      _s(
        size,
        FontWeight.w600,
        letterSpacing: size * -0.01,
        height: 1.2,
        color: color,
      );

  /// The name above a control.
  static TextStyle label(double size, {Color color = AskanceColors.graphite}) =>
      _s(size, FontWeight.w600, height: 1.2, color: color);

  /// Inside a control: a segment, a tab.
  static TextStyle control(
    double size, {
    Color color = AskanceColors.graphite,
    FontWeight weight = FontWeight.w500,
  }) => _s(size, weight, height: 1.1, color: color);

  static TextStyle button(double size, {Color color = AskanceColors.paper}) =>
      _s(size, FontWeight.w600, height: 1.1, color: color);

  static TextStyle body(double size, {Color color = AskanceColors.graphite}) =>
      _s(size, FontWeight.w400, height: 1.45, color: color);

  static TextStyle caption(double size, {Color color = AskanceColors.muted}) =>
      _s(size, FontWeight.w400, height: 1.3, color: color);

  /// A readout: tabular, so a changing number does not jitter its neighbours.
  static TextStyle number(
    double size, {
    Color color = AskanceColors.graphite,
  }) => _s(
    size,
    FontWeight.w600,
    height: 1.1,
    color: color,
    features: const [FontFeature.tabularFigures()],
  );

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
