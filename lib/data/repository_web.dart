import 'dart:convert';
import 'dart:typed_data';

import 'package:idb_shim/idb_browser.dart';

import '../model/study.dart';
import 'study_repository.dart';

StudyRepository createStudyRepository() => IndexedDbStudyRepository();

/// Web: the same manifest-plus-images shape as the native repository, held in
/// IndexedDB because a browser has no app documents directory and image bytes
/// are far too large for localStorage.
class IndexedDbStudyRepository implements StudyRepository {
  static const _dbName = 'askance';
  static const _dbVersion = 1;
  static const _metaStore = 'meta';
  static const _imageStore = 'images';

  static const _manifestKey = 'studies';
  static const _entitlementKey = 'unlocked';
  static const _onboardingKey = 'onboardingSeen';

  Database? _db;

  Future<Database> _open() async {
    if (_db != null) return _db!;
    return _db = await idbFactoryBrowser.open(
      _dbName,
      version: _dbVersion,
      onUpgradeNeeded: (VersionChangeEvent event) {
        final db = event.database;
        if (!db.objectStoreNames.contains(_metaStore)) {
          db.createObjectStore(_metaStore);
        }
        if (!db.objectStoreNames.contains(_imageStore)) {
          db.createObjectStore(_imageStore);
        }
      },
    );
  }

  Future<Object?> _get(String store, String key) async {
    final db = await _open();
    final txn = db.transaction(store, idbModeReadOnly);
    final value = await txn.objectStore(store).getObject(key);
    await txn.completed;
    return value;
  }

  Future<void> _put(String store, String key, Object value) async {
    final db = await _open();
    final txn = db.transaction(store, idbModeReadWrite);
    await txn.objectStore(store).put(value, key);
    await txn.completed;
  }

  @override
  Future<List<Study>> loadStudies() async {
    final raw = await _get(_metaStore, _manifestKey);
    if (raw is! String) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => Study.fromJson(e.cast<String, Object?>()))
          .nonNulls
          .toList();
    } catch (e) {
      return const [];
    }
  }

  @override
  Future<void> saveStudies(List<Study> studies) => _put(
    _metaStore,
    _manifestKey,
    jsonEncode(studies.map((s) => s.toJson()).toList()),
  );

  @override
  Future<String> putImage(Uint8List bytes, {String extension = 'jpg'}) async {
    final key = '${DateTime.now().microsecondsSinceEpoch}.$extension';
    // idb_shim round-trips a plain int list reliably across both the browser
    // and the in-memory factory used by tests.
    await _put(_imageStore, key, bytes.toList());
    return key;
  }

  @override
  Future<Uint8List?> readImage(String key) async {
    final raw = await _get(_imageStore, key);
    if (raw is List) return Uint8List.fromList(raw.cast<int>());
    return null;
  }

  @override
  Future<void> deleteImage(String key) async {
    final db = await _open();
    final txn = db.transaction(_imageStore, idbModeReadWrite);
    await txn.objectStore(_imageStore).delete(key);
    await txn.completed;
  }

  @override
  Future<bool> loadEntitlement() async =>
      await _get(_metaStore, _entitlementKey) == true;

  @override
  Future<void> saveEntitlement(bool unlocked) =>
      _put(_metaStore, _entitlementKey, unlocked);

  @override
  Future<bool> loadOnboardingSeen() async =>
      await _get(_metaStore, _onboardingKey) == true;

  @override
  Future<void> saveOnboardingSeen(bool seen) =>
      _put(_metaStore, _onboardingKey, seen);
}
