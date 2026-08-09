import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/purchase_service.dart';
import '../data/study_repository.dart';
import '../engine/engine.dart';
import '../model/study.dart';
import 'canvas_session.dart';

final repositoryProvider = Provider<StudyRepository>(
  (ref) => createStudyRepository(),
);

final shaderProvider = FutureProvider<ValueShader>((ref) => ValueShader.load());

final purchaseServiceProvider = Provider<PurchaseService>((ref) {
  // The PWA cannot use store IAP, and the web build is free by design.
  if (kIsWeb || kProductId.isEmpty) return SimulatedPurchaseService();
  return StorePurchaseService();
});

final sessionProvider = Provider<CanvasSession>((ref) {
  final session = CanvasSession();
  // A study that is already on the shelf keeps itself up to date; there is no
  // second save step once it exists.
  session.onPersist = (id, settings, name) =>
      ref.read(studiesProvider.notifier).updateSettings(id, settings, name);
  ref.onDispose(session.dispose);
  return session;
});

/// Everything on the canvas is free forever. Only what outlives the session —
/// the shelf and every export — is gated, and never on web.
final entitlementProvider = AsyncNotifierProvider<EntitlementNotifier, bool>(
  EntitlementNotifier.new,
);

class EntitlementNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    if (kIsWeb) return true;
    return ref.read(repositoryProvider).loadEntitlement();
  }

  Future<PurchaseOutcome> unlock() async {
    final outcome = await ref.read(purchaseServiceProvider).purchase();
    if (outcome == PurchaseOutcome.success) await _grant();
    return outcome;
  }

  Future<PurchaseOutcome> restore() async {
    final outcome = await ref.read(purchaseServiceProvider).restore();
    if (outcome == PurchaseOutcome.success) await _grant();
    return outcome;
  }

  Future<void> _grant() async {
    await ref.read(repositoryProvider).saveEntitlement(true);
    state = const AsyncData(true);
  }
}

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
    final repo = ref.read(repositoryProvider);
    final existing = state.valueOrNull ?? const <Study>[];
    final victim = existing.where((s) => s.id == id).firstOrNull;
    final next = existing.where((s) => s.id != id).toList();
    await repo.saveStudies(next);
    // Only drop the image once no remaining study points at it.
    if (victim != null && !next.any((s) => s.imageKey == victim.imageKey)) {
      await repo.deleteImage(victim.imageKey);
    }
    state = AsyncData(next);
  }

  Future<Uint8List?> imageBytes(Study study) =>
      ref.read(repositoryProvider).readImage(study.imageKey);
}

/// Decodes image bytes into a GPU image.
Future<ui.Image> decodeImage(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  codec.dispose();
  return frame.image;
}
