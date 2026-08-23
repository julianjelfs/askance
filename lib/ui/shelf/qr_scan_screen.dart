import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../data/qr_transfer/transfer.dart';
import '../../model/study.dart';
import '../../state/providers.dart';
import '../../theme.dart';
import '../canvas/canvas_screen.dart';
import '../widgets/controls.dart';
import 'shelf_screen.dart' show NoTransitionRoute;

/// Scans a code off another askance's screen and receives the study it
/// offers: photograph, settings, zoom and all. Lands straight on the canvas.
class QrScanScreen extends ConsumerStatefulWidget {
  const QrScanScreen({super.key});

  @override
  ConsumerState<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends ConsumerState<QrScanScreen> {
  QrReceiver? _receiver;
  String? _stage;
  double? _fraction;
  bool _failed = false;

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_receiver != null) return;
    final payload = capture.barcodes.firstOrNull?.rawValue;
    if (payload == null || !payload.startsWith('askance1:')) return;

    final receiver = _receiver = QrReceiver(
      onProgress: (stage, fraction) {
        if (mounted) {
          setState(() {
            _stage = stage;
            _fraction = fraction;
          });
        }
      },
    );
    try {
      final received = await receiver.receive(payload);
      final image = await decodeImage(received.imageBytes);
      if (!mounted) return;
      final session = ref.read(sessionProvider);
      session.startFreshStudy();
      session.loadImage(image, received.imageBytes);
      session.applyTransferredSettings(
        StudySettings.fromJson(received.settings),
      );
      // An arrived study is as much an import as a picked photograph: onto
      // the shelf without a keep step.
      await ref.read(studiesProvider.notifier).keep(session);
      if (!mounted) return;
      // The desktop's canvas is its stage; the phone pushes the canvas
      // screen. Wide layouts pop back with a result so the shelf overlay can
      // close over the newly arrived study.
      if (MediaQuery.sizeOf(context).width >= kDesktopBreakpoint) {
        Navigator.of(context).pop(true);
      } else {
        Navigator.of(context).pushReplacement(
          NoTransitionRoute(builder: (_) => const CanvasScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _failed = true;
          _stage = 'Failed: $e';
          _receiver = null;
        });
      }
    } finally {
      receiver.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = DesignScale.of(context);
    final stage = _stage;
    return ColoredBox(
      color: AskanceColors.ink,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 46 * s,
              child: Row(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).maybePop(),
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16 * s),
                      child: Text(
                        '←',
                        style: AskanceText.button(
                          16,
                          color: AskanceColors.ground,
                        ).by(s),
                      ),
                    ),
                  ),
                  Text(
                    'SCAN THE CODE ON THE OTHER SCREEN',
                    style: AskanceText.controlLabel(
                      10,
                      tracking: 0.06,
                      color: AskanceColors.ground,
                    ).by(s),
                  ),
                ],
              ),
            ),
            Expanded(
              child: stage == null
                  ? MobileScanner(onDetect: _onDetect)
                  : Center(
                      child: Text(
                        _fraction != null && _fraction! > 0 && _fraction! < 1
                            ? '$stage ${(_fraction! * 100).round()}%'
                            : stage,
                        textAlign: TextAlign.center,
                        style: AskanceText.controlLabel(
                          11,
                          tracking: 0.06,
                          color: _failed
                              ? AskanceColors.accent
                              : AskanceColors.ground,
                        ).by(s),
                      ),
                    ),
            ),
            if (_failed)
              Padding(
                padding: EdgeInsets.all(16 * s),
                child: ActionButton(
                  label: 'Try again',
                  onPressed: () => setState(() {
                    _stage = null;
                    _failed = false;
                  }),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
