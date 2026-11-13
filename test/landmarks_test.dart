import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui';

import 'package:askance/engine/landmarks.dart';
import 'package:askance/engine/sketch.dart';
import 'package:askance/state/canvas_session.dart';
import 'package:askance/ui/canvas/points_compare.dart';
import 'package:flutter_test/flutter_test.dart';

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

/// A session with a 100 by 140 picture and a 60 by 80 drawing laid on it.
Future<CanvasSession> _session() async {
  final session = CanvasSession()
    ..loadImage(await _image(100, 140), Uint8List(0));
  session.addSketch(await _image(60, 80), 'sketch.png');
  return session;
}

/// Five points of a head on a 1000 by 1400 picture: crown, chin, the outer
/// corner of each eye, and the tip of the nose.
const _picture = [
  Offset(500, 200),
  Offset(500, 900),
  Offset(380, 520),
  Offset(620, 520),
  Offset(500, 700),
];

/// [points] turned by [turn] about the origin, scaled by [scale] and moved
/// by [shift]: the same drawing, placed differently.
List<Offset> _placed(
  List<Offset> points, {
  double turn = 0,
  double scale = 1,
  Offset shift = Offset.zero,
}) => [
  for (final p in points)
    Offset(
              p.dx * math.cos(turn) - p.dy * math.sin(turn),
              p.dx * math.sin(turn) + p.dy * math.cos(turn),
            ) *
            scale +
        shift,
];

