import 'package:flutter/foundation.dart';

import '../data/qr_transfer/signal.dart';
import '../data/qr_transfer/transfer.dart';

/// Where the phone is sent to open a sketch link: the web app the laptop is
/// running, or the published one when that is out of the phone's reach.
///
/// [page] is the address of this page on the web, null in a native app.
/// A page on this machine alone names an address the phone cannot reach,
/// and a native app has no address at all.
Uri sketchLinkBase({required Uri? page}) {
  final public = Uri.parse('https://askance.julianjelfs.co.uk/');
  if (page == null) return public;
  const local = {'localhost', '127.0.0.1', '::1', '[::1]', ''};
  if (local.contains(page.host)) return public;
  return Uri(
    scheme: page.scheme,
    host: page.host,
    port: page.hasPort ? page.port : null,
    path: page.path,
  );
}

enum SketchLinkStage {
  off,

  /// Reaching the broker and making the offer.
  starting,

  /// The code is up, waiting for a phone to open it.
  waiting,
  connected,

  /// A photograph on its way.
  receiving,
  failed,
}

/// The laptop end of sending a photo of the sketch from a phone. Lives as
/// long as the study is open, so after the first photo the phone stays
/// connected and the next is one more press of its shutter.
class SketchLink extends ChangeNotifier {
  SketchLink(this._onPhoto);

  /// Lays the photograph over the open study.
  final Future<void> Function(Uint8List bytes) _onPhoto;

  SketchLinkStage stage = SketchLinkStage.off;

  /// What the code says while [stage] is [SketchLinkStage.waiting].
  String? link;
  double fraction = 0;

  /// How many photographs have arrived over this connection.
  int received = 0;

  /// The last photograph arrived but would not open.
  bool photoFailed = false;

  SketchHost? _host;

  /// Bumped by every [open] and [close], so callbacks from a connection
  /// that has since been replaced change nothing.
  int _generation = 0;

  bool get connected =>
      stage == SketchLinkStage.connected || stage == SketchLinkStage.receiving;

  Future<void> open() async {
    close();
    final generation = ++_generation;
    bool current() => generation == _generation;
    _set(SketchLinkStage.starting);
    final host = _host = SketchHost(
      onConnected: () {
        if (current()) _set(SketchLinkStage.connected);
      },
      onFraction: (value) {
        if (!current()) return;
        fraction = value;
        _set(SketchLinkStage.receiving);
      },
      onPhoto: (bytes) async {
        if (!current()) return;
        received++;
        _set(SketchLinkStage.connected);
        try {
          await _onPhoto(bytes);
          photoFailed = false;
        } on Exception {
          photoFailed = true;
        }
        if (current()) notifyListeners();
      },
      onClosed: () {
        if (!current()) return;
        _host = null;
        _set(SketchLinkStage.off);
      },
    );
    try {
      await host.open(
        onRoomReady: (token, keyB64) {
          if (!current()) return;
          link = QrSignal.sketchLink(
            sketchLinkBase(page: kIsWeb ? Uri.base : null),
            token,
            keyB64,
          );
          _set(SketchLinkStage.waiting);
        },
      );
    } catch (e) {
      debugPrint('[askance-sketch] host failed: $e');
      if (!current()) return;
      host.dispose();
      _host = null;
      _set(SketchLinkStage.failed);
    }
  }

  void close() {
    _generation++;
    _host?.dispose();
    _host = null;
    received = 0;
    photoFailed = false;
    if (stage == SketchLinkStage.off) return;
    _set(SketchLinkStage.off);
  }

  void _set(SketchLinkStage next) {
    stage = next;
    if (next != SketchLinkStage.waiting) link = null;
    if (next != SketchLinkStage.receiving) fraction = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _generation++;
    _host?.dispose();
    super.dispose();
  }
}
