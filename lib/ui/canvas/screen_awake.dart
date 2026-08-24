import 'package:wakelock_plus/wakelock_plus.dart';

/// Keeps the screen on while any canvas surface is up: a study used as a
/// painting reference must not go dark mid-brushstroke. Reference-counted
/// because the open transition briefly runs two surfaces at once.
abstract final class ScreenAwake {
  static int _holders = 0;

  static void acquire() {
    if (_holders++ == 0) WakelockPlus.enable();
  }

  static void release() {
    if (--_holders == 0) WakelockPlus.disable();
  }
}
