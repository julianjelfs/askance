import 'package:flutter/widgets.dart';

import '../../engine/blocks.dart';
import '../../engine/crop.dart';
import '../../engine/engine.dart';
import '../../engine/value_scale.dart';
import '../../model/study.dart';
import '../../state/canvas_session.dart';
import '../../theme.dart';
import '../widgets/controls.dart';

/// The control groups. Shared verbatim between the phone's tool panel and the
/// desktop rail — only the surrounding chrome differs.

/// The Munsell value a band is painted at: L* / 10, which is what an artist's
/// printed value scale is numbered in.
String munsellLabel(StudySettings settings, int band) {
  final lstar = bandCentreLstar(band, settings.steps, settings.bias);
  return 'V${(lstar / 10).round()}';
}

/// A name and, flush right, its readout.
class ControlLabelRow extends StatelessWidget {
  const ControlLabelRow({super.key, required this.label, this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final s = DesignScale.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: 8 * s),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          // Gives way to the readout rather than overflowing the panel.
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AskanceText.label(14.5).by(s),
            ),
          ),
          if (value != null)
            Text(value!, style: AskanceText.number(13.5).by(s)),
        ],
      ),
    );
  }
}

/// Two quiet words under either end of a slider, saying what the ends mean.
class SliderEnds extends StatelessWidget {
  const SliderEnds(this.start, this.end, {super.key});

  final String start;
  final String end;

  @override
  Widget build(BuildContext context) {
    final s = DesignScale.of(context);
    final style = AskanceText.caption(12).by(s);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(child: Text(start, style: style)),
        const SizedBox(width: 12),
        Flexible(
          child: Text(end, textAlign: TextAlign.end, style: style),
        ),
      ],
    );
  }
}

/// Values and detail together, as six quick picks. Each is drawn as the
/// ramp it would paint, so the choice is made by looking rather than by
/// number. Picks nothing once either has been set by hand; nothing else
/// depends on it.
class StageControl extends StatelessWidget {
  const StageControl({super.key, required this.session, this.height = 44});
  final CanvasSession session;
  final double height;

  static String readout(StudySettings settings) => switch (settings.stage) {
    final stage? => '${stage + 1} of ${StudySettings.stages.length}',
    null => 'By hand',
  };

