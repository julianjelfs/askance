import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../engine/crop.dart';
import '../../engine/export.dart';
import '../../state/canvas_session.dart';
import '../../state/providers.dart';
import '../../theme.dart';
import '../layout.dart';
import '../widgets/controls.dart';
import '../widgets/glyphs.dart';
import 'image_output.dart';
import 'qr_share_dialog.dart';

/// A bottom sheet on phone, a 360px centred dialog on desktop. One action on
/// each surface: SHARE. The study is already on the shelf — everything a
/// study needs to survive happens the moment it is opened — so this is purely
/// about the ways out: an image file, a print, the clipboard, another device.
Future<void> showShareSheet(BuildContext context, WidgetRef ref) {
  final wide = isWideLayout(context);
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Share this study',
    barrierColor: const Color(0x991C1B1A),
    transitionDuration: AskanceMotion.sheetSlide,
    pageBuilder: (context, _, _) => const SizedBox.shrink(),
    transitionBuilder: (context, animation, _, _) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: AskanceMotion.slide,
      );
      final sheet = ShareSheet(wide: wide);
      if (wide) {
        return Center(
          child: FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween(begin: 0.98, end: 1.0).animate(curved),
              child: SizedBox(width: 360, child: sheet),
            ),
          ),
        );
      }
      return Align(
        alignment: Alignment.bottomCenter,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(curved),
          child: sheet,
        ),
      );
    },
  );
}

class ShareSheet extends ConsumerStatefulWidget {
  const ShareSheet({super.key, required this.wide});

  final bool wide;

  @override
  ConsumerState<ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends ConsumerState<ShareSheet> {
  ExportSize _size = ExportSize.screen;
  String _status = '';
  bool _busy = false;
  bool _showingQr = false;

  CanvasSession get _session => ref.read(sessionProvider);

  /// The shape the export takes: the study's crop of its photograph.
  Size get _pictureSize {
    final image = _session.image;
    if (image == null) return Size.zero;
    return croppedSize(
      Size(image.width.toDouble(), image.height.toDouble()),
      _session.settings.crop,
    );
  }

  void _report(String message) {
    if (mounted) setState(() => _status = message);
  }

  Future<Uint8List?> _render() async {
    final shader = ref.read(shaderProvider).valueOrNull;
    final session = _session;
    if (shader == null || session.image == null) return null;
    return renderExport(
      shader: shader,
      source: session.image!,
      settings: session.settings,
      view: session.view,
      target: _size,
      splitPosition: session.splitPosition,
    );
  }

  Future<void> _withRender(Future<void> Function(Uint8List png) action) async {
    setState(() {
      _busy = true;
      _status = 'Rendering…';
    });
    try {
      final png = await _render();
      if (png == null) {
        _report('Could not render');
        return;
      }
      await action(png);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() => _withRender((png) async {
    final result = await saveImageBytes(
      png,
      exportFilename(_session.name, _size.frameFor(_pictureSize)),
    );
    _report(result.message);
  });

  Future<void> _copy() => _withRender((png) async {
    final result = await copyImageToClipboard(
      png,
      exportFilename(_session.name, _size.frameFor(_pictureSize)),
    );
    _report(result.message);
  });

  Future<void> _print() => _withRender((png) async {
    _report('');
    final doc = pw.Document();
    final image = pw.MemoryImage(png);
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (context) =>
            pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
      ),
    );
    await Printing.layoutPdf(onLayout: (_) => doc.save());
  });

  @override
  Widget build(BuildContext context) {
    final s = DesignScale.of(context);

    return Container(
      decoration: BoxDecoration(
        color: AskanceColors.gesso,
        borderRadius: widget.wide
            ? BorderRadius.circular(AskanceRadius.sheet)
            : BorderRadius.vertical(
                top: Radius.circular(AskanceRadius.sheet * s),
              ),
      ),
      padding: EdgeInsets.fromLTRB(
        18 * s,
        20 * s,
        18 * s,
        18 * s + (widget.wide ? 0 : MediaQuery.paddingOf(context).bottom),
      ),
      child: SingleChildScrollView(
        child: _showingQr
            ? QrSharePanel(
                session: _session,
                onBack: () => setState(() => _showingQr = false),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Share this study',
                          style: AskanceText.heading(22).by(s),
                        ),
                      ),
                      Semantics(
                        button: true,
                        label: 'Close',
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => Navigator.of(context).pop(),
                          child: SizedBox(
                            width: 40 * s,
                            height: 40 * s,
                            child: Center(
                              child: GlyphIcon(
                                Glyph.close,
                                size: 22 * s,
                                color: AskanceColors.graphite,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16 * s),

                  Text('Size', style: AskanceText.label(14.5).by(s)),
                  SizedBox(height: 8 * s),
                  SegmentedControl<ExportSize>(
                    values: ExportSize.values,
                    selected: _size,
                    labelOf: (v) => v.label,
                    onChanged: (v) => setState(() => _size = v),
                  ),
                  SizedBox(height: 8 * s),
                  Text(
                    '${_size.noteFor(_pictureSize)} · exactly what you see',
                    style: AskanceText.caption(12.5).by(s),
                  ),
                  SizedBox(height: 14 * s),

                  ActionButton(
                    label: 'Save image',
                    trailing: '↓',
                    solid: false,
                    onPressed: _busy ? null : _save,
                  ),
                  SizedBox(height: 8 * s),
                  ActionButton(
                    label: 'Print',
                    trailingIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GlyphIcon(
                          Glyph.command,
                          size: 13 * s,
                          color: AskanceColors.graphite,
                        ),
                        SizedBox(width: 3 * s),
                        Text(
                          'P',
                          style: AskanceText.button(
                            14,
                            color: AskanceColors.graphite,
                          ).by(s),
                        ),
                      ],
                    ),
                    solid: false,
                    onPressed: _busy ? null : _print,
                  ),
                  SizedBox(height: 8 * s),
                  ActionButton(
                    label: 'Copy to clipboard',
                    trailingIcon: GlyphIcon(
                      Glyph.copy,
                      size: 14 * s,
                      color: AskanceColors.graphite,
                    ),
                    solid: false,
                    onPressed: _busy ? null : _copy,
                  ),
                  SizedBox(height: 8 * s),
                  ActionButton(
                    label: 'Share with QR code',
                    solid: false,
                    onPressed: _busy
                        ? null
                        : () => setState(() => _showingQr = true),
                  ),

                  if (_status.isNotEmpty) ...[
                    SizedBox(height: 14 * s),
                    Text(
                      _status,
                      style: AskanceText.label(
                        14,
                        color: AskanceColors.accentInk,
                      ).by(s),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
