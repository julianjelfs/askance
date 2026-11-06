import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:askance/engine/sketch_page.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// A sketchbook page, A-series portrait (1 wide, root 2 high), photographed
/// on a darker table by a phone tilted [tilt] radians off square and rolled
/// [roll] radians, into a [size] photograph.
class _Shot {
  const _Shot();

  static const tilt = 0.5;
  static const roll = 0.12;
  static const size = Size(900, 700);
  static final double pageHeight = math.sqrt2;

  /// Where the point [u] across and [v] down the page lands in the
  /// photograph, in pixels.
  Offset at(double u, double v) {
    final f =
        kPhoneFocal *
        1.08 *
        math.sqrt(size.width * size.width + size.height * size.height);
    const distance = 2.6;
    final x = u - 0.5;
    final y = v - pageHeight / 2;
    final y1 = y * math.cos(tilt);
    final z = distance + y * math.sin(tilt);
    final x2 = x * math.cos(roll) - y1 * math.sin(roll);
    final y2 = x * math.sin(roll) + y1 * math.cos(roll);
    return Offset(size.width / 2 + f * x2 / z, size.height / 2 + f * y2 / z);
  }

  List<Offset> get corners => [
    at(0, 0),
    at(1, 0),
    at(1, pageHeight),
    at(0, pageHeight),
  ];

  Path quad(double u0, double v0, double u1, double v1) =>
      Path()
        ..addPolygon([at(u0, v0), at(u1, v0), at(u1, v1), at(u0, v1)], true);

  /// The photograph: the page, a dark patch drawn in its top left quarter,
  /// and a stroke run right across it from edge to edge.
  Future<ui.Image> photograph() async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder)
      ..drawColor(const Color(0xFF3A3A3A), BlendMode.src)
      ..drawPath(
        quad(0, 0, 1, pageHeight),
        Paint()..color = const Color(0xFFF2F0EA),
      )
      ..drawPath(
        quad(0.1, 0.1, 0.4, 0.6),
        Paint()..color = const Color(0xFF202020),
      )
      ..drawLine(
        at(0, 1),
        at(1, 1),
        Paint()
          ..color = const Color(0xFF202020)
          ..strokeWidth = 3,
      );
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      size.width.round(),
      size.height.round(),
    );
    picture.dispose();
    return image;
  }
}

Future<ui.Image> _flat(Color color) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(color, BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(600, 400);
  picture.dispose();
  return image;
}

Future<Color> _pixel(ui.Image image, double x, double y) async {
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final i =
      ((y * image.height).round() * image.width + (x * image.width).round()) *
      4;
  final b = data.buffer.asUint8List();
  return Color.fromARGB(b[i + 3], b[i], b[i + 1], b[i + 2]);
}

/// A sketchbook page shot from above on a mid-grey carpet, as a phone sees
/// it: paper only a little lighter than the carpet, charcoal darker than
/// both covering most of the page up to thin margins, the photographer's
/// shadow over the lower left, and the phone's across the bottom edge.
const _carpetSize = Size(576, 1024);
const _carpetPage = Rect.fromLTRB(44, 162, 536, 874);

Future<ui.Image> _onCarpet() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..drawColor(const Color(0xFF8E8C88), BlendMode.src);
  // The carpet's weave: specks a little lighter and darker than it.
  final random = math.Random(7);
  for (var i = 0; i < 6000; i++) {
    final g = 0x8E + random.nextInt(41) - 20;
    canvas.drawRect(
      Rect.fromLTWH(
        random.nextDouble() * _carpetSize.width,
        random.nextDouble() * _carpetSize.height,
        3,
        3,
      ),
      Paint()..color = Color.fromARGB(255, g, g - 2, g - 6),
    );
  }
  canvas
    ..drawRect(_carpetPage, Paint()..color = const Color(0xFFD8D6D2))
    // Charcoal nearly to the edges of the paper.
    ..drawRect(
      Rect.fromLTRB(
        _carpetPage.left + 50,
        _carpetPage.top + 14,
        _carpetPage.right - 18,
        _carpetPage.bottom - 14,
      ),
      Paint()..color = const Color(0xFF4A4A4A),
    );
  // A shadow over the lower left, of page and carpet alike, deep enough
  // that the paper in it is darker than the carpet in the light.
  canvas
    ..drawRect(
      Rect.fromLTWH(0, 600, 330, 424),
      Paint()
        ..color = const Color(0xFF8C8C8C)
        ..blendMode = BlendMode.multiply,
    )
    // And the phone's own, hard and dark, across the bottom edge.
    ..drawOval(
      Rect.fromLTWH(160, _carpetPage.bottom - 40, 110, 260),
      Paint()..color = const Color(0xFF2A2A2A),
    );
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    _carpetSize.width.round(),
    _carpetSize.height.round(),
  );
  picture.dispose();
  return image;
}

