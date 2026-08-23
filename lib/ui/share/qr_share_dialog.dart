import 'package:flutter/widgets.dart';
import 'package:qr/qr.dart';

import '../../data/qr_transfer/transfer.dart';
import '../../state/canvas_session.dart';
import '../../theme.dart';

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
                  child: Text(
                    '←',
                    style: AskanceText.button(
                      16,
                      color: AskanceColors.ground,
                    ).by(s),
                  ),
                ),
              ),
            ),
            SizedBox(width: 6 * s),
            Expanded(
              child: Text(
                'Share with QR code',
                style: AskanceText.sheetTitle().by(s),
              ),
            ),
          ],
        ),
        SizedBox(height: 14 * s),
        if (payload == null)
          SizedBox(
            height: 276 * s,
            child: Center(
              child: Text(
                '…',
                style: AskanceText.button(22, color: AskanceColors.ground),
              ),
            ),
          )
        else
          Center(
            // White quiet zone around the code, as the spec asks for.
            child: Container(
              color: const Color(0xFFFFFFFF),
              padding: EdgeInsets.all(12 * s),
              child: CustomPaint(
                size: Size.square(252 * s),
                painter: _QrPainter(payload),
              ),
            ),
          ),
        SizedBox(height: 14 * s),
        Text(
          _fraction != null && _fraction! > 0 && _fraction! < 1
              ? '$_stage ${(_fraction! * 100).round()}%'
              : _stage,
          style: AskanceText.controlLabel(
            10,
            tracking: 0.06,
            color: _failed ? AskanceColors.accent : AskanceColors.mutedDark,
          ).by(s),
        ),
        SizedBox(height: 4 * s),
        Text(
          'On the other device, choose "Scan from QR code" on the shelf.',
          style: AskanceText.body(12, color: AskanceColors.mutedDark).by(s),
        ),
      ],
    );
  }
}

class _QrPainter extends CustomPainter {
  _QrPainter(String payload)
    : _qr = QrImage(
        QrCode.fromData(
          data: payload,
          errorCorrectLevel: QrErrorCorrectLevel.M,
        ),
      );

  final QrImage _qr;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF000000);
    final cell = size.width / _qr.moduleCount;
    for (var y = 0; y < _qr.moduleCount; y++) {
      for (var x = 0; x < _qr.moduleCount; x++) {
        if (_qr.isDark(y, x)) {
          // A hair of overlap so antialiasing cannot open seams between
          // modules.
          canvas.drawRect(
            Rect.fromLTWH(x * cell, y * cell, cell + 0.5, cell + 0.5),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _QrPainter old) => old._qr != _qr;
}
