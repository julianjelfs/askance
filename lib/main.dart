// TEMPORARY: shader capability gate. Replaced by the real app once the web
// path is confirmed. See README "Verify the shader path early on PWA".
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'engine/engine.dart';
import 'engine/value_scale.dart';

void main() => runApp(const GateApp());

class GateApp extends StatefulWidget {
  const GateApp({super.key});
  @override
  State<GateApp> createState() => _GateAppState();
}

class _GateAppState extends State<GateApp> {
  String _status = 'loading…';
  ValueShader? _shader;
  ui.Image? _image;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final log = StringBuffer();
    try {
      _shader = await ValueShader.load();
      log.writeln('FragmentProgram.fromAsset OK');
    } catch (e) {
      log.writeln('FragmentProgram FAILED: $e');
      setState(() => _status = log.toString());
      return;
    }
    try {
      final data = await rootBundle.load('assets/dev/ref-portrait.jpg');
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      _image = (await codec.getNextFrame()).image;
      log.writeln('image ${_image!.width}x${_image!.height} OK');
    } catch (e) {
      log.writeln('image decode FAILED: $e');
    }
    try {
      final blurred = BlurredSource.render(
        source: _image!,
        outputPx: const Size(64, 64),
        detail: 0.5,
        view: const ViewTransform(),
      );
      log.writeln('toImageSync OK (${blurred.image.width}x${blurred.image.height})');
      blurred.dispose();
    } catch (e) {
      log.writeln('toImageSync FAILED: $e');
    }
    debugPrint('[askance-gate] $log');
    setState(() => _status = log.toString());
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        color: const Color(0xFF201E1D),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_shader != null && _image != null)
              CustomPaint(painter: _GatePainter(_shader!, _image!)),
            Positioned(
              left: 12,
              bottom: 12,
              child: Text(
                _status,
                style: const TextStyle(
                  fontFamily: 'Archivo',
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                  height: 1.5,
                  color: Color(0xFFEC3013),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GatePainter extends CustomPainter {
  _GatePainter(this.shader, this.image);
  final ValueShader shader;
  final ui.Image image;

  // Held across frames. Disposing either of these inside paint() destroys them
  // before the recorded picture is rasterised, which on web renders as a solid
  // fill of nothing.
  BlurredSource? _blurred;
  ui.FragmentShader? _fragment;

  @override
  void paint(Canvas canvas, Size size) {
    final dpr = WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
    final devicePx = Size(size.width * dpr, size.height * dpr);
    final key = BlurredSource.keyFor(
      outputPx: devicePx,
      detail: 0.5,
      view: const ViewTransform(),
    );
    if (_blurred == null || !_blurred!.matches(key)) {
      _blurred = BlurredSource.render(
        source: image,
        outputPx: devicePx,
        detail: 0.5,
        view: const ViewTransform(),
      );
      _fragment = shader.build(
        logicalSize: size,
        devicePx: devicePx,
        steps: 3,
        scale: ValueScale.graphite,
        skeleton: false,
      )..setImageSampler(0, _blurred!.image);
    }
    canvas.drawRect(Offset.zero & size, Paint()..shader = _fragment!);
  }

  @override
  bool shouldRepaint(covariant _GatePainter old) => false;
}
