import 'package:flutter/widgets.dart';

import '../../state/sketch_link.dart';
import '../../theme.dart';
import '../widgets/controls.dart';
import '../widgets/qr_code.dart';

/// Shows the code a phone scans to send a photo of the sketch here, and
/// closes itself once the first photo has arrived and been laid over the
/// study. Closing it before a phone has connected takes the code away;
/// after, the phone stays connected for the next photo.
Future<void> showSketchLinkDialog(BuildContext context, SketchLink link) {
  if (!link.connected) link.open();
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Send a sketch from your phone',
    barrierColor: const Color(0x991C1B1A),
    transitionDuration: AskanceMotion.sheetSlide,
    pageBuilder: (context, _, _) => const SizedBox.shrink(),
    transitionBuilder: (context, animation, _, _) => Center(
      child: FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: AskanceMotion.slide),
        child: SizedBox(width: 360, child: _SketchLinkCard(link: link)),
      ),
    ),
  ).whenComplete(() {
    if (!link.connected) link.close();
  });
}

class _SketchLinkCard extends StatefulWidget {
  const _SketchLinkCard({required this.link});
  final SketchLink link;

  @override
  State<_SketchLinkCard> createState() => _SketchLinkCardState();
}

class _SketchLinkCardState extends State<_SketchLinkCard> {
  late final int _arrived = widget.link.received;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    widget.link.addListener(_changed);
  }

  @override
  void dispose() {
    widget.link.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    // The photo is over the study behind: the card has done its job.
    if (widget.link.received > _arrived && !_closing) {
      _closing = true;
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final link = widget.link;
    final url = link.link;
    final (status, note) = switch (link.stage) {
      SketchLinkStage.starting => ('Making a code…', null),
      SketchLinkStage.off => (
        'Not connected',
        'The phone went, or the code was closed. Make a new one to '
            'connect again.',
      ),
      SketchLinkStage.waiting => (
        "Scan this with your phone's camera",
        'It opens a page on the phone that takes the photo and sends it '
            'here. Both need to be online, ideally on the same Wi-Fi.',
      ),
      SketchLinkStage.connected => (
        'Phone connected',
        'Take the photo of your sketch on the phone.',
      ),
      SketchLinkStage.receiving => (
        'Receiving… ${(link.fraction * 100).round()}%',
        null,
      ),
      SketchLinkStage.failed => (
        'Could not make a code',
        'The signalling service could not be reached. Check the '
            'connection and try again.',
      ),
    };

    return Container(
      decoration: BoxDecoration(
        color: AskanceColors.gesso,
        borderRadius: BorderRadius.circular(AskanceRadius.sheet),
      ),
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Send from your phone', style: AskanceText.heading(22)),
          const SizedBox(height: 14),
          SizedBox(
            height: 276,
            child: Center(
              child: url != null
                  ? QrCodeCard(url, size: 252)
                  : Text('…', style: AskanceText.title(22)),
            ),
          ),
          const SizedBox(height: 14),
          Text(status, style: AskanceText.label(14)),
          if (note != null) ...[
            const SizedBox(height: 4),
            Text(
              note,
              style: AskanceText.body(13.5, color: AskanceColors.muted),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              if (link.stage == SketchLinkStage.failed ||
                  link.stage == SketchLinkStage.off) ...[
                Expanded(
                  child: ActionButton(
                    label: 'Try again',
                    height: 40,
                    fontSize: 14,
                    centred: true,
                    onPressed: link.open,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: ActionButton(
                  label: 'Close',
                  solid: false,
                  height: 40,
                  fontSize: 14,
                  centred: true,
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
