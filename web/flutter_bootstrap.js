{{flutter_js}}
{{flutter_build_config}}

// No serviceWorkerSettings: Flutter's worker is now a stub that unregisters
// itself, and registering it at the root scope would replace sw.js, which
// index.html registers instead.
_flutter.loader.load();
