import 'dart:typed_data';

/// Aslant (https://aslant.julianjelfs.co.uk), the head-lighting companion,
/// hands a picture over by opening askance in a new tab at
/// [aslantLaunchFragment]. The new tab tells the tab that opened it that it
/// is ready, Aslant posts the picture back, and it opens as a new study.
///
/// Only Aslant's own origin is listened to: any page can open askance with
/// that fragment, but only Aslant can post a picture that is accepted.
const aslantOrigin = 'https://aslant.julianjelfs.co.uk';

/// The fragment Aslant opens askance with. The fragment, not the query, so
/// it never reaches a server log.
const aslantLaunchFragment = '#from=aslant';

/// What askance posts to the opener once it is listening.
const aslantReadyType = 'askance:ready';

/// What Aslant posts back: the picture as PNG bytes, and study settings in
/// the shape [StudySettings.fromJson] reads.
const aslantStudyType = 'aslant:study';

typedef AslantStudy = ({Uint8List imageBytes, Map<String, Object?> settings});

/// The study in a message, or null if the message is not one from Aslant:
/// another origin, another type, or no picture.
AslantStudy? parseAslantMessage(String origin, Object? data) {
  if (origin != aslantOrigin) return null;
  if (data is! Map || data['type'] != aslantStudyType) return null;
  final image = switch (data['image']) {
    final Uint8List bytes => bytes,
    final ByteBuffer buffer => buffer.asUint8List(),
    _ => null,
  };
  if (image == null || image.isEmpty) return null;
  final settings = data['settings'];
  return (
    imageBytes: image,
    settings: settings is Map
        ? settings.map((k, v) => MapEntry('$k', v))
        : const <String, Object?>{},
  );
}
