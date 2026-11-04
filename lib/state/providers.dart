import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/study_repository.dart';
import '../engine/engine.dart';
import '../model/study.dart';
import 'canvas_session.dart';
import 'sketch_link.dart';

final repositoryProvider = Provider<StudyRepository>(
  (ref) => createStudyRepository(),
);

final shaderProvider = FutureProvider<ValueShader>((ref) => ValueShader.load());

final sessionProvider = Provider<CanvasSession>((ref) {
  final session = CanvasSession();
  // A study that is already on the shelf keeps itself up to date; there is no
  // second save step once it exists.
  session.onPersist = (id, settings, name) =>
      ref.read(studiesProvider.notifier).updateSettings(id, settings, name);
  ref.onDispose(session.dispose);
  return session;
});

/// The laptop end of sending a photo of the sketch from a phone. Each
/// photograph that arrives is laid over whichever study is open.
final sketchLinkProvider = ChangeNotifierProvider<SketchLink>(
  (ref) => SketchLink(
    (bytes) => ref
        .read(studiesProvider.notifier)
        .addSketch(ref.read(sessionProvider), bytes),
  ),
);

/// The room in the link this page was opened with, when a phone opened a
/// laptop's code to send it a sketch. Set once at launch.
final launchSketchRoomProvider =
    StateProvider<({String token, String keyB64})?>((ref) => null);

final onboardingSeenProvider = AsyncNotifierProvider<OnboardingNotifier, bool>(
  OnboardingNotifier.new,
);

class OnboardingNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() => ref.read(repositoryProvider).loadOnboardingSeen();

  Future<void> markSeen() async {
    await ref.read(repositoryProvider).saveOnboardingSeen(true);
    state = const AsyncData(true);
  }
}

final studiesProvider = AsyncNotifierProvider<StudiesNotifier, List<Study>>(
  StudiesNotifier.new,
);

class StudiesNotifier extends AsyncNotifier<List<Study>> {
  @override
  Future<List<Study>> build() async {
    final studies = await ref.read(repositoryProvider).loadStudies();
    studies.sort((a, b) => b.date.compareTo(a.date));
    return studies;
  }

  /// Writes the current settings back to the open study, or creates a new one
  /// if this study has never been saved.
  Future<Study> keep(CanvasSession session) async {
    final repo = ref.read(repositoryProvider);
    final existing = state.valueOrNull ?? const <Study>[];

    var imageKey = session.imageKey;
    if (imageKey == null || imageKey.isEmpty) {
      final bytes = session.imageBytes;
      if (bytes == null) throw StateError('no source image to keep');
      imageKey = await repo.putImage(bytes);
      session.imageKey = imageKey;
    }

    final study = session.toStudy();
    session.studyId = study.id;

    final next = [...existing];
    final index = next.indexWhere((s) => s.id == study.id);
    if (index >= 0) {
      next[index] = study;
    } else {
      next.insert(0, study);
    }
    next.sort((a, b) => b.date.compareTo(a.date));
    await repo.saveStudies(next);
    state = AsyncData(next);
    return study;
  }

  /// Writes settled settings back to a study that is already on the shelf.
  ///
  /// The date is deliberately left alone: adjusting a study is not the same as
  /// making one, and bumping it would silently reorder the shelf under the
  /// user while they were working.
  Future<void> updateSettings(
    String id,
    StudySettings settings,
    String name,
  ) async {
    final existing = state.valueOrNull ?? const <Study>[];
    final index = existing.indexWhere((s) => s.id == id);
    if (index < 0) return;

    final trimmed = name.trim().isEmpty ? 'Untitled study' : name.trim();
    final current = existing[index];
    if (current.settings == settings && current.name == trimmed) return;

    final next = [...existing];
    next[index] = current.copyWith(settings: settings, name: trimmed);
    await ref.read(repositoryProvider).saveStudies(next);
    state = AsyncData(next);
  }

