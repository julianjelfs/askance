import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:askance/data/study_repository.dart';
import 'package:askance/engine/lines.dart';
import 'package:askance/engine/sketch.dart';
import 'package:askance/model/study.dart';
import 'package:askance/state/providers.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Remembers what was stored and what was deleted.
class _Storage implements StudyRepository {
  final images = <String, Uint8List>{};
  final deleted = <String>[];
  List<Study> manifest = const [];
  var _next = 0;

  @override
  Future<List<Study>> loadStudies() async => [...manifest];
  @override
  Future<void> saveStudies(List<Study> next) async => manifest = next;
  @override
  Future<String> putImage(Uint8List bytes, {String extension = 'jpg'}) async {
    final key = '${_next++}.$extension';
    images[key] = bytes;
    return key;
  }

  @override
  Future<Uint8List?> readImage(String key) async => images[key];
  @override
  Future<void> deleteImage(String key) async {
    images.remove(key);
    deleted.add(key);
  }

  @override
  Future<bool> loadOnboardingSeen() async => true;
  @override
  Future<void> saveOnboardingSeen(bool seen) async {}
}

Future<ui.Image> _image(int width, int height) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF808080),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  return image;
}

/// A white page [page] pixels wide and high on a dark table, as a PNG.
Future<Uint8List> _pagePng(Size page) async {
  const size = Size(600, 500);
  final recorder = ui.PictureRecorder();
  Canvas(recorder)
    ..drawColor(const Color(0xFF333333), BlendMode.src)
    ..drawRect(
      Rect.fromCenter(
        center: size.center(Offset.zero),
        width: page.width,
        height: page.height,
      ),
      Paint()..color = const Color(0xFFF4F4F0),
    );
  final picture = recorder.endRecording();
  final image = await picture.toImage(600, 500);
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

Future<Uint8List> _png(int width, int height) async {
  final image = await _image(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  // The session hands images it lets go of to the scheduler to dispose.
  TestWidgetsFlutterBinding.ensureInitialized();

  const placed = SketchOverlay(
    imageKey: 'sketch.jpg',
    center: Offset(0.4, 0.6),
    width: 0.7,
    rotation: 0.1,
    opacity: 0.35,
  );

  group('the sketch is kept with the study', () {
    test('its placement and opacity round-trip through JSON', () {
      const settings = StudySettings(sketch: placed);
      expect(StudySettings.fromJson(settings.toJson()), settings);
    });

    test('the page found in its photo, and whether it is straightened, '
        'round-trip through JSON', () {
      final settings = StudySettings(
        sketch: SketchOverlay(
          imageKey: placed.imageKey,
          center: placed.center,
          width: placed.width,
          page: const [
            Offset(0.1, 0.1),
            Offset(0.9, 0.12),
            Offset(0.88, 0.9),
            Offset(0.12, 0.85),
          ],
          straighten: false,
        ),
      );
      expect(StudySettings.fromJson(settings.toJson()), settings);
    });

    test('a damaged page costs the straightening, not the sketch', () {
      final json = const StudySettings(sketch: placed).toJson();
      (json['sketch'] as Map)['page'] = [
        [0.1, 0.1],
        'nonsense',
      ];
      final sketch = StudySettings.fromJson(json).sketch!;
      expect(sketch.page, isNull);
      expect(sketch.center, placed.center);
    });

    test('a damaged sketch costs the sketch, not the study', () {
      final json = const StudySettings(steps: 5).toJson()
        ..['sketch'] = {'imageKey': 'sketch.jpg', 'center': 'nonsense'};
      final settings = StudySettings.fromJson(json);
      expect(settings.sketch, isNull);
      expect(settings.steps, 5);
    });
  });

  test('a gesture keeps the point of the sketch under the fingers under '
      'them, as it scales and turns', () {
    const crop = Rect.fromLTRB(0.1, 0.2, 0.9, 0.8);
    const picture = Rect.fromLTWH(30, 40, 600, 450);
    const focalStart = Offset(250, 300);
    const focal = Offset(310, 270);
    const scale = 1.6;
    const rotation = 0.7;

    // A point of the sketch, measured from its centre in its own unturned,
    // unscaled frame, as it lies on screen.
    Offset onScreen(SketchOverlay sketch, Offset local) {
      final at = sketchOnScreen(sketch, crop, picture);
      final k = at.width / sketchOnScreen(placed, crop, picture).width;
      final c = math.cos(sketch.rotation);
      final s = math.sin(sketch.rotation);
      final p = local * k;
      return at.center + Offset(p.dx * c - p.dy * s, p.dx * s + p.dy * c);
    }

    // The sketch's own point that starts under the fingers.
    final start = sketchOnScreen(placed, crop, picture);
    final from = focalStart - start.center;
    final c = math.cos(-placed.rotation);
    final s = math.sin(-placed.rotation);
    final local = Offset(from.dx * c - from.dy * s, from.dx * s + from.dy * c);
    expect(onScreen(placed, local).dx, closeTo(focalStart.dx, 1e-6));

    final moved = movedSketch(
      placed,
      focalStart: focalStart,
      focal: focal,
      scale: scale,
      rotation: rotation,
      crop: crop,
      picture: picture,
    );
    final after = onScreen(moved, local);
    expect(after.dx, closeTo(focal.dx, 1e-6));
    expect(after.dy, closeTo(focal.dy, 1e-6));
    expect(moved.width, closeTo(placed.width * scale, 1e-9));
  });

  test('the sketch lies on the photograph: zooming and panning carry it '
      'with the picture', () {
    const crop = Rect.fromLTRB(0.1, 0.2, 0.9, 0.8);
    const whole = Rect.fromLTWH(0, 0, 400, 300);
    // The same crop zoomed in 2.5 times and panned.
    const zoomed = Rect.fromLTWH(-310, -120, 1000, 750);
    for (final picture in [whole, zoomed]) {
      final at = sketchOnScreen(placed, crop, picture);
      // Its centre sits on the same point of the photograph, and it covers
      // the same share of it.
      expect(screenToLine(at.center, crop, picture).dx, closeTo(0.4, 1e-9));
      expect(screenToLine(at.center, crop, picture).dy, closeTo(0.6, 1e-9));
      expect(at.width / picture.width * crop.width, closeTo(0.7, 1e-9));
    }
  });

  group('a sketch photo leaves storage with the sketch', () {
    late _Storage storage;
    late ProviderContainer container;

    setUp(() {
      storage = _Storage();
      container = ProviderContainer(
        overrides: [repositoryProvider.overrideWithValue(storage)],
      );
    });
    tearDown(() => container.dispose());

    Future<String> keptStudy() async {
      final session = container.read(sessionProvider);
      await container.read(studiesProvider.future);
      session.loadImage(await _image(40, 60), await _png(40, 60));
      final study = await container
          .read(studiesProvider.notifier)
          .keep(session);
      return study.id;
    }

    test('replacing it deletes the old photo, removing it deletes the new '
        'one, and the shelf names neither', () async {
      final id = await keptStudy();
      final session = container.read(sessionProvider);
      final notifier = container.read(studiesProvider.notifier);

      await notifier.addSketch(session, await _png(30, 20));
      final first = session.settings.sketch!.imageKey;
      await notifier.addSketch(session, await _png(20, 30));
      final second = session.settings.sketch!.imageKey;
      expect(storage.deleted, [first]);
      expect(
        storage.manifest.singleWhere((s) => s.id == id).settings.sketch,
        isNotNull,
      );

      await notifier.removeSketch(session);
      expect(storage.deleted, [first, second]);
      expect(
        storage.manifest.singleWhere((s) => s.id == id).settings.sketch,
        isNull,
      );
    });

    test('a photo of a page is stored as it came and shown squared up to '
        'the page; the whole photo can be had back', () async {
      await keptStudy();
      final session = container.read(sessionProvider);
      final notifier = container.read(studiesProvider.notifier);
      final bytes = await _pagePng(const Size(300, 420));

      await notifier.addSketch(session, bytes);
      final sketch = session.settings.sketch!;
      expect(storage.images[sketch.imageKey], same(bytes));
      expect(sketch.page, isNotNull);
      expect(
        session.sketchImage!.width / session.sketchImage!.height,
        closeTo(300 / 420, 0.02),
      );

      await notifier.straightenSketch(session, false);
      expect(session.settings.sketch!.straighten, isFalse);
      expect(session.sketchImage!.width, 600);
      expect(session.sketchImage!.height, 500);
    });

    test('straightening again looks for the page afresh, so corners found '
        'wrongly before are put right', () async {
      await keptStudy();
      final session = container.read(sessionProvider);
      final notifier = container.read(studiesProvider.notifier);
      await notifier.addSketch(session, await _pagePng(const Size(300, 420)));
      final kept = session.settings.sketch!;
      session.moveSketch(
        SketchOverlay(
          imageKey: kept.imageKey,
          center: kept.center,
          width: kept.width,
          page: const [
            Offset(0, 0),
            Offset(1, 0),
            Offset(0.9, 0.86),
            Offset(0.08, 0.85),
          ],
          straighten: false,
        ),
      );

      await notifier.straightenSketch(session, true);
      final page = session.settings.sketch!.page!;
      const want = [
        Offset(0.25, 0.08),
        Offset(0.75, 0.08),
        Offset(0.75, 0.92),
        Offset(0.25, 0.92),
      ];
      for (var i = 0; i < 4; i++) {
        expect((page[i] - want[i]).distance, lessThan(0.01), reason: '$i');
      }
    });

    test('deleting the study deletes its sketch photo', () async {
      final id = await keptStudy();
      final session = container.read(sessionProvider);
      final notifier = container.read(studiesProvider.notifier);
      await notifier.addSketch(session, await _png(30, 20));
      final key = session.settings.sketch!.imageKey;
      session.flushPersist();
      await Future<void>.delayed(Duration.zero);

      await notifier.delete(id);
      expect(storage.deleted, contains(key));
      expect(storage.images, isEmpty);
    });
  });
}
