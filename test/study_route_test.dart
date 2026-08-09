import 'package:askance/ui/shelf/shelf_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the route a study opens with can carry the Hero flight', () {
    final route = studyRoute();
    // Zero here means the card would snap to full screen with no growth, and
    // the same going back.
    expect(route.transitionDuration, kStudyOpenDuration);
    expect(route.reverseTransitionDuration, kStudyOpenDuration);
  });
}