  Future<void> delete(String id) async {
    // If the study being deleted is the one open in the session, empty the
    // session too — otherwise its ghost stays on the desktop stage, named in
    // the rail and still shareable.
    final session = ref.read(sessionProvider);
    if (session.studyId == id) session.clear();

    final repo = ref.read(repositoryProvider);
    final existing = state.valueOrNull ?? const <Study>[];
    final victim = existing.where((s) => s.id == id).firstOrNull;
    final next = existing.where((s) => s.id != id).toList();
    await repo.saveStudies(next);
    // Only drop the image once no remaining study points at it.
    if (victim != null && !next.any((s) => s.imageKey == victim.imageKey)) {
      await repo.deleteImage(victim.imageKey);
    }
    // A drawing's photograph belongs to the one study it was laid over.
    if (victim?.settings.sketch case final sketch?) {
      await repo.deleteImage(sketch.imageKey);
    }
    state = AsyncData(next);
  }

  Future<Uint8List?> imageBytes(Study study) =>
      ref.read(repositoryProvider).readImage(study.imageKey);

  /// Copies a photograph of the drawing into storage and lays it over the
  /// study open in [session], in place of any drawing already there. Throws
  /// if the bytes are not an image this platform can decode.
  Future<void> addSketch(
    CanvasSession session,
    Uint8List bytes, {
    String extension = 'jpg',
  }) async {
    final studyId = session.studyId;
    final image = await decodeSketch(bytes);
    final repo = ref.read(repositoryProvider);
    final key = await repo.putImage(bytes, extension: extension);
    // Another study opened while the photograph was being stored: this one
    // was never laid over anything.
    if (session.studyId != studyId || !session.hasImage) {
      image.dispose();
      await repo.deleteImage(key);
      return;
    }
    final replaced = session.addSketch(image, key);
    if (replaced != null) await _forgetSketch(session, replaced);
  }

  /// Takes the drawing off the study open in [session], and its photograph
  /// out of storage.
  Future<void> removeSketch(CanvasSession session) async {
    final key = session.removeSketch();
    if (key != null) await _forgetSketch(session, key);
  }

  /// Written to the shelf first, so the manifest never names a photograph
  /// that has gone.
  Future<void> _forgetSketch(CanvasSession session, String key) async {
    if (session.studyId case final id?) {
      await updateSettings(id, session.settled, session.name);
    }
    await ref.read(repositoryProvider).deleteImage(key);
  }

  /// Reads back the photograph of the drawing for the study just opened in
  /// [session]. A photograph that has gone leaves the study without one.
  Future<void> loadSketch(CanvasSession session) async {
    final key = session.settings.sketch?.imageKey;
    if (key == null) return;
    final bytes = await ref.read(repositoryProvider).readImage(key);
    if (bytes == null) return;
    try {
      session.loadSketchImage(key, await decodeSketch(bytes));
    } on Exception {
      // Stored but no longer decodable here: the study opens without it.
    }
  }
}

/// Decodes a photograph of the drawing for the screen, its long side held
/// to [kSketchMaxSide]: a phone's twelve megapixels would cost the GPU four
/// times the memory and show nothing more at the size it is drawn.
Future<ui.Image> decodeSketch(Uint8List bytes) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final codec = await ui.instantiateImageCodecWithSize(
    buffer,
    getTargetSize: (width, height) {
      final long = math.max(width, height);
      if (long <= kSketchMaxSide) {
        return ui.TargetImageSize(width: width, height: height);
      }
      final k = kSketchMaxSide / long;
      return ui.TargetImageSize(
        width: (width * k).round(),
        height: (height * k).round(),
      );
    },
  );
  final frame = await codec.getNextFrame();
  codec.dispose();
  return frame.image;
}

const int kSketchMaxSide = 2400;

/// Decodes image bytes into a GPU image.
Future<ui.Image> decodeImage(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  codec.dispose();
  return frame.image;
}
