import 'package:flutter/widgets.dart';

import '../../data/qr_transfer/transfer.dart';
import '../../state/canvas_session.dart';
import '../../theme.dart';
import '../widgets/glyphs.dart';
import '../widgets/qr_code.dart';

/// The share sheet's QR face: swaps in for the sheet's usual content and runs
/// the whole exchange while it is showing — broker, scan, WebRTC handshake,
/// transfer. Going back cancels whatever is in flight.
class QrSharePanel extends StatefulWidget {
  const QrSharePanel({super.key, required this.session, required this.onBack});

  final CanvasSession session;
  final VoidCallback onBack;

  @override
  State<QrSharePanel> createState() => _QrSharePanelState();
}

class _QrSharePanelState extends State<QrSharePanel> {
  late final QrSender _sender;
  String? _payload;
  String _stage = 'Preparing…';
  double? _fraction;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _sender = QrSender(
      onProgress: (stage, fraction) {
        if (mounted) {
          setState(() {
            _stage = stage;
            _fraction = fraction;
          });
        }
      },
    );
    _start();
  }

  Future<void> _start() async {
    final bytes = widget.session.imageBytes;
    if (bytes == null) return;
    try {
      await _sender.send(
        imageBytes: bytes,
        settingsJson: widget.session.settled.toJson(),
        onQrReady: (payload) {
          if (mounted) setState(() => _payload = payload);
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _failed = true;
          _stage = 'Failed: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    _sender.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = DesignScale.of(context);
    final payload = _payload;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onBack,
              child: SizedBox(
                width: 32 * s,
                height: 32 * s,
                child: Center(
                  child: GlyphIcon(
                    Glyph.back,
                    size: 22 * s,
                    color: AskanceColors.graphite,
                  ),
                ),
              ),
            ),
            SizedBox(width: 6 * s),
            Expanded(
              child: Text(
                'Share with QR code',
                style: AskanceText.heading(22).by(s),
              ),
            ),
          ],
        ),
        SizedBox(height: 14 * s),
        if (payload == null)
          SizedBox(
            height: 276 * s,
            child: Center(child: Text('…', style: AskanceText.title(22))),
          )
        else
          Center(child: QrCodeCard(payload, size: 252 * s)),
        SizedBox(height: 14 * s),
        Text(
          _fraction != null && _fraction! > 0 && _fraction! < 1
              ? '$_stage ${(_fraction! * 100).round()}%'
              : _stage,
          style: AskanceText.label(
            14,
            color: _failed ? AskanceColors.accentInk : AskanceColors.graphite,
          ).by(s),
        ),
        SizedBox(height: 4 * s),
        Text(
          'On the other device, choose "Receive from another device" on the '
          'shelf.',
          style: AskanceText.body(13.5, color: AskanceColors.muted).by(s),
        ),
      ],
    );
  }
}
