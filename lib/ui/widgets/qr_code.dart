import 'package:flutter/widgets.dart';
import 'package:qr/qr.dart';

import '../../theme.dart';

/// [payload] as a QR code on a white quiet zone, as the spec asks for.
class QrCodeCard extends StatelessWidget {
  const QrCodeCard(this.payload, {super.key, required this.size});

  final String payload;
  final double size;

  @override
  Widget build(BuildContext context) {
    final s = DesignScale.of(context);
    return Container(
      decoration: BoxDecoration(
        color: AskanceColors.paper,
        borderRadius: BorderRadius.circular(AskanceRadius.card * s),
      ),
      padding: EdgeInsets.all(12 * s),
      child: CustomPaint(size: Size.square(size), painter: _QrPainter(payload)),
    );
  }
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.payload)
    : _qr = QrImage(
        QrCode.fromData(
          data: payload,
          errorCorrectLevel: QrErrorCorrectLevel.M,
        ),
      );

  final String payload;
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
  bool shouldRepaint(covariant _QrPainter old) => old.payload != payload;
}
