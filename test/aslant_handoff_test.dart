import 'dart:typed_data';

import 'package:askance/data/aslant_handoff.dart';
import 'package:askance/model/study.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('a picture handed over by Aslant', () {
    final png = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47]);

    test('is accepted only from Aslant\'s origin', () {
      final message = {'type': aslantStudyType, 'image': png};
      expect(parseAslantMessage(aslantOrigin, message), isNotNull);
      for (final other in [
        'https://example.com',
        'http://aslant.julianjelfs.co.uk',
        'https://aslant.julianjelfs.co.uk.evil.example',
        'null',
      ]) {
        expect(parseAslantMessage(other, message), isNull, reason: other);
      }
    });

    test('needs the study type and a picture', () {
      expect(parseAslantMessage(aslantOrigin, {'image': png}), isNull);
      expect(
        parseAslantMessage(aslantOrigin, {'type': aslantStudyType}),
        isNull,
      );
      expect(
        parseAslantMessage(aslantOrigin, {
          'type': aslantStudyType,
          'image': Uint8List(0),
        }),
        isNull,
      );
      expect(parseAslantMessage(aslantOrigin, 'a string'), isNull);
    });

    // The browser hands JavaScript numbers over as doubles and object keys
    // untyped; the settings must still come out as the values asked for.
    test('carries its values setting into the study', () {
      final study = parseAslantMessage(aslantOrigin, <Object?, Object?>{
        'type': aslantStudyType,
        'image': png.buffer,
        'settings': <Object?, Object?>{'steps': 4.0},
      })!;
      expect(study.imageBytes, png);
      expect(StudySettings.fromJson(study.settings).steps, 4);
    });
  });
}
