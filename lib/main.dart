import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/qr_transfer/signal.dart';
import 'state/providers.dart';
import 'ui/sketch_link/launch_link_stub.dart'
    if (dart.library.js_interop) 'ui/sketch_link/launch_link_web.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // A phone that opened a laptop's code lands here to send it a sketch.
  final launched = takeLaunchLink();
  final room = launched == null ? null : QrSignal.parseSketchLink(launched);
  runApp(
    ProviderScope(
      overrides: [launchSketchRoomProvider.overrideWith((ref) => room)],
      child: const AskanceApp(),
    ),
  );
}
