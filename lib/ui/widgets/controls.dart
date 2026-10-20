import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../../theme.dart';

/// A label with an optional trailing glyph, solid or outlined. Solid is the
/// one primary action on a screen; outlined is everything beside it.
class ActionButton extends StatefulWidget {
  const ActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.trailing,
    this.trailingIcon,
    this.leadingIcon,
    this.solid = true,
    this.height = 50,
    this.fontSize = 15,
    this.onDark = false,
    this.enabled = true,
    this.centred = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final String? trailing;
  final Widget? trailingIcon;
  final Widget? leadingIcon;
  final bool solid;
  final double height;
  final double fontSize;

  /// Outlined buttons need to know which ground they sit on to pick their
  /// outline and text colour.
  final bool onDark;
  final bool enabled;

  /// Centre the label instead of spreading it from the trailing glyph.
  final bool centred;

  @override
  State<ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<ActionButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final s = DesignScale.of(context);
    final foreground = widget.solid
        ? AskanceColors.paper
        : (widget.onDark ? AskanceColors.gesso : AskanceColors.graphite);
    final fill = widget.solid
        ? (_down ? AskanceColors.accentPressed : AskanceColors.accent)
        : (_down
              ? (widget.onDark
                    ? AskanceColors.graphiteRaised
                    : AskanceColors.well)
              : null);

    final live = widget.enabled && widget.onPressed != null;

