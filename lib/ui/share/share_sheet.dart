import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../data/purchase_service.dart';
import '../../engine/export.dart';
import '../../state/canvas_session.dart';
import '../../state/providers.dart';
import '../../theme.dart';
import '../widgets/controls.dart';
import '../widgets/glyphs.dart';
import 'image_output.dart';

/// A bottom sheet on phone, a 360px centred dialog on desktop. One action on
/// each surface: SHARE. There is no separate save.
Future<void> showShareSheet(BuildContext context, WidgetRef ref) {
  final wide = MediaQuery.sizeOf(context).width >= kDesktopBreakpoint;
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Share this study',
    barrierColor: const Color(0x99201E1D),
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
  bool _buying = false;

  CanvasSession get _session => ref.read(sessionProvider);

  bool get _unlocked => ref.watch(entitlementProvider).valueOrNull ?? false;

  void _report(String message) {
    if (mounted) setState(() => _status = message);
  }

  /// A tap on a locked control is intent to buy, not an error.
  Future<bool> _ensureUnlocked() async {
    if (_unlocked) return true;
    await _buy();
    return ref.read(entitlementProvider).valueOrNull ?? false;
  }

  Future<void> _buy() async {
    if (_buying) return;
    setState(() {
      _buying = true;
      _status = '';
    });
    final outcome = await ref.read(entitlementProvider.notifier).unlock();
    if (!mounted) return;
    setState(() {
      _buying = false;
      _status = switch (outcome) {
        PurchaseOutcome.success => 'Unlocked — thank you',
        PurchaseOutcome.cancelled => '',
        PurchaseOutcome.failed => 'Purchase did not complete',
      };
    });
  }

  Future<void> _restore() async {
    setState(() => _status = 'Restoring…');
    final outcome = await ref.read(entitlementProvider.notifier).restore();
    if (!mounted) return;
    _report(
      outcome == PurchaseOutcome.success
          ? 'Restored — thank you'
          : 'Nothing to restore',
    );
  }

  Future<void> _keep() async {
    if (!await _ensureUnlocked()) return;
    setState(() => _busy = true);
    try {
      await ref.read(studiesProvider.notifier).keep(_session);
      if (!mounted) return;
      if (widget.wide) {
        _report('Saved to the shelf');
      } else {
        Navigator.of(context)
          ..pop()
          ..maybePop();
      }
    } catch (e) {
      _report('Could not keep this study');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
    if (!await _ensureUnlocked()) return;
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
      exportFilename(_session.name, _size),
    );
    _report(result.message);
  });

  Future<void> _copy() => _withRender((png) async {
    final result = await copyImageToClipboard(
      png,
      exportFilename(_session.name, _size),
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
    final locked = !_unlocked;
    final optionOpacity = locked ? 0.4 : 1.0;

    return Container(
      color: AskanceColors.ink,
      foregroundDecoration: BoxDecoration(
        border: widget.wide
            ? Border.all(color: AskanceColors.accent, width: kRule)
            : const Border(
                top: BorderSide(color: AskanceColors.accent, width: kRule),
              ),
      ),
      padding: EdgeInsets.fromLTRB(
        18 * s,
        18 * s,
        18 * s,
        18 * s + (widget.wide ? 0 : MediaQuery.paddingOf(context).bottom),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Share this study',
                    style: AskanceText.sheetTitle().by(s),
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).pop(),
                  child: SizedBox(
                    width: 32 * s,
                    height: 32 * s,
                    child: Center(
                      child: Text(
                        '×',
                        style: AskanceText.button(
                          18,
                          color: AskanceColors.ground,
                        ).by(s),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 16 * s),

            if (locked) ...[
              _PaywallBlock(
                buying: _buying,
                onUnlock: _buy,
                onRestore: _restore,
              ),
              SizedBox(height: 16 * s),
            ],

            ActionButton(
              label: 'Keep on the shelf',
              trailingIcon: GlyphIcon(
                Glyph.star,
                size: 14 * s,
                color: AskanceColors.ground,
              ),
              onPressed: _busy ? null : _keep,
              opacity: optionOpacity,
            ),
            SizedBox(height: 18 * s),

            Text('SIZE', style: AskanceText.sectionLabel().by(s)),
            SizedBox(height: 10 * s),
            Opacity(
              opacity: optionOpacity,
              child: SegmentedControl<ExportSize>(
                values: ExportSize.values,
                selected: _size,
                labelOf: (v) => v.label,
                onChanged: (v) => setState(() => _size = v),
                fontSize: 10,
              ),
            ),
            SizedBox(height: 10 * s),
            Opacity(
              opacity: optionOpacity,
              child: Text(
                'Image size · ${_size.note} · exactly what you see',
                style: AskanceText.caption(
                  11,
                  color: AskanceColors.mutedDark,
                ).by(s),
              ),
            ),
            SizedBox(height: 14 * s),

            ActionButton(
              label: 'Save image',
              trailing: '↓',
              solid: false,
              onDark: true,
              onPressed: _busy ? null : _save,
              opacity: optionOpacity,
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
                    color: AskanceColors.ground,
                  ),
                  SizedBox(width: 3 * s),
                  Text(
                    'P',
                    style: AskanceText.button(
                      14,
                      color: AskanceColors.ground,
                    ).by(s),
                  ),
                ],
              ),
              solid: false,
              onDark: true,
              onPressed: _busy ? null : _print,
              opacity: optionOpacity,
            ),
            SizedBox(height: 8 * s),
            ActionButton(
              label: 'Copy to clipboard',
              trailingIcon: GlyphIcon(
                Glyph.copy,
                size: 14 * s,
                color: AskanceColors.ground,
              ),
              solid: false,
              onDark: true,
              onPressed: _busy ? null : _copy,
              opacity: optionOpacity,
            ),

            if (_status.isNotEmpty) ...[
              SizedBox(height: 14 * s),
              Text(
                _status.toUpperCase(),
                style: AskanceText.controlLabel(
                  10,
                  color: AskanceColors.accent,
                ).by(s),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The unlock lives inside the share sheet. There is no separate upsell screen
/// and nothing interrupts the user while working.
class _PaywallBlock extends StatelessWidget {
  const _PaywallBlock({
    required this.buying,
    required this.onUnlock,
    required this.onRestore,
  });

  final bool buying;
  final VoidCallback onUnlock;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final s = DesignScale.of(context);
    return Container(
      padding: EdgeInsets.all(14 * s),
      foregroundDecoration: const BoxDecoration(
        border: Border.fromBorderSide(
          BorderSide(color: AskanceColors.accent, width: kRule),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ONE PAYMENT · LIFETIME',
            style: AskanceText.sectionLabel(color: AskanceColors.accent).by(s),
          ),
          SizedBox(height: 10 * s),
          Text(
            'Keep and export your studies',
            style: AskanceText.button(17, color: AskanceColors.ground).by(s),
          ),
          SizedBox(height: 10 * s),
          Text(
            'Looking is free, always. $kPriceLabel unlocks the shelf and every '
            'way out of the app.',
            style: AskanceText.body(13, color: AskanceColors.mutedDark).by(s),
          ),
          SizedBox(height: 14 * s),
          ActionButton(
            label: buying ? 'Confirming…' : 'Unlock — $kPriceLabel',
            trailing: buying ? null : '→',
            onPressed: buying ? null : onUnlock,
          ),
          SizedBox(height: 10 * s),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onRestore,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 4 * s),
              child: Text(
                'RESTORE PURCHASE',
                style: AskanceText.controlLabel(
                  10,
                  color: AskanceColors.mutedDark,
                ).by(s),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