/// The same page laid on black leather: dark enough that its sheen, taken
/// as a ratio, flickers as steeply as the edge of the paper does.
Future<ui.Image> _onLeather() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..drawColor(const Color(0xFF1E1E1E), BlendMode.src);
  final random = math.Random(11);
  for (var i = 0; i < 9000; i++) {
    final g = 0x14 + random.nextInt(0x30);
    canvas.drawRect(
      Rect.fromLTWH(
        random.nextDouble() * _carpetSize.width,
        random.nextDouble() * _carpetSize.height,
        2 + random.nextDouble() * 4,
        2 + random.nextDouble() * 4,
      ),
      Paint()..color = Color.fromARGB(255, g, g, g),
    );
  }
  canvas
    ..drawRect(_carpetPage, Paint()..color = const Color(0xFFD8D6D2))
    ..drawRect(
      Rect.fromLTRB(
        _carpetPage.left + 50,
        _carpetPage.top + 14,
        _carpetPage.right - 18,
        _carpetPage.bottom - 14,
      ),
      Paint()..color = const Color(0xFF4A4A4A),
    );
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    _carpetSize.width.round(),
    _carpetSize.height.round(),
  );
  picture.dispose();
  return image;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the corners of a page shot at a slant are found, clockwise from the '
      'top left, despite a stroke drawn right across it', () async {
    const shot = _Shot();
    final photo = await shot.photograph();
    addTearDown(photo.dispose);
    final page = await findPage(photo);
    expect(page, isNotNull);
    for (var i = 0; i < 4; i++) {
      final want = shot.corners[i];
      final got = Offset(
        page![i].dx * _Shot.size.width,
        page[i].dy * _Shot.size.height,
      );
      expect((got - want).distance, lessThan(6), reason: 'corner $i');
    }
  });

  test('a page shot at a slant is squared up to its true proportions, the '
      'right way up', () async {
    const shot = _Shot();
    final photo = await shot.photograph();
    addTearDown(photo.dispose);
    final page = (await findPage(photo))!;
    final straight = await straightenPage(photo, page);
    addTearDown(straight.dispose);

    // Read off its sides alone, foreshortened, the page would come out
    // about an eighth too wide. The lens here is 8% off the one assumed,
    // which at this steep a slant costs nearly 2% of its own.
    expect(
      straight.width / straight.height,
      closeTo(1 / math.sqrt2, 0.03 / math.sqrt2),
    );
    final patch = await _pixel(straight, 0.25, 0.25);
    final paper = await _pixel(straight, 0.75, 0.5);
    expect((patch.r * 255).round(), lessThan(80), reason: 'the dark patch');
    expect((paper.r * 255).round(), greaterThan(200), reason: 'the paper');
  });

  test('a page only a little lighter than the surface it lies on is found, '
      'though charcoal darker than both covers most of it and a shadow '
      'leaves part of it darker than the surface in the light', () async {
    final photo = await _onCarpet();
    addTearDown(photo.dispose);
    final page = await findPage(photo);
    expect(page, isNotNull);
    final want = [
      _carpetPage.topLeft,
      _carpetPage.topRight,
      _carpetPage.bottomRight,
      _carpetPage.bottomLeft,
    ];
    for (var i = 0; i < 4; i++) {
      final got = Offset(
        page![i].dx * _carpetSize.width,
        page[i].dy * _carpetSize.height,
      );
      expect((got - want[i]).distance, lessThan(12), reason: 'corner $i');
    }
  });

  test('a page on a dark, grainy surface is cropped to the paper, not '
      'pushed out onto the grain', () async {
    final photo = await _onLeather();
    addTearDown(photo.dispose);
    final page = await findPage(photo);
    expect(page, isNotNull);
    final want = [
      _carpetPage.topLeft,
      _carpetPage.topRight,
      _carpetPage.bottomRight,
      _carpetPage.bottomLeft,
    ];
    for (var i = 0; i < 4; i++) {
      final got = Offset(
        page![i].dx * _carpetSize.width,
        page[i].dy * _carpetSize.height,
      );
      expect((got - want[i]).distance, lessThan(12), reason: 'corner $i');
    }
  });

  test('without a page that stands out, or with one filling the photo, '
      'nothing is straightened', () async {
    final grey = await _flat(const Color(0xFF808080));
    addTearDown(grey.dispose);
    expect(await findPage(grey), isNull);

    final paper = await _flat(const Color(0xFFF2F0EA));
    addTearDown(paper.dispose);
    expect(await findPage(paper), isNull);
  });

  test('squared on, the proportions come from the sides', () {
    const size = Size(1000, 800);
    const corners = [
      Offset(200, 100),
      Offset(800, 100),
      Offset(800, 500),
      Offset(200, 500),
    ];
    expect(pageAspect(corners, size), closeTo(1.5, 1e-6));
  });
}
