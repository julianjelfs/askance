import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../model/study.dart';
import 'study_repository.dart';

StudyRepository createStudyRepository() => FileStudyRepository();

/// iOS, Android and macOS: a readable JSON manifest beside a directory of
/// copied source images.
class FileStudyRepository implements StudyRepository {
  Directory? _root;

  static const _entitlementKey = 'askance.unlocked';
  static const _onboardingKey = 'askance.onboardingSeen';

  Future<Directory> _dir() async {
    if (_root != null) return _root!;
    final docs = await getApplicationDocumentsDirectory();
    final root = Directory('${docs.path}/askance');
    if (!root.existsSync()) root.createSync(recursive: true);
    final images = Directory('${root.path}/images');
    if (!images.existsSync()) images.createSync(recursive: true);
    return _root = root;
  }

  Future<File> _manifest() async => File('${(await _dir()).path}/studies.json');

  @override
  Future<List<Study>> loadStudies() async {
    final file = await _manifest();
    if (!file.existsSync()) return const [];
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((e) => Study.fromJson(e.cast<String, Object?>()))
          .nonNulls
          .toList();
    } catch (e) {
      // A corrupt manifest should cost the shelf, not the app.
      return const [];
    }
  }

  @override
  Future<void> saveStudies(List<Study> studies) async {
    final file = await _manifest();
    final encoded = const JsonEncoder.withIndent(
      '  ',
    ).convert(studies.map((s) => s.toJson()).toList());
    // Write to a sibling and rename, so an interrupted write cannot leave a
    // half-written manifest behind.
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(encoded, flush: true);
    await tmp.rename(file.path);
  }

  @override
  Future<String> putImage(Uint8List bytes, {String extension = 'jpg'}) async {
    final key = '${DateTime.now().microsecondsSinceEpoch}.$extension';
    final file = File('${(await _dir()).path}/images/$key');
    await file.writeAsBytes(bytes, flush: true);
    return key;
  }

  @override
  Future<Uint8List?> readImage(String key) async {
    final file = File('${(await _dir()).path}/images/$key');
    if (!file.existsSync()) return null;
    return file.readAsBytes();
  }

  @override
  Future<void> deleteImage(String key) async {
    final file = File('${(await _dir()).path}/images/$key');
    if (file.existsSync()) await file.delete();
  }

  @override
  Future<bool> loadEntitlement() async =>
      (await SharedPreferences.getInstance()).getBool(_entitlementKey) ?? false;

  @override
  Future<void> saveEntitlement(bool unlocked) async =>
      (await SharedPreferences.getInstance()).setBool(
        _entitlementKey,
        unlocked,
      );

  @override
  Future<bool> loadOnboardingSeen() async =>
      (await SharedPreferences.getInstance()).getBool(_onboardingKey) ?? false;

  @override
  Future<void> saveOnboardingSeen(bool seen) async =>
      (await SharedPreferences.getInstance()).setBool(_onboardingKey, seen);
}
