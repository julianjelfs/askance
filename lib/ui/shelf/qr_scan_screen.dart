import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:flutter/foundation.dart' show kIsWeb;
import '../../build_stamp.dart';
import '../../data/qr_transfer/still_decode.dart';
import '../pick_image.dart';
import '../../data/qr_transfer/transfer.dart';
import '../../model/study.dart';
import '../../state/providers.dart';
import '../../theme.dart';
import '../study_screen.dart';
import '../widgets/controls.dart';
import 'shelf_screen.dart' show NoTransitionRoute;

/// Scans a code off another askance's screen and receives the study it
/// offers: photograph, settings, zoom and all. Lands straight on the canvas.
class QrScanScreen extends ConsumerStatefulWidget {
  const QrScanScreen({super.key});

  @override
  ConsumerState<QrScanScreen> createState() => _QrScanScreenState();
}

/// Whether to attempt the live camera view. Earlier iPad reports of a blank
/// screen turned out to coincide with stale service-worker builds, so the
/// live scanner gets its fair trial everywhere — with the photograph route
/// alongside it on web as the escape hatch.
const bool _liveScannerWorks = true;

class _QrScanScreenState extends ConsumerState<QrScanScreen> {
  final _scanner = MobileScannerController(
    facing: CameraFacing.back,
    formats: const [BarcodeFormat.qrCode],
  );
  QrReceiver? _receiver;

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  String? _stage;
  double? _fraction;
  bool _failed = false;

  Future<void> _onDetect(BarcodeCapture capture) async {
    final payload = capture.barcodes.firstOrNull?.rawValue;
    if (payload == null || !payload.startsWith('askance1:')) return;
    await _begin(payload);
  }

  /// The live camera view does not render on every browser — some tablets
  /// composite the platform view to nothing — so a photograph of the code,
  /// taken through the native capture UI and decoded in Dart, is offered as
  /// the way past it.
  Future<void> _photoOfCode() async {
    final picked = await takePhoto();
    if (picked == null || !mounted) return;
    setState(() => _stage = 'Reading the code…');
    final payload = await decodeQrFromPhoto(picked.bytes);
    if (!mounted) return;
    if (payload == null || !payload.startsWith('askance1:')) {
      setState(() {
        _failed = true;
        _stage = 'No askance code found in that photo';
      });
      return;
    }
    await _begin(payload);
  }

  Future<void> _begin(String payload) async {
    if (_receiver != null) return;

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
      Navigator.of(
        context,
      ).pushReplacement(NoTransitionRoute(builder: (_) => const StudyScreen()));
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
                  const Spacer(),
                  Padding(
                    padding: EdgeInsets.only(right: 12 * s),
                    child: Text(
                      kBuildStamp,
                      style: AskanceText.caption(
                        9,
                        color: const Color(0x40F3F2F2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: stage == null && !_liveScannerWorks
                  ? Center(
                      child: Padding(
                        padding: EdgeInsets.all(24 * s),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Photograph the code on the other screen and '
                              'it will be read from the picture.',
                              textAlign: TextAlign.center,
                              style: AskanceText.body(
                                13,
                                color: AskanceColors.mutedDark,
                              ).by(s),
                            ),
                            SizedBox(height: 16 * s),
                            ActionButton(
                              label: 'Photograph the code',
                              trailing: '→',
                              onPressed: _photoOfCode,
                            ),
                          ],
                        ),
                      ),
                    )
                  : stage == null
                  ? MobileScanner(
                      controller: _scanner,
                      onDetect: _onDetect,
                      // The default error state is an unexplained black
                      // rectangle; say what actually went wrong instead.
                      errorBuilder: (context, error) => Center(
                        child: Padding(
                          padding: EdgeInsets.all(24 * s),
                          child: Text(
                            'Camera failed: '
                            '${error.errorCode.name}'
                            '${error.errorDetails?.message == null ? '' : ' — ${error.errorDetails!.message}'}',
                            textAlign: TextAlign.center,
                            style: AskanceText.controlLabel(
                              11,
                              tracking: 0.06,
                              color: AskanceColors.accent,
                            ).by(s),
                          ),
                        ),
                      ),
                    )
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
            if (kIsWeb && stage == null)
              Padding(
                padding: EdgeInsets.fromLTRB(16 * s, 12 * s, 16 * s, 16 * s),
                child: ActionButton(
                  label: 'Photo of the code instead',
                  solid: false,
                  onDark: true,
                  onPressed: _photoOfCode,
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
