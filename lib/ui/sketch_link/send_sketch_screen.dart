import 'package:flutter/widgets.dart';

import '../../data/qr_transfer/transfer.dart';
import '../../theme.dart';
import '../pick_image.dart';
import '../widgets/askance_mark.dart';
import '../widgets/controls.dart';

enum _Stage { connecting, ready, sending, gone, failed }

/// The phone's end of sending a sketch to a laptop: opened from the code on
/// the laptop's screen, it takes a photo of the drawing and sends it there.
/// Stays connected after, so checking again is one more photo.
class SendSketchScreen extends StatefulWidget {
  const SendSketchScreen({
    super.key,
    required this.room,
    required this.onLeave,
  });

  final ({String token, String keyB64}) room;

  /// Into the app proper, leaving the laptop behind.
  final VoidCallback onLeave;

  @override
  State<SendSketchScreen> createState() => _SendSketchScreenState();
}

class _SendSketchScreenState extends State<SendSketchScreen> {
  late SketchGuest _guest;
  _Stage _stage = _Stage.connecting;
  double _fraction = 0;
  int _sent = 0;
  String? _problem;

  @override
  void initState() {
    super.initState();
    _join();
  }

  Future<void> _join() async {
    late final SketchGuest guest;
    guest = _guest = SketchGuest(
      onClosed: () {
        if (mounted && identical(guest, _guest)) {
          setState(() => _stage = _Stage.gone);
        }
      },
    );
    try {
      await guest.join(token: widget.room.token, keyB64: widget.room.keyB64);
      if (mounted && identical(guest, _guest)) {
        setState(() => _stage = _Stage.ready);
      }
    } catch (e) {
      debugPrint('[askance-sketch] guest failed: $e');
      guest.dispose();
      if (mounted && identical(guest, _guest)) {
        setState(() => _stage = _Stage.failed);
      }
    }
  }

  Future<void> _send({required bool fromCamera}) async {
    final picked = fromCamera ? await takePhoto() : await pickFromLibrary();
    if (picked == null || !mounted) return;
    setState(() {
      _stage = _Stage.sending;
      _fraction = 0;
      _problem = null;
    });
    try {
      await _guest.send(
        picked.bytes,
        onFraction: (value) {
          if (mounted) setState(() => _fraction = value);
        },
      );
      if (mounted) {
        setState(() {
          _sent++;
          _stage = _Stage.ready;
        });
      }
    } catch (e) {
      if (mounted && _stage == _Stage.sending) {
        setState(() {
          _stage = _Stage.ready;
          _problem = 'That photo did not get through. Try it again.';
        });
      }
    }
  }

  @override
  void dispose() {
    _guest.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = DesignScale.of(context);
    final (heading, body) = switch (_stage) {
      _Stage.connecting => (
        'Connecting to your laptop',
        'Keep the code on the laptop showing for a moment.',
      ),
      _Stage.ready when _sent == 0 => (
        'Photograph your sketch',
        'Hold the phone square over the paper, with the whole drawing in '
            'the frame. It will appear over the study on your laptop.',
      ),
      _Stage.ready => (
        _sent == 1 ? 'Sent' : 'Sent $_sent photos',
        'It is over the study on your laptop now. Take another to replace '
            'it whenever you want to check again.',
      ),
      _Stage.sending => ('Sending', '${(_fraction * 100).round()}%'),
      _Stage.gone => (
        'Disconnected from your laptop',
        'Show the code on the laptop again and scan it to reconnect.',
      ),
      _Stage.failed => (
        'Could not reach your laptop',
        'The code may have expired, or the two devices cannot see each '
            'other. Show a new code on the laptop and scan it again, with '
            'both on the same Wi-Fi.',
      ),
    };
    final ready = _stage == _Stage.ready;

    return ColoredBox(
      color: AskanceColors.gesso,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(24 * s, 18 * s, 24 * s, 20 * s),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  AskanceMark(size: 22 * s),
                  SizedBox(width: 10 * s),
                  Text('Askance', style: AskanceText.display(22).by(s)),
                ],
              ),
              const Spacer(),
              Text(heading, style: AskanceText.heading(28).by(s)),
              SizedBox(height: 10 * s),
              Text(
                _problem ?? body,
                style: AskanceText.body(
                  15,
                  color: _problem == null
                      ? AskanceColors.muted
                      : AskanceColors.accentInk,
                ).by(s),
              ),
              const Spacer(),
              if (ready) ...[
                ActionButton(
                  label: _sent == 0 ? 'Take a photo' : 'Take another',
                  centred: true,
                  onPressed: () => _send(fromCamera: true),
                ),
                SizedBox(height: 10 * s),
                ActionButton(
                  label: 'Choose a photo',
                  solid: false,
                  centred: true,
                  onPressed: () => _send(fromCamera: false),
                ),
                SizedBox(height: 18 * s),
              ],
              Center(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onLeave,
                  child: Padding(
                    padding: EdgeInsets.all(8 * s),
                    child: Text(
                      'Open Askance on this phone instead',
                      style: AskanceText.caption(13).by(s),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
