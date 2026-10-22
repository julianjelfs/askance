import 'dart:js_interop';

import 'analytics.dart';

/// Set by count.js, which index.html loads. Absent when a blocker stops the
/// script, offline, or before it has arrived; every one of those is a count
/// lost, never an error.
@JS('goatcounter')
external _GoatCounter? get _goatcounter;

extension type _GoatCounter._(JSObject _) implements JSObject {
  external void count(_Vars vars);
}

extension type _Vars._(JSObject _) implements JSObject {
  external factory _Vars({String path, String title, bool event});
}

void countEvent(AppEvent event) {
  try {
    _goatcounter?.count(
      _Vars(path: event.path, title: event.title, event: true),
    );
  } catch (_) {
    // A half-loaded or replaced counter must not take a tap down with it.
  }
}
