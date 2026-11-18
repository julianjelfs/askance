import 'dart:async' show unawaited;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../analytics/analytics.dart';
import '../../model/study.dart';
import '../../state/providers.dart';
import '../shelf/shelf_screen.dart' show NoTransitionRoute;
import '../study_screen.dart';
import 'aslant_handoff_stub.dart'
    if (dart.library.js_interop) 'aslant_handoff_web.dart';

/// Wraps the first screen when Aslant opened this tab: waits for Aslant's
/// picture and opens it as a new study, the way a study scanned off another
/// screen arrives. If nothing comes, [child] is simply the app as usual.
class AslantReceiver extends ConsumerStatefulWidget {
  const AslantReceiver({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AslantReceiver> createState() => _AslantReceiverState();
}

class _AslantReceiverState extends ConsumerState<AslantReceiver> {
  @override
  void initState() {
    super.initState();
    unawaited(_receive());
  }

  Future<void> _receive() async {
    final received = await receiveFromAslant();
    if (received == null || !mounted) return;
    final image = await decodeImage(received.imageBytes);
    if (!mounted) return;
    final session = ref.read(sessionProvider);
    session.startFreshStudy();
    session.loadImage(image, received.imageBytes);
    session.applyTransferredSettings(StudySettings.fromJson(received.settings));
    await ref.read(studiesProvider.notifier).keep(session);
    countEvent(AppEvent.aslantReceived);
    if (!mounted) return;
    unawaited(
      Navigator.of(
        context,
      ).push(NoTransitionRoute(builder: (_) => const StudyScreen())),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