void main() {
  test('a drawing with every point right, only placed differently, '
      'reports nothing out', () {
    final fit = fitLandmarks(
      _picture,
      _placed(_picture, turn: 0.07, scale: 0.8, shift: const Offset(40, -25)),
    )!;
    for (var i = 0; i < _picture.length; i++) {
      expect(fit.error(i).distance, lessThan(1e-9));
    }
    expect(fit.describe(), [
      'All 5 points are within 2.0% of where the '
          'picture puts them.',
    ]);
  });

  test('a point drawn too high takes all the error, named with how far, '
      'and the distances through it read as wrong', () {
    // The chin drawn 49 pixels high: 7% of the 700 pixel crown to chin.
    final drawn = [..._picture];
    drawn[1] = drawn[1] - const Offset(0, 49);
    final fit = fitLandmarks(_picture, _placed(drawn, scale: 1.2))!;
    // All of it lands on the chin, none spread over the points that are
    // right.
    expect(fit.error(1).dy, closeTo(0.07, 0.002));
    expect(fit.error(1).dx.abs(), lessThan(0.002));
    for (final i in [0, 2, 3, 4]) {
      expect(fit.error(i).distance, lessThan(0.002));
    }
    expect(fit.stretch(0, 1), lessThan(-kRatioTolerance));
    final report = fit.describe();
    expect(report.first, '4 of 5 points are where the picture puts them.');
    expect(report[1], startsWith('Point 2 is drawn 7.0% too high'));
    expect(report[1], contains('which makes the distance from'));
    // The distances through the chin are its effects, told once with it,
    // not each again on a line of their own.
    expect(report, hasLength(2));
  });

  test('named points are called by name; custom names as written', () {
    final drawn = [..._picture];
    drawn[1] = drawn[1] - const Offset(0, 49);
    final fit = fitLandmarks(
      _picture,
      drawn,
      names: const ['Top of head', 'Chin', 'Left eye', 'Right eye', 'Tip'],
    )!;
    expect(
      fit.describe()[1],
      startsWith(
        'The chin is drawn 7.0% too high, which makes the distance '
        'from Tip to the chin',
      ),
    );
  });

  test('under three pairs there is nothing to report', () {
    expect(fitLandmarks(_picture.sublist(0, 2), _picture.sublist(0, 2)), null);
  });

  test('fitting the sketch lays a right drawing\'s points on the picture\'s '
      'as the overlay paints it', () {
    const photo = Size(1000, 1400);
    const drawing = Size(600, 800);
    // The same head drawn smaller and a little turned on its own page.
    final drawn = _placed(
      _picture,
      turn: -0.1,
      scale: 0.5,
      shift: const Offset(40, 60),
    );
    final fit = fitLandmarks(_picture, drawn)!;
    final sketch = fit.overlay(
      const SketchOverlay(
        imageKey: 'sketch.jpg',
        center: Offset(0.2, 0.9),
        width: 0.3,
      ),
      photo,
      drawing,
    );
    // As paintSketch lays it: the drawing's middle at the centre, turned,
    // its width a share of the photograph's.
    final k = sketch.width * photo.width / drawing.width;
    final c = Offset(
      sketch.center.dx * photo.width,
      sketch.center.dy * photo.height,
    );
    for (var i = 0; i < _picture.length; i++) {
      final q = (drawn[i] - Offset(drawing.width / 2, drawing.height / 2)) * k;
      final at =
          c +
          Offset(
            q.dx * math.cos(sketch.rotation) - q.dy * math.sin(sketch.rotation),
            q.dx * math.sin(sketch.rotation) + q.dy * math.cos(sketch.rotation),
          );
      expect((at - _picture[i]).distance, lessThan(1e-6));
    }
  });

  group('marking points', () {
    // The session hands images it lets go of to the scheduler to dispose.
    TestWidgetsFlutterBinding.ensureInitialized();

    test(
      'a tap on the sketch marks the first point not yet marked there',
      () async {
        final session = await _session();
        session
          ..addLandmark(const Offset(0.3, 0.3))
          ..addLandmark(const Offset(0.6, 0.3));
        expect(session.nextMark, 0);
        session.placeMark(const Offset(0.32, 0.31));
        expect(session.nextMark, 1);
        session.placeMark(const Offset(0.62, 0.31));
        expect(session.nextMark, isNull);
        expect(session.settings.sketch!.marks, const [
          Offset(0.32, 0.31),
          Offset(0.62, 0.31),
        ]);
      },
    );

    test('a new photograph of the sketch keeps the picture\'s points and '
        'asks for each on the sketch again', () async {
      final session = await _session();
      for (final p in const [Offset(0.2, 0.2), Offset(0.8, 0.3)]) {
        session
          ..addLandmark(p)
          ..placeMark(p);
      }
      session.addSketch(await _image(60, 80), 'again.png');
      expect(session.settings.landmarks, hasLength(2));
      expect(session.nextMark, 0);
      expect(session.isMarked(0), isFalse);
    });

    test('undo takes back the last tap, even marking a new photograph of '
        'the sketch', () async {
      final session = await _session();
      for (final p in const [Offset(0.2, 0.2), Offset(0.8, 0.3)]) {
        session
          ..addLandmark(p)
          ..placeMark(p);
      }
      session.addSketch(await _image(60, 80), 'again.png');
      session.placeMark(const Offset(0.21, 0.2));
      // Point 2 waits for its mark, as it would had it just been placed on
      // the picture. Undo must take the mark of point 1, not point 2.
      expect(session.nextMark, 1);
      session.undoPoint();
      expect(session.settings.landmarks, hasLength(2));
      expect(session.nextMark, 0);
    });

    test(
      'done lays the sketch over the picture as the points fit it',
      () async {
        final session = await _session();
        session.setMarkingPoints(true);
        const picture = [
          Offset(0.1, 0.1),
          Offset(0.4, 0.12),
          Offset(0.25, 0.5),
        ];
        const marks = [Offset(0.2, 0.2), Offset(0.8, 0.25), Offset(0.5, 0.9)];
        for (var i = 0; i < 3; i++) {
          session
            ..addLandmark(picture[i])
            ..placeMark(marks[i]);
        }
        final expected = session.landmarkFit!.overlay(
          session.settings.sketch!,
          const Size(100, 140),
          const Size(60, 80),
        );
        expect(session.settings.sketch, isNot(expected));
        session.setMarkingPoints(false);
        expect(session.settings.sketch, expected);
      },
    );
  });

  test('portrait photographs go side by side in a square-ish room, '
      'landscape ones one above the other', () {
    const portrait = Size(600, 900);
    const landscape = Size(900, 600);
    expect(sideBySide(const Size(1100, 800), portrait, portrait), isTrue);
    expect(sideBySide(const Size(1100, 800), landscape, landscape), isFalse);
  });
}
