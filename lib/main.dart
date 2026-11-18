import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/qr_transfer/signal.dart';
import 'state/providers.dart';
import 'ui/aslant/aslant_handoff_stub.dart'
    if (dart.library.js_interop) 'ui/aslant/aslant_handoff_web.dart';
import 'ui/sketch_link/launch_link_stub.dart'
    if (dart.library.js_interop) 'ui/sketch_link/launch_link_web.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // A phone that opened a laptop's code lands here to send it a sketch.
  final launched = takeLaunchLink();
  final room = launched == null ? null : QrSignal.parseSketchLink(launched);
  // Aslant opened this tab to hand over a picture of its head.
  final fromAslant = takeAslantLaunch();
  runApp(
    ProviderScope(
      overrides: [
        launchSketchRoomProvider.overrideWith((ref) => room),
        launchFromAslantProvider.overrideWith((ref) => fromAslant),
      ],
      child: const AskanceApp(),
    ),
  );
}
