import 'dart:typed_data';

import '../model/study.dart';

export 'repository_io.dart'
    if (dart.library.js_interop) 'repository_web.dart'
    show createStudyRepository;

/// Storage for the shelf. The source image is always *copied* rather than
/// referenced: photo-library references can be revoked, and a study whose
/// image has vanished is not a study.
abstract class StudyRepository {
  Future<List<Study>> loadStudies();

  Future<void> saveStudies(List<Study> studies);

  /// Copies [bytes] into app storage and returns the key to read it back with.
  Future<String> putImage(Uint8List bytes, {String extension = 'jpg'});

  Future<Uint8List?> readImage(String key);

  Future<void> deleteImage(String key);

  /// Whether onboarding has been completed at least once.
  Future<bool> loadOnboardingSeen();

  Future<void> saveOnboardingSeen(bool seen);
}