  @override
  Widget build(BuildContext context) {
    final s = DesignScale.of(context);
    final current = session.settings.stage;
    final scale = session.settings.scale;
    return Row(
      children: [
        for (var i = 0; i < StudySettings.stages.length; i++) ...[
          if (i > 0) SizedBox(width: 6 * s),
          Expanded(
            child: Semantics(
              button: true,
              selected: current == i,
              label: 'Stage ${i + 1}, ${StudySettings.stages[i].steps} values',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => session.setStage(i),
                child: Container(
                  height: height * s,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(9 * s),
                    boxShadow: current == i
                        ? [
                            BoxShadow(
                              color: AskanceColors.gesso,
                              spreadRadius: 2 * s,
                            ),
                            BoxShadow(
                              color: AskanceColors.accent,
                              spreadRadius: 4 * s,
                            ),
                          ]
                        : null,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(9 * s),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      // Lightest at the top, as a value scale stands.
                      children: [
                        for (final colour
                            in scale
                                .ramp(StudySettings.stages[i].steps)
                                .reversed)
                          Expanded(child: ColoredBox(color: colour)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class ValuesControl extends StatelessWidget {
  const ValuesControl({super.key, required this.session});
  final CanvasSession session;

  @override
  Widget build(BuildContext context) => RuleStepper(
    value: session.settings.steps,
    min: StudySettings.minSteps,
    max: StudySettings.maxSteps,
    onChanged: session.setSteps,
  );
}

/// Slides every threshold together, so a borderline passage can be pushed to
/// one side of a boundary or the other.
class BiasControl extends StatelessWidget {
  const BiasControl({super.key, required this.session});
  final CanvasSession session;

  static String readout(double bias) {
    final steps = (bias / StudySettings.maxBias * 50).round();
    return steps == 0 ? '0' : (steps > 0 ? '+$steps' : '$steps');
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      RuleSlider(
        // Nothing in the middle, and equal room either side of it.
        origin: 0.5,
        shaded: true,
        value: session.settings.bias / (StudySettings.maxBias * 2) + 0.5,
        onChanged: (v) =>
            session.setBias((v - 0.5) * StudySettings.maxBias * 2),
      ),
      // A positive bias lifts every pixel's lightness before it is banded.
      const SliderEnds('More reads dark', 'More reads light'),
    ],
  );
}

class DetailControl extends StatelessWidget {
  const DetailControl({super.key, required this.session});
  final CanvasSession session;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      RuleSlider(value: session.settings.detail, onChanged: session.setDetail),
      const SliderEnds('Squint', 'Look closely'),
    ],
  );
}

/// Whether the detail is locked against the zoom. Unticked, the blur lives
/// in screen space and zooming in resolves finer shapes; ticked, the
/// simplification holds still against the photograph and zooming only
/// magnifies it.
class LockDetailControl extends StatelessWidget {
  const LockDetailControl({super.key, required this.session});
  final CanvasSession session;

  @override
  Widget build(BuildContext context) => RuleCheckbox(
    label: 'Keep the detail fixed when zooming',
    value: session.settings.lockDetail,
    onChanged: session.setLockDetail,
  );
}

/// Which way the photograph is simplified before it is quantised, each choice
/// drawn as the kind of edge it leaves.
class SmoothingControl extends StatelessWidget {
  const SmoothingControl({super.key, required this.session, this.height = 60});
  final CanvasSession session;
  final double height;

  @override
  Widget build(BuildContext context) {
    final s = DesignScale.of(context);
    return Row(
      children: [
        for (final smoothing in Smoothing.values) ...[
          if (smoothing.index > 0) SizedBox(width: 8 * s),
          Expanded(
            child: _Tile(
              selected: session.settings.smoothing == smoothing,
              onTap: () => session.setSmoothing(smoothing),
              height: height,
              label: smoothing.label,
              icon: (colour) => CustomPaint(
                size: Size(30 * s, 18 * s),
                painter: _EdgePainter(smoothing, colour),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// A choice drawn as a small card: selected, it turns graphite.
class _Tile extends StatelessWidget {
  const _Tile({
    required this.selected,
    required this.onTap,
    required this.height,
    required this.label,
    required this.icon,
  });

  final bool selected;
  final VoidCallback onTap;
  final double height;
  final String label;
  final Widget Function(Color) icon;

  @override
  Widget build(BuildContext context) {
    final s = DesignScale.of(context);
    final ink = selected ? AskanceColors.gesso : AskanceColors.graphite;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: AskanceMotion.chromeFade,
          height: height * s,
          decoration: BoxDecoration(
            color: selected ? AskanceColors.graphite : AskanceColors.paper,
            borderRadius: BorderRadius.circular(12 * s),
            border: selected
                ? null
                : Border.all(color: AskanceColors.rule, width: kRule),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              icon(ink),
              SizedBox(height: 4 * s),
              Text(label, style: AskanceText.control(13, color: ink).by(s)),
            ],
          ),
        ),
      ),
    );
  }
}

class _EdgePainter extends CustomPainter {
  _EdgePainter(this.smoothing, this.colour);
  final Smoothing smoothing;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width / 30, h = size.height / 20;
    Offset p(double x, double y) => Offset(x * w, y * h);
    final path = switch (smoothing) {
      Smoothing.gaussian =>
        Path()
          ..moveTo(p(3, 17).dx, p(3, 17).dy)
          ..cubicTo(5 * w, 4 * h, 13 * w, 2 * h, 17 * w, 7 * h)
          ..cubicTo(21 * w, 12 * h, 26 * w, 9 * h, 27 * w, 17 * h)
          ..close(),
      Smoothing.kuwahara =>
        Path()..addPolygon([
          p(3, 17), p(5, 11), p(8, 12), p(10, 5), p(14, 7), p(17, 5), //
          p(19, 9), p(23, 8), p(24, 12), p(27, 17),
        ], true),
      Smoothing.block =>
        Path()..addPolygon([p(3, 17), p(9, 4), p(18, 6), p(27, 17)], true),
    };
    canvas.drawPath(path, Paint()..color = colour);
  }

  @override
  bool shouldRepaint(covariant _EdgePainter old) =>
      old.smoothing != smoothing || old.colour != colour;
}

class ScaleControl extends StatelessWidget {
  const ScaleControl({super.key, required this.session});
  final CanvasSession session;

  /// The strip shows the tint each hue actually produces — the mid band of
  /// its own three-step ramp — not a saturated spectrum. A rainbow would
  /// promise colours the scale never paints; vivid is RANDOM's job.
  static final List<Color> _stripTints = [
    for (var h = 0; h <= 360; h += 15)
      ValueScale.tinted(h.toDouble()).ramp(3)[1],
  ];

  @override
  Widget build(BuildContext context) {
    final s = DesignScale.of(context);
    final selected = session.settings.scale;
    final radius = BorderRadius.circular(8 * s);
    final ring = [
      BoxShadow(color: AskanceColors.gesso, spreadRadius: 2 * s),
      BoxShadow(color: AskanceColors.graphite, spreadRadius: 3.5 * s),
    ];
    return SizedBox(
      height: 34 * s,
      child: Row(
        // Without this a swatch sizes to its bands, which have no height of
        // their own, and collapses to a hairline.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Grey is not a hue, it is the absence of one, so it gets its own
          // cell rather than a point on the strip.
          Semantics(
            button: true,
            selected: selected.hue == null,
            label: 'Neutral grey',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => session.setScale(ValueScale.grey),
              child: Container(
                width: 52 * s,
                decoration: BoxDecoration(
                  borderRadius: radius,
                  boxShadow: selected.hue == null ? ring : null,
                ),
                child: ClipRRect(
                  borderRadius: radius,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final band in ValueScale.grey.swatchBands)
                        Expanded(child: ColoredBox(color: band)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SizedBox(width: 10 * s),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                void report(Offset local) => session.setScale(
                  ValueScale.tinted((local.dx / width).clamp(0.0, 1.0) * 360),
                );
                final hue = selected.hue;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) => report(d.localPosition),
                  onHorizontalDragStart: (d) => report(d.localPosition),
                  onHorizontalDragUpdate: (d) => report(d.localPosition),
                  child: Stack(
                    clipBehavior: Clip.none,
                    fit: StackFit.expand,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: radius,
                          gradient: LinearGradient(colors: _stripTints),
                        ),
                      ),
                      if (hue != null)
                        // A ring around the chosen hue, the slider thumb's
                        // shape standing on the strip.
                        Positioned(
                          left: (hue / 360 * width - 11 * s).clamp(
                            -4 * s,
                            width - 18 * s,
                          ),
                          top: -3 * s,
                          bottom: -3 * s,
                          width: 22 * s,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8 * s),
                              border: Border.all(
                                color: AskanceColors.paper,
                                width: 3 * s,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x40000000),
                                  blurRadius: 3,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Every colour the picture is painted in, each on its own: the palette to
/// mix, easier to judge in isolation than scattered across the image, and
/// numbered in the Munsell values a printed value scale uses. Tap a colour to
/// see only where it falls; tap it again to see them all. Shown in the modes
/// where the picture is nothing but these colours.
///
/// A column of chips, lightest at the top, for the side of a large picture.
class PaletteSwatch extends StatelessWidget {
  const PaletteSwatch({
    super.key,
    required this.session,
    required this.chipHeight,
  });

  final CanvasSession session;

  /// Before the design scale. Each chip takes the full width it is given.
  final double chipHeight;

  @override
  Widget build(BuildContext context) {
    final s = DesignScale.of(context);
    final palette = session.settings.palette;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Lightest at the top, as a value scale stands.
        for (var band = palette.length - 1; band >= 0; band--) ...[
          if (band < palette.length - 1) SizedBox(height: 8 * s),
          _PaletteChip(
            session: session,
            band: band,
            child: Container(
              height: chipHeight * s,
              alignment: Alignment.bottomRight,
              padding: EdgeInsets.fromLTRB(6 * s, 4 * s, 8 * s, 6 * s),
              decoration: BoxDecoration(
                color: palette[band],
                borderRadius: BorderRadius.circular(12 * s),
                border: Border.all(
                  color: session.isolatedBand == band
                      ? AskanceColors.accent
                      : const Color(0x1A000000),
                  width: session.isolatedBand == band ? 3 * s : kRule,
                ),
              ),
              child: Text(
                munsellLabel(session.settings, band),
                style: AskanceText.number(
                  13,
                  color: _onColour(palette[band]),
                ).by(s),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// The same palette as a row of pills under the picture, lightest first.
class PaletteChips extends StatelessWidget {
  const PaletteChips({super.key, required this.session});

  final CanvasSession session;

  @override
  Widget build(BuildContext context) {
    final s = DesignScale.of(context);
    final palette = session.settings.palette;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 6 * s,
      runSpacing: 6 * s,
      children: [
        for (var band = palette.length - 1; band >= 0; band--)
          _PaletteChip(
            session: session,
            band: band,
            child: Container(
              height: 30 * s,
              padding: EdgeInsets.fromLTRB(4 * s, 0, 11 * s, 0),
              decoration: BoxDecoration(
                color: AskanceColors.graphiteRaised,
                borderRadius: BorderRadius.circular(15 * s),
                border: session.isolatedBand == band
                    ? Border.all(color: AskanceColors.accent, width: 2 * s)
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 22 * s,
                    height: 22 * s,
                    decoration: BoxDecoration(
                      color: palette[band],
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0x33FFFFFF),
                        width: kRule,
                      ),
                    ),
                  ),
                  SizedBox(width: 7 * s),
                  Text(
                    munsellLabel(session.settings, band),
                    style: AskanceText.number(
                      12.5,
                      color: AskanceColors.gesso,
                    ).by(s),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _PaletteChip extends StatelessWidget {
  const _PaletteChip({
    required this.session,
    required this.band,
    required this.child,
  });

  final CanvasSession session;
  final int band;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: session.isolatedBand == band,
    label: 'Show ${munsellLabel(session.settings, band)} alone',
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => session.toggleIsolatedBand(band),
      child: child,
    ),
  );
}

/// Graphite or gesso, whichever reads on [colour].
Color _onColour(Color colour) => colour.computeLuminance() > 0.25
    ? AskanceColors.graphite
    : AskanceColors.gesso;

/// How PHOTO shows the photograph: colour or black and white, brightness and
/// contrast. Shared by the phone's tone panel and the desktop rail.
class ToneControl extends StatelessWidget {
  const ToneControl({super.key, required this.session});
  final CanvasSession session;

  static String readout(double v) {
    final n = (v * 50).round();
    return n == 0 ? '0' : (n > 0 ? '+$n' : '$n');
  }

  @override
  Widget build(BuildContext context) {
    final s = DesignScale.of(context);
    final tone = session.settings.tone;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedControl<bool>(
          values: const [false, true],
          selected: tone.mono,
          labelOf: (v) => v ? 'Black & white' : 'Colour',
          onChanged: (v) => session.setTone(tone.copyWith(mono: v)),
        ),
        SizedBox(height: 16 * s),
        ControlLabelRow(label: 'Brightness', value: readout(tone.brightness)),
        RuleSlider(
          origin: 0.5,
          value: tone.brightness / 2 + 0.5,
          onChanged: (v) =>
              session.setTone(tone.copyWith(brightness: v * 2 - 1)),
        ),
        SizedBox(height: 10 * s),
        ControlLabelRow(label: 'Contrast', value: readout(tone.contrast)),
        RuleSlider(
          origin: 0.5,
          value: tone.contrast / 2 + 0.5,
          onChanged: (v) => session.setTone(tone.copyWith(contrast: v * 2 - 1)),
        ),
      ],
    );
  }
}

/// EDGES only: how many values, darkest first, are blocked in under the
/// lines.
class FillControl extends StatelessWidget {
  const FillControl({super.key, required this.session});
  final CanvasSession session;

  @override
  Widget build(BuildContext context) => SegmentedControl<int>(
    values: [for (var i = 0; i <= session.settings.steps; i++) i],
    selected: session.settings.skeletonFill.clamp(0, session.settings.steps),
    labelOf: (v) => v == 0 ? 'Lines' : '$v',
    onChanged: session.setSkeletonFill,
  );
}

class GridControl extends StatelessWidget {
  const GridControl({super.key, required this.session});
  final CanvasSession session;

  @override
  Widget build(BuildContext context) {
    final s = DesignScale.of(context);
    final on = session.settings.grid != GridMode.off;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedControl<GridMode>(
          values: GridMode.values,
          selected: session.settings.grid,
          labelOf: (v) => v.label,
          onChanged: session.setGrid,
        ),
        SizedBox(height: 8 * s),
        // Each level halves every cell both ways, so the choice is how many
        // cells across at 1×: 2, 4, 8 or 16 — never a count that leaves a
        // partial cell at one edge. Zooming in halves further by itself.
        Opacity(
          opacity: on ? 1 : 0.45,
          child: SegmentedControl<int>(
            values: [
              for (
                var level = StudySettings.minGridLevel;
                level <= StudySettings.maxGridLevel;
                level++
              )
                level,
            ],
            selected: session.settings.gridLevel,
            labelOf: (level) {
              final n = StudySettings.divisionsAt(level);
              return '$n × $n';
            },
            onChanged: session.setGridLevel,
          ),
        ),
      ],
    );
  }
}

/// What the study is cropped to, in words.
String cropSummary(CanvasSession session) {
  final image = session.image;
  if (image == null) return 'Whole photograph';
  final found = cropShapeOf(
    Size(image.width.toDouble(), image.height.toDouble()),
    session.settings.crop,
  );
  return switch (found) {
    null => 'Custom crop',
    (shape: CropShape.whole, landscape: _) => 'Whole photograph',
    (shape: CropShape.square, landscape: _) => 'Square crop',
    (:final shape, :final landscape) =>
      '${shape.label} ${landscape ? 'landscape' : 'portrait'}',
  };
}

/// The board: the crop the study is of, and the grid that divides it.
class BoardControl extends StatelessWidget {
  const BoardControl({
    super.key,
    required this.session,
    required this.onEditCrop,
  });

  final CanvasSession session;
  final VoidCallback onEditCrop;

  @override
  Widget build(BuildContext context) {
    final s = DesignScale.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Crop', style: AskanceText.label(14.5).by(s)),
                  SizedBox(height: 2 * s),
                  Text(
                    cropSummary(session),
                    style: AskanceText.caption(13).by(s),
                  ),
                ],
              ),
            ),
            ActionButton(
              label: 'Edit crop',
              solid: false,
              height: 38,
              fontSize: 13.5,
              onPressed: onEditCrop,
            ),
          ],
        ),
        SizedBox(height: 14 * s),
        const ControlLabelRow(label: 'Grid'),
        GridControl(session: session),
      ],
    );
  }
}

/// The phone's tool panel: one tool at a time, above the tool bar.
class ToolPanel extends StatelessWidget {
  const ToolPanel({
    super.key,
    required this.session,
    required this.tool,
    required this.onEditCrop,
  });

  final CanvasSession session;
  final CanvasTool tool;
  final VoidCallback onEditCrop;

  @override
  Widget build(BuildContext context) {
    final s = DesignScale.of(context);
    final gap = SizedBox(height: 16 * s);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: switch (tool) {
        CanvasTool.steps => [
          ControlLabelRow(
            label: 'Stages',
            value: StageControl.readout(session.settings),
          ),
          StageControl(session: session),
          gap,
          Row(
            children: [
              Expanded(
                child: Text('Values', style: AskanceText.label(14.5).by(s)),
              ),
              ValuesControl(session: session),
            ],
          ),
          gap,
          ControlLabelRow(
            label: 'Where the steps fall',
            value: BiasControl.readout(session.settings.bias),
          ),
          BiasControl(session: session),
        ],
        CanvasTool.detail => [
          SmoothingControl(session: session),
          gap,
          ControlLabelRow(
            label: 'Detail',
            value: '${(session.settings.detail * 100).round()}',
          ),
          DetailControl(session: session),
          SizedBox(height: 6 * s),
          LockDetailControl(session: session),
        ],
        CanvasTool.scale => [
          const ControlLabelRow(label: 'Root of the scale'),
          ScaleControl(session: session),
        ],
        CanvasTool.grid => [
          BoardControl(session: session, onEditCrop: onEditCrop),
        ],
        CanvasTool.tone => [ToneControl(session: session)],
        CanvasTool.fill => [
          const ControlLabelRow(label: 'Blocked in under the lines'),
          FillControl(session: session),
          SizedBox(height: 6 * s),
          Text(
            'Values fill darkest first, the way a painting is begun.',
            style: AskanceText.caption(12.5).by(s),
          ),
        ],
      },
    );
  }
}