    return Opacity(
      // A button with nothing to do is dimmed and inert.
      opacity: live ? 1 : 0.4,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: live ? (_) => setState(() => _down = true) : null,
        onTapUp: widget.enabled ? (_) => setState(() => _down = false) : null,
        onTapCancel: widget.enabled
            ? () => setState(() => _down = false)
            : null,
        onTap: widget.enabled ? widget.onPressed : null,
        child: Container(
          height: widget.height * s,
          padding: EdgeInsets.symmetric(horizontal: 18 * s),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(AskanceRadius.button * s),
            border: widget.solid
                ? null
                : Border.all(
                    color: widget.onDark
                        ? AskanceColors.ruleDark
                        : AskanceColors.ruleStrong,
                    width: kRuleStrong,
                  ),
          ),
          // A Row hands its non-flex children an unbounded width, and an
          // Expanded inside one of those is a layout assertion — which only
          // fires in debug, so a release build hides it. Spread the label and
          // the trailing glyph apart when there is a width to spread them
          // across, and shrink-wrap when there is not.
          child: LayoutBuilder(
            builder: (context, constraints) {
              final style = AskanceText.button(
                widget.fontSize,
                color: foreground,
              ).by(s);
              final label = Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: widget.centred ? TextAlign.center : null,
                style: style,
              );
              final trailing =
                  widget.trailingIcon ??
                  (widget.trailing != null
                      ? Text(widget.trailing!, style: style)
                      : null);
              final leading = widget.leadingIcon == null
                  ? null
                  : Padding(
                      padding: EdgeInsets.only(right: 10 * s),
                      child: widget.leadingIcon,
                    );

              if (!constraints.hasBoundedWidth || widget.centred) {
                return Row(
                  mainAxisSize: constraints.hasBoundedWidth
                      ? MainAxisSize.max
                      : MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ?leading,
                    Flexible(child: label),
                    if (trailing != null) ...[
                      SizedBox(width: 12 * s),
                      trailing,
                    ],
                  ],
                );
              }
              return Row(
                children: [
                  ?leading,
                  Expanded(child: label),
                  ?trailing,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Cells in a sunken track, the selected one lifted out of it. Light by
/// default; [onDark] for the graphite chrome.
class SegmentedControl<T> extends StatelessWidget {
  const SegmentedControl({
    super.key,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
    this.height = 38,
    this.fontSize = 13,
    this.onDark = false,
  });

  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;
  final double height;
  final double fontSize;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final s = DesignScale.of(context);
    // A selection that is not among the values shows no marker at all, rather
    // than claiming the first cell.
    final index = values.indexOf(selected);
    final inset = 3 * s;
    final radius = AskanceRadius.control * s;

    return Container(
      height: height * s,
      padding: EdgeInsets.all(inset),
      decoration: BoxDecoration(
        color: onDark ? AskanceColors.graphiteRaised : AskanceColors.well,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cell = constraints.maxWidth / values.length;
          return Stack(
            children: [
              if (index >= 0)
                AnimatedPositioned(
                  duration: AskanceMotion.segmentedMarker,
                  curve: AskanceMotion.slide,
                  left: cell * index,
                  top: 0,
                  bottom: 0,
                  width: cell,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: onDark ? AskanceColors.gesso : AskanceColors.paper,
                      borderRadius: BorderRadius.circular(radius - inset),
                      boxShadow: onDark
                          ? null
                          : const [
                              BoxShadow(
                                color: Color(0x1F000000),
                                blurRadius: 2,
                                offset: Offset(0, 1),
                              ),
                            ],
                    ),
                  ),
                ),
              Row(
                children: [
                  for (final value in values)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onChanged(value),
                        child: Center(
                          child: Text(
                            labelOf(value),
                            maxLines: 1,
                            overflow: TextOverflow.fade,
                            softWrap: false,
                            style: AskanceText.control(
                              fontSize,
                              weight: value == selected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: value == selected
                                  ? AskanceColors.graphite
                                  : (onDark
                                        ? AskanceColors.mutedOnDark
                                        : AskanceColors.muted),
                            ).by(s),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A rounded track with a round thumb. The whole row is the drag target, not
/// just the thumb.
class RuleSlider extends StatelessWidget {
  const RuleSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.rowHeight = 30,
    this.origin = 0,
    this.shaded = false,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final double rowHeight;

  /// Where the filled part of the track starts. Centre it for a control that
  /// runs either side of nothing, and a tick marks the middle.
  final double origin;

  /// Shade the track from dark to light instead of filling it: for a control
  /// whose ends mean darker and lighter.
  final bool shaded;

  @override
  Widget build(BuildContext context) {
    final s = DesignScale.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final thumb = 22 * s;
        // The thumb stays wholly on the track at either end, so the value is
        // measured across the span its centre can travel.
        void report(Offset local) => onChanged(
          ((local.dx - thumb / 2) / (width - thumb)).clamp(0.0, 1.0),
        );
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => report(d.localPosition),
          onHorizontalDragStart: (d) => report(d.localPosition),
          onHorizontalDragUpdate: (d) => report(d.localPosition),
          child: SizedBox(
            height: rowHeight * s,
            width: width,
            child: CustomPaint(
              painter: _RuleSliderPainter(
                value: value,
                origin: origin,
                shaded: shaded,
                thumb: thumb,
                track: 4 * s,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RuleSliderPainter extends CustomPainter {
  _RuleSliderPainter({
    required this.value,
    required this.origin,
    required this.shaded,
    required this.thumb,
    required this.track,
  });

  final double value;
  final double origin;
  final bool shaded;
  final double thumb;
  final double track;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final left = thumb / 2;
    final span = size.width - thumb;
    double at(double v) => left + v * span;
    final bar = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, y - track / 2, span, track),
      Radius.circular(track / 2),
    );

    if (shaded) {
      canvas.drawRRect(
        bar,
        Paint()
          ..shader = const LinearGradient(
            colors: [Color(0xFF2B2A28), Color(0xFFE9E7E2)],
          ).createShader(bar.outerRect),
      );
    } else {
      canvas.drawRRect(bar, Paint()..color = AskanceColors.rule);
      final from = at(origin), to = at(value);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            math.min(from, to),
            y - track / 2,
            math.max(from, to),
            y + track / 2,
          ),
          Radius.circular(track / 2),
        ),
        Paint()..color = AskanceColors.graphite,
      );
    }
    if (origin > 0) {
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(at(origin), y),
          width: 1.5,
          height: thumb * 0.6,
        ),
        Paint()..color = AskanceColors.graphite,
      );
    }

    final centre = Offset(at(value), y);
    canvas.drawCircle(
      centre.translate(0, 1),
      thumb / 2,
      Paint()
        ..color = const Color(0x33000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    canvas.drawCircle(centre, thumb / 2, Paint()..color = AskanceColors.paper);
    canvas.drawCircle(
      centre,
      thumb / 2 - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = shaded ? AskanceColors.accent : AskanceColors.graphite,
    );
  }

  @override
  bool shouldRepaint(covariant _RuleSliderPainter old) =>
      old.value != value ||
      old.origin != origin ||
      old.shaded != shaded ||
      old.thumb != thumb ||
      old.track != track;
}

/// A rounded box that fills with the accent and a tick when on, with its
/// label beside it. The whole row is the tap target.
class RuleCheckbox extends StatelessWidget {
  const RuleCheckbox({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = DesignScale.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 6 * s),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: AskanceMotion.chromeFade,
              curve: AskanceMotion.slide,
              width: 20 * s,
              height: 20 * s,
              decoration: BoxDecoration(
                color: value ? AskanceColors.accent : AskanceColors.paper,
                borderRadius: BorderRadius.circular(6 * s),
                border: Border.all(
                  color: value
                      ? AskanceColors.accent
                      : AskanceColors.ruleStrong,
                  width: kRuleStrong,
                ),
              ),
              child: value
                  ? CustomPaint(painter: _TickPainter(AskanceColors.paper))
                  : null,
            ),
            SizedBox(width: 10 * s),
            Flexible(child: Text(label, style: AskanceText.body(14).by(s))),
          ],
        ),
      ),
    );
  }
}

class _TickPainter extends CustomPainter {
  _TickPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.shortestSide;
    canvas.drawPath(
      Path()
        ..moveTo(u * 0.26, u * 0.52)
        ..lineTo(u * 0.43, u * 0.68)
        ..lineTo(u * 0.74, u * 0.34),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = u * 0.12
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _TickPainter old) => old.color != color;
}

/// `−  n  +`, the buttons outlined, the number large between them.
class RuleStepper extends StatelessWidget {
  const RuleStepper({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.size = 40,
  });

  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  final double size;

  @override
  Widget build(BuildContext context) {
    final s = DesignScale.of(context);
    Widget button(String glyph, String label, int delta, bool enabled) =>
        Semantics(
          button: true,
          label: label,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: enabled ? () => onChanged(value + delta) : null,
            child: Container(
              width: size * s,
              height: size * s,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12 * s),
                border: Border.all(
                  color: AskanceColors.ruleStrong,
                  width: kRuleStrong,
                ),
              ),
              child: Text(
                glyph,
                style: AskanceText.title(
                  20,
                  color: enabled ? AskanceColors.graphite : AskanceColors.rule,
                ).by(s),
              ),
            ),
          ),
        );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        button('−', 'Fewer', -1, value > min),
        SizedBox(
          width: size * s,
          child: Center(
            child: Text('$value', style: AskanceText.number(22).by(s)),
          ),
        ),
        button('+', 'More', 1, value < max),
      ],
    );
  }
}

/// A hairline. On gesso by default.
class Rule extends StatelessWidget {
  const Rule({super.key, this.color = AskanceColors.rule, this.height = kRule});

  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) => Container(height: height, color: color);
}

/// Builds the recognizer for press-and-hold-to-peek at the designed 280ms,
/// which is shorter than Flutter's default long press.
GestureRecognizerFactory peekRecognizer({
  required VoidCallback onStart,
  required VoidCallback onEnd,
}) => GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
  () => LongPressGestureRecognizer(duration: AskanceMotion.peekThreshold),
  (instance) => instance
    ..onLongPressStart = ((_) => onStart())
    ..onLongPressEnd = ((_) => onEnd())
    ..onLongPressCancel = onEnd,
);
