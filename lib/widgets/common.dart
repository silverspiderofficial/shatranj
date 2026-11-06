import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/strings.dart';

/// Keeps the chessboard left-to-right (a-file on the left from White's view)
/// even inside the right-to-left Persian UI.
class LtrBoard extends StatelessWidget {
  const LtrBoard({super.key, required this.builder});

  final Widget Function(BuildContext context, double size) builder;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: LayoutBuilder(
        builder: (context, c) {
          final size = c.maxWidth < c.maxHeight ? c.maxWidth : c.maxHeight;
          return Center(child: SizedBox(width: size, height: size, child: builder(context, size)));
        },
      ),
    );
  }
}

/// Vertical evaluation bar. [whiteCp] is from White's point of view.
class EvalBar extends StatelessWidget {
  const EvalBar({super.key, required this.whiteCp, required this.whiteAtBottom, required this.strings});

  final int? whiteCp;
  final bool whiteAtBottom;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final cp = (whiteCp ?? 0).clamp(-1000, 1000);
    // Logistic mapping to a 0..1 "white share".
    final share = 1 / (1 + _exp(-cp / 250));
    final label = whiteCp == null
        ? ''
        : (whiteCp!.abs() >= 9000 ? '#' : (whiteCp! / 100).abs().toStringAsFixed(1));
    return Directionality(
      textDirection: TextDirection.ltr,
      child: LayoutBuilder(
        builder: (context, c) {
          final whiteH = c.maxHeight * share;
          return ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Stack(
              children: [
                Container(color: const Color(0xFF333333)),
                Align(
                  alignment: whiteAtBottom ? Alignment.bottomCenter : Alignment.topCenter,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    height: whiteH,
                    color: const Color(0xFFEEEEEE),
                  ),
                ),
                Align(
                  alignment: (cp >= 0) == whiteAtBottom ? Alignment.bottomCenter : Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      label,
                      style: TextStyle(fontSize: 9, color: cp >= 0 ? Colors.black87 : Colors.white70),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  static double _exp(double x) => math.exp(x);
}

/// A chess clock face.
class ClockFace extends StatelessWidget {
  const ClockFace({super.key, required this.ms, required this.active, required this.strings, this.label});

  final int ms;
  final bool active;
  final AppStrings strings;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = ms < 0 ? 0 : ms;
    final m = total ~/ 60000;
    final s = (total % 60000) ~/ 1000;
    final tenths = (total % 1000) ~/ 100;
    final text = total < 10000
        ? '$m:${s.toString().padLeft(2, '0')}.$tenths'
        : '$m:${s.toString().padLeft(2, '0')}';
    final low = total < 20000;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: active ? (low ? Colors.red.shade700 : scheme.primary) : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        strings.n(text),
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          fontFeatures: const [FontFeature.tabularFigures()],
          color: active ? Colors.white : scheme.onSurface,
        ),
      ),
    );
  }
}

/// Horizontal scrollable SAN move list with tap-to-navigate.
class MoveList extends StatefulWidget {
  const MoveList({super.key, required this.sans, required this.cursor, required this.onTap, required this.strings, this.marks = const {}, this.startPly = 0});

  final List<String> sans;
  final int cursor;
  final void Function(int ply) onTap;
  final AppStrings strings;

  /// Optional annotation per ply index (0-based move index): '??', '?', '?!'.
  final Map<int, String> marks;

  /// Ply number of the starting position (1 if Black moves first).
  final int startPly;

  @override
  State<MoveList> createState() => _MoveListState();
}

class _MoveListState extends State<MoveList> {
  final _controller = ScrollController();

  @override
  void didUpdateWidget(covariant MoveList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cursor != widget.cursor || oldWidget.sans.length != widget.sans.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_controller.hasClients) {
          _controller.animateTo(
            _controller.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _markColor(String m) => switch (m) {
    '??' => Colors.red,
    '?' => Colors.orange,
    _ => Colors.amber.shade700,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = <Widget>[];
    for (var i = 0; i < widget.sans.length; i++) {
      final ply = widget.startPly + i;
      if (ply.isEven || i == 0) {
        final number = ply ~/ 2 + 1;
        items.add(
          Padding(
            padding: const EdgeInsets.only(left: 6, right: 2),
            child: Text(
              '${widget.strings.n(number)}.${ply.isOdd ? '..' : ''}',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
        );
      }
      final selected = i + 1 == widget.cursor;
      final mark = widget.marks[i];
      items.add(
        InkWell(
          onTap: () => widget.onTap(i + 1),
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: selected ? scheme.primaryContainer : null,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: widget.sans[i], style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (mark != null)
                    TextSpan(text: mark, style: TextStyle(color: _markColor(mark), fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        height: 36,
        child: ListView(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          children: items.isEmpty ? [const SizedBox()] : items,
        ),
      ),
    );
  }
}

Future<bool> confirmDialog(BuildContext context, String text, AppStrings s) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      content: Text(text),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(s.t('common.no'))),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(s.t('common.yes'))),
      ],
    ),
  );
  return r ?? false;
}

/// Bottom sheet that shows PGN and FEN with copy and share buttons.
Future<void> showExportSheet(BuildContext context, AppStrings s, {required String pgn, required String fen}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ExportBlock(title: 'PGN', text: pgn, s: s),
              const SizedBox(height: 12),
              _ExportBlock(title: 'FEN', text: fen, s: s),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ExportBlock extends StatelessWidget {
  const _ExportBlock({required this.title, required this.text, required this.s});
  final String title;
  final String text;
  final AppStrings s;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Directionality(
              textDirection: TextDirection.ltr,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 160),
                child: SingleChildScrollView(child: SelectableText(text, style: const TextStyle(fontFamily: 'monospace', fontSize: 12))),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.copy),
                  label: Text(s.t('common.copy')),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: text));
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('common.copied'))));
                  },
                ),
                TextButton.icon(
                  icon: const Icon(Icons.share),
                  label: Text(s.t('common.share')),
                  onPressed: () => SharePlus.instance.share(ShareParams(text: text)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
