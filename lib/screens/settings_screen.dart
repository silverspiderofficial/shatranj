import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/settings.dart';
import '../providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final st = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    Widget header(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(t, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
    );
    return Scaffold(
      appBar: AppBar(title: Text(s.t('settings.title'))),
      body: ListView(
        children: [
          header(s.t('settings.language')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('فارسی')),
                ButtonSegment(value: false, label: Text('English')),
              ],
              selected: {st.languageFa},
              onSelectionChanged: (v) => n.update(st.copyWith(languageFa: v.first)),
            ),
          ),
          header(s.t('settings.theme')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<ThemeMode>(
              segments: [
                ButtonSegment(value: ThemeMode.system, label: Text(s.t('settings.themeSystem'))),
                ButtonSegment(value: ThemeMode.light, label: Text(s.t('settings.themeLight'))),
                ButtonSegment(value: ThemeMode.dark, label: Text(s.t('settings.themeDark'))),
              ],
              selected: {st.themeMode},
              onSelectionChanged: (v) => n.update(st.copyWith(themeMode: v.first)),
            ),
          ),
          header(s.t('settings.board')),
          SizedBox(
            height: 110,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final b in BoardTheme.values)
                  _Thumb(
                    selected: st.boardTheme == b,
                    label: s.t('settings.board.${b.name}'),
                    onTap: () => n.update(st.copyWith(boardTheme: b)),
                    child: StaticChessboard(
                      size: 72,
                      orientation: Side.white,
                      fen: kInitialBoardFEN,
                      settings: StaticChessboardSettings(colorScheme: b.scheme, pieceAssets: st.pieceSet.assets),
                    ),
                  ),
              ],
            ),
          ),
          header(s.t('settings.pieces')),
          SizedBox(
            height: 110,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final p in kPieceSets)
                  _Thumb(
                    selected: st.pieceSet == p,
                    label: p.label,
                    onTap: () => n.update(st.copyWith(pieceSet: p)),
                    child: Directionality(
                      textDirection: TextDirection.ltr,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image(image: p.assets[PieceKind.whiteKnight]!, width: 36, height: 36),
                          Image(image: p.assets[PieceKind.blackQueen]!, width: 36, height: 36),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(),
          SwitchListTile(title: Text(s.t('settings.sound')), value: st.sound, onChanged: (v) => n.update(st.copyWith(sound: v))),
          SwitchListTile(title: Text(s.t('settings.coords')), value: st.coordinates, onChanged: (v) => n.update(st.copyWith(coordinates: v))),
          SwitchListTile(title: Text(s.t('settings.legal')), value: st.showLegalMoves, onChanged: (v) => n.update(st.copyWith(showLegalMoves: v))),
          SwitchListTile(title: Text(s.t('settings.lastMove')), value: st.highlightLastMove, onChanged: (v) => n.update(st.copyWith(highlightLastMove: v))),
          SwitchListTile(title: Text(s.t('settings.evalBar')), value: st.evalBar, onChanged: (v) => n.update(st.copyWith(evalBar: v))),
          SwitchListTile(title: Text(s.t('settings.blunder')), value: st.blunderWarning, onChanged: (v) => n.update(st.copyWith(blunderWarning: v))),
          SwitchListTile(title: Text(s.t('settings.tips')), value: st.tips, onChanged: (v) => n.update(st.copyWith(tips: v))),
          header(s.t('settings.hints')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<HintLimit>(
              segments: [
                ButtonSegment(value: HintLimit.unlimited, label: Text(s.t('settings.hintsUnlimited'))),
                ButtonSegment(value: HintLimit.three, label: Text(s.t('settings.hintsThree'))),
                ButtonSegment(value: HintLimit.off, label: Text(s.t('settings.hintsOff'))),
              ],
              selected: {st.hintLimit},
              onSelectionChanged: (v) => n.update(st.copyWith(hintLimit: v.first)),
            ),
          ),
          const Divider(height: 32),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(s.t('settings.about')),
            subtitle: Text(s.t('settings.aboutText')),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.selected, required this.label, required this.onTap, required this.child});
  final bool selected;
  final String label;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            border: Border.all(color: selected ? scheme.primary : Colors.transparent, width: 3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [child, const SizedBox(height: 4), Text(label, style: const TextStyle(fontSize: 11))],
          ),
        ),
      ),
    );
  }
}

