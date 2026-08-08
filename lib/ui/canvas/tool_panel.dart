import 'package:flutter/widgets.dart';

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

class DetailControl extends StatelessWidget {
  const DetailControl({super.key, required this.session});
  final CanvasSession session;

  @override
  Widget build(BuildContext context) =>
      RuleSlider(value: session.settings.detail, onChanged: session.setDetail);
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
        children: [
          for (final scale in ValueScale.values) ...[
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => session.setScale(scale),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: scale == session.settings.scale
                          ? AskanceColors.accent
                          : AskanceColors.dividerDark,
                      width: kRule,
                    ),
                    gradient: LinearGradient(
                      colors: scale.swatchStops,
                      stops: const [0, 0.25, 0.5, 0.75],
                    ),
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
          ],
          CanvasTool.detail => [
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
