import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../../theme.dart';

/// A flush-left label with a trailing glyph, solid or outlined. The design has
/// exactly two button shapes and this is both of them.
class ActionButton extends StatefulWidget {
  const ActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.trailing,
    this.trailingIcon,
    this.solid = true,
    this.height = 46,
    this.fontSize = 14,
    this.onDark = false,
    this.enabled = true,
    this.opacity = 1,
  });

  final String label;
  final VoidCallback? onPressed;
  final String? trailing;

  /// Used where the design's symbol is not in Archivo; see [GlyphIcon].
  final Widget? trailingIcon;
  final bool solid;
  final double height;
  final double fontSize;

  /// Outlined buttons need to know which ground they sit on to pick their rule
  /// and text colour.
  final bool onDark;
  final bool enabled;

  /// Locked share options drop to 40% but stay tappable — a tap on a locked
  /// control is intent to buy.
  final double opacity;

  @override
  State<ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<ActionButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final s = DesignScale.of(context);
    final foreground = widget.solid
        ? AskanceColors.ground
        : (widget.onDark ? AskanceColors.ground : AskanceColors.ink);
    final fill = widget.solid
        ? (_down ? AskanceColors.accentPressed : AskanceColors.accent)
        : (_down
              ? (widget.onDark
                    ? AskanceColors.trackDark
                    : const Color(0x12201E1D))
              : null);

    final live = widget.enabled && widget.onPressed != null;

    return Opacity(
      // A locked share option keeps its own dimming and stays tappable; a
      // button with nothing to do is dimmed and inert.
      opacity: live ? widget.opacity : widget.opacity * 0.4,
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
          padding: EdgeInsets.symmetric(horizontal: 14 * s),
          decoration: BoxDecoration(
            color: fill,
            border: widget.solid
                ? null
                : Border.all(
                    color: widget.onDark
                        ? AskanceColors.ground
                        : AskanceColors.dividerLight,
                    width: kRule,
                  ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AskanceText.button(
                    widget.fontSize,
                    color: foreground,
                  ).by(s),
                ),
              ),
              if (widget.trailingIcon != null)
                widget.trailingIcon!
              else if (widget.trailing != null)
                Text(
                  widget.trailing!,
                  style: AskanceText.button(
                    widget.fontSize,
                    color: foreground,
                  ).by(s),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A segmented control with a red marker that slides between cells.
class SegmentedControl<T> extends StatelessWidget {
  const SegmentedControl({
    super.key,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
    this.height = 34,
    this.fontSize = 11,
  });

  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;
  final double height;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final s = DesignScale.of(context);
    final index = values.indexOf(selected).clamp(0, values.length - 1);

    return SizedBox(
      height: height * s,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cell = constraints.maxWidth / values.length;
          return Stack(
            children: [
              Positioned.fill(
                child: ColoredBox(color: AskanceColors.trackDark),
              ),
              AnimatedPositioned(
                duration: AskanceMotion.segmentedMarker,
                curve: AskanceMotion.slide,
                left: cell * index,
                top: 0,
                bottom: 0,
                width: cell,
                child: const ColoredBox(color: AskanceColors.accent),
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
                            style: AskanceText.controlLabel(
                              fontSize,
                              tracking: 0.06,
                              color: AskanceColors.ground,
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

/// A 2px track with a 4px red thumb. The whole row is the drag target, not
/// just the thumb.
class RuleSlider extends StatelessWidget {
  const RuleSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.rowHeight = 28,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final double rowHeight;

  @override
  Widget build(BuildContext context) {
    final s = DesignScale.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        void report(Offset local) =>
            onChanged((local.dx / width).clamp(0.0, 1.0));
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => report(d.localPosition),
          onHorizontalDragStart: (d) => report(d.localPosition),
          onHorizontalDragUpdate: (d) => report(d.localPosition),
          child: SizedBox(
            height: rowHeight * s,
            width: width,
            child: CustomPaint(
              painter: _RuleSliderPainter(value: value, thumbWidth: 4 * s),
            ),
          ),
        );
      },
    );
  }
}

class _RuleSliderPainter extends CustomPainter {
  _RuleSliderPainter({required this.value, required this.thumbWidth});

  final double value;
  final double thumbWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final x = value * size.width;
    canvas.drawRect(
      Rect.fromLTWH(0, y - kRule / 2, size.width, kRule),
      Paint()..color = AskanceColors.dividerDark,
    );
    canvas.drawRect(
      Rect.fromLTWH(0, y - kRule / 2, x, kRule),
      Paint()..color = AskanceColors.accent,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        (x - thumbWidth / 2).clamp(0.0, size.width - thumbWidth),
        y - size.height / 3,
        thumbWidth,
        size.height / 1.5,
      ),
      Paint()..color = AskanceColors.accent,
    );
  }

  @override
  bool shouldRepaint(covariant _RuleSliderPainter old) =>
      old.value != value || old.thumbWidth != thumbWidth;
}

/// `–  n  +` in a 2px outlined box.
class RuleStepper extends StatelessWidget {
  const RuleStepper({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.height = 32,
  });

  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  final double height;

  @override
  Widget build(BuildContext context) {
    final s = DesignScale.of(context);
    Widget button(String glyph, int delta, bool enabled) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? () => onChanged(value + delta) : null,
      child: SizedBox(
        width: height * s,
        height: height * s,
        child: Center(
          child: Text(
            glyph,
            style: AskanceText.button(
              14,
              color: enabled ? AskanceColors.ground : AskanceColors.dividerDark,
            ).by(s),
          ),
        ),
      ),
    );

    return Container(
      height: height * s,
      decoration: BoxDecoration(
        border: Border.all(color: AskanceColors.dividerDark, width: kRule),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          button('–', -1, value > min),
          SizedBox(
            width: 28 * s,
            child: Center(
              child: Text(
                '$value',
                style: AskanceText.controlLabel(
                  12,
                  tracking: 0.06,
                  color: AskanceColors.ground,
                ).by(s),
              ),
            ),
          ),
          button('+', 1, value < max),
        ],
      ),
    );
  }
}

/// The one icon in the design: Lucide `share-2`. Drawn rather than bundled,
/// because bundling an icon font for a single glyph is not worth the weight.
class ShareIcon extends StatelessWidget {
  const ShareIcon({super.key, required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _ShareIconPainter(color));
}

class _ShareIconPainter extends CustomPainter {
  _ShareIconPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width / 24;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * u
      ..strokeCap = StrokeCap.round;

    final topRight = Offset(18 * u, 5 * u);
    final bottomRight = Offset(18 * u, 19 * u);
    final left = Offset(6 * u, 12 * u);

    canvas.drawLine(
      Offset(8.59 * u, 13.51 * u),
      Offset(15.42 * u, 17.49 * u),
      stroke,
    );
    canvas.drawLine(
      Offset(15.41 * u, 6.51 * u),
      Offset(8.59 * u, 10.49 * u),
      stroke,
    );

    final fill = Paint()..color = color;
    for (final centre in [topRight, bottomRight, left]) {
      canvas.drawCircle(centre, 3 * u, stroke);
      canvas.drawCircle(centre, 0.6 * u, fill);
    }
  }

  @override
  bool shouldRepaint(covariant _ShareIconPainter old) => old.color != color;
}

/// A 2px rule. Used everywhere; never a hairline.
class Rule extends StatelessWidget {
  const Rule({
    super.key,
    this.color = AskanceColors.dividerDark,
    this.height = kRule,
  });

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
