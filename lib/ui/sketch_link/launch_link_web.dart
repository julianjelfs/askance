import 'package:web/web.dart' as web;

/// The address this page was opened at, when it is a sketch link, with the
/// link then wiped from the address bar: it holds the room's key, which has
/// no business in the history or a bookmark.
String? takeLaunchLink() {
  final location = web.window.location;
  if (!location.hash.startsWith('#sketch=')) return null;
  final href = location.href;
  web.window.history.replaceState(
    null,
    '',
    '${location.pathname}${location.search}',
  );
  return href;
}
