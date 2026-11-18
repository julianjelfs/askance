import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:askance/data/study_repository.dart';
import 'package:askance/model/study.dart';
import 'package:askance/state/providers.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Storage whose shelf takes as long to load as the test says, the way
/// IndexedDB can at launch.
class _SlowStorage implements StudyRepository {
  _SlowStorage(this.manifest);

  List<Study> manifest;
  final loaded = Completer<void>();
  final images = <String, Uint8List>{};
  var _next = 0;

  @override
  Future<List<Study>> loadStudies() async {
    await loaded.future;
    return [...manifest];
  }

  @override
  Future<void> saveStudies(List<Study> next) async => manifest = next;
  @override
  Future<String> putImage(Uint8List bytes, {String extension = 'jpg'}) async {
    final key = 'new-${_next++}.$extension';
    images[key] = bytes;
    return key;
  }

  @override
  Future<Uint8List?> readImage(String key) async => images[key];
  @override
  Future<void> deleteImage(String key) async => images.remove(key);
  @override
  Future<bool> loadOnboardingSeen() async => true;
  @override
  Future<void> saveOnboardingSeen(bool seen) async {}
}

Study _study(String id) => Study(
  id: id,
  name: 'Study $id',
  date: DateTime(2026, 11, 1),
  imageKey: '$id.jpg',
  settings: const StudySettings(),
);

Future<(ui.Image, Uint8List)> _picture() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    const Rect.fromLTWH(0, 0, 8, 8),
    Paint()..color = const Color(0xFF808080),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(8, 8);
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return (image, data!.buffer.asUint8List());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A study kept before the shelf has loaded, as one handed over by Aslant
  // at launch is, once replaced the whole stored shelf with itself.
  test('keeping a study before the shelf loads keeps every stored study', () async {
    final storage = _SlowStorage([_study('a'), _study('b'), _study('c')]);
    final container = ProviderContainer(
      overrides: [repositoryProvider.overrideWithValue(storage)],
    );
    addTearDown(container.dispose);

    final session = container.read(sessionProvider);
    final (image, bytes) = await _picture();
    session.loadImage(image, bytes);
    container.read(studiesProvider);
    final kept = container.read(studiesProvider.notifier).keep(session);
    storage.loaded.complete();
    await kept;

    expect(storage.manifest.map((s) => s.id), containsAll(['a', 'b', 'c']));
    expect(storage.manifest, hasLength(4));
  });
}
