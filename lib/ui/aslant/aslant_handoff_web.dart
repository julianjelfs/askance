import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../../data/aslant_handoff.dart';

/// Whether Aslant opened this page to hand it a picture. Wipes the marker
/// from the address bar, so a reload or a bookmark doesn't wait for one.
bool takeAslantLaunch() {
  final location = web.window.location;
  if (location.hash != aslantLaunchFragment) return false;
  web.window.history.replaceState(
    null,
    '',
    '${location.pathname}${location.search}',
  );
  return true;
}

/// Tells the tab that opened this one that askance is listening, then waits
/// for Aslant's picture. Null when there is no opener to ask (an installed
/// app on a phone can lose it) or nothing arrives in time; Aslant tells its
/// user so on its side.
Future<AslantStudy?> receiveFromAslant({
  Duration timeout = const Duration(seconds: 20),
}) async {
  final opener = web.window.opener;
  if (opener == null) return null;
  final arrived = Completer<AslantStudy?>();
  final listener = (web.MessageEvent event) {
    final study = parseAslantMessage(event.origin, event.data.dartify());
    if (study != null && !arrived.isCompleted) arrived.complete(study);
  }.toJS;
  web.window.addEventListener('message', listener);
  try {
    (opener as web.Window).postMessage(
      {'type': aslantReadyType}.jsify(),
      aslantOrigin.toJS,
    );
    return await arrived.future.timeout(timeout, onTimeout: () => null);
  } catch (_) {
    return null;
  } finally {
    web.window.removeEventListener('message', listener);
  }
}
