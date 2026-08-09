import 'package:flutter/widgets.dart';

import '../../engine/engine.dart';
import '../../engine/value_scale.dart';
import '../../model/study.dart';
import '../../state/canvas_session.dart';
import '../../theme.dart';
import '../widgets/controls.dart';

/// The four control groups. Shared verbatim between the phone's tool panel and
/// the desktop rail — only the surrounding chrome differs.
class ValuesControl extends StatelessWidget {
  const ValuesControl({super.key, required this.session});
  final CanvasSession session;

  @override
  Widget build(BuildContext context) => SegmentedControl<int>(
    values: const [2, 3, 4, 5, 6, 7],
    selected: session.settings.steps,
    labelOf: (v) => '$v',
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
  Widget build(BuildContext context) => RuleSlider(
    // Nothing in the middle, and equal room either side of it.
    origin: 0.5,
    value: session.settings.bias / (StudySettings.maxBias * 2) + 0.5,
    onChanged: (v) => session.setBias((v - 0.5) * StudySettings.maxBias * 2),
  );
}

class DetailControl extends StatelessWidget {
  const DetailControl({super.key, required this.session});
  final CanvasSession session;

  @override
  Widget build(BuildContext context) =>
      RuleSlider(value: session.settings.detail, onChanged: session.setDetail);
}

/// Which way the photograph is simplified before it is quantised.
class SmoothingControl extends StatelessWidget {
  const SmoothingControl({super.key, required this.session});
  final CanvasSession session;

  @override
  Widget build(BuildContext context) => SegmentedControl<Smoothing>(
    values: Smoothing.values,
    selected: session.settings.smoothing,
    labelOf: (v) => v.label,
    onChanged: session.setSmoothing,
    height: 30,
    fontSize: 10,
  );
}

class ScaleControl extends StatelessWidget {
  const ScaleControl({super.key, required this.session});
  final CanvasSession session;

  @override
  Widget build(BuildContext context) {
    final s = DesignScale.of(context);
    return SizedBox(
      height: 32 * s,
      child: Row(
        // Without this a swatch sizes to its bands, which have no height of
        // their own, and collapses to a hairline.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final scale in ValueScale.values) ...[
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => session.setScale(scale),
                child: Container(
                  foregroundDecoration: BoxDecoration(
                    border: Border.all(
                      color: scale == session.settings.scale
                          ? AskanceColors.accent
                          : AskanceColors.swatchBorder,
                      width: kRule,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final band in scale.swatchBands)
                        Expanded(child: ColoredBox(color: band)),
                    ],
                  ),
                ),
              ),
            ),
            if (scale != ValueScale.values.last) SizedBox(width: 8 * s),
          ],
        ],
      ),
    );
  }
}

class GridControl extends StatelessWidget {
  const GridControl({super.key, required this.session});
  final CanvasSession session;

  @override
  Widget build(BuildContext context) {
    final s = DesignScale.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedControl<GridMode>(
          values: GridMode.values,
          selected: session.settings.grid,
          labelOf: (v) => v.label,
          onChanged: session.setGrid,
          fontSize: 10,
        ),
        SizedBox(height: 12 * s),
        Row(
          children: [
            Text('DIVISIONS', style: AskanceText.sectionLabel().by(s)),
            const Spacer(),
            RuleStepper(
              value: session.settings.gridDivisions,
              min: StudySettings.minDivisions,
              max: StudySettings.maxDivisions,
              onChanged: session.setGridDivisions,
            ),
          ],
        ),
      ],
    );
  }
}

/// A label line above a control: flush-left name, optional flush-right value in
/// the accent red.
class ControlLabelRow extends StatelessWidget {
  const ControlLabelRow({super.key, required this.label, this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final s = DesignScale.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: 10 * s),
      child: Row(
        children: [
          Text(label, style: AskanceText.sectionLabel().by(s)),
          const Spacer(),
          if (value != null)
            Text(
              value!,
              style: AskanceText.controlLabel(
                11,
                tracking: 0.06,
                color: AskanceColors.accent,
              ).by(s),
            ),
        ],
      ),
    );
  }
}

/// The phone's tool panel: one tool at a time, directly above the tool bar,
/// with a 2px accent top rule.
class ToolPanel extends StatelessWidget {
  const ToolPanel({super.key, required this.session, required this.tool});

  final CanvasSession session;
  final CanvasTool tool;

  @override
  Widget build(BuildContext context) {
    final s = DesignScale.of(context);
    return Container(
      width: double.infinity,
      color: AskanceColors.ink,
      padding: EdgeInsets.symmetric(vertical: 14 * s, horizontal: 16 * s),
      foregroundDecoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: AskanceColors.accent, width: kRule),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: switch (tool) {
          CanvasTool.steps => [
            const ControlLabelRow(label: 'HOW MANY VALUES'),
            ValuesControl(session: session),
            SizedBox(height: 16 * s),
            ControlLabelRow(
              label: 'WHERE THE STEPS FALL',
              value: BiasControl.readout(session.settings.bias),
            ),
            BiasControl(session: session),
          ],
          CanvasTool.detail => [
            const ControlLabelRow(label: 'HOW THE SHAPES FORM'),
            SmoothingControl(session: session),
            SizedBox(height: 16 * s),
            ControlLabelRow(
              label: 'DETAIL OF THE SHAPES',
              value: '${(session.settings.detail * 100).round()}',
            ),
            DetailControl(session: session),
          ],
          CanvasTool.scale => [
            const ControlLabelRow(label: 'ROOT OF THE SCALE'),
            ScaleControl(session: session),
          ],
          CanvasTool.grid => [
            const ControlLabelRow(label: 'GRID'),
            GridControl(session: session),
          ],
        },
      ),
    );
  }
}
