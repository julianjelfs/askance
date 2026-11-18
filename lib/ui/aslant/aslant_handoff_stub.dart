import '../../data/aslant_handoff.dart';

/// A native app is never opened by Aslant.
bool takeAslantLaunch() => false;

Future<AslantStudy?> receiveFromAslant() async => null;
