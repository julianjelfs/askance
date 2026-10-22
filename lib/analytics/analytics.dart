export 'analytics_stub.dart'
    if (dart.library.js_interop) 'analytics_web.dart'
    show countEvent;

/// What the web build counts, through GoatCounter: a name and nothing else.
///
/// [countEvent] takes only one of these, so no photograph, filename, setting
/// or study name can reach the counter: there is no parameter to put one in.
/// The native apps count nothing.
enum AppEvent {
  photoLoaded('photo-loaded', 'Opened a photograph'),
  sampleLoaded('sample-loaded', 'Opened the sample portrait'),
  studyReceived('study-received', 'Received a study from another device'),
  exportSaved('export-saved', 'Saved an export'),
  exportCopied('export-copied', 'Copied an export'),
  exportPrinted('export-printed', 'Printed an export');

  const AppEvent(this.path, this.title);

  /// GoatCounter's name for the event, shown in its dashboard.
  final String path;
  final String title;
}
