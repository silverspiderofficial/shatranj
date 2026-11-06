import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/strings.dart';
import '../models/game_models.dart';
import '../providers.dart';
import 'analysis_screen.dart';
import 'game_screen.dart';

final gamesProvider = FutureProvider.autoDispose<List<GameRecord>>((ref) => ref.read(databaseProvider).allGames());

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  String _date(AppStrings s, DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return s.n('${d.year}/${two(d.month)}/${two(d.day)} ${two(d.hour)}:${two(d.minute)}');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final games = ref.watch(gamesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('history.title'))),
      body: games.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) {
          if (list.isEmpty) return Center(child: Text(s.t('history.empty')));
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final g = list[i];
              final title = g.config.mode == GameMode.ai ? s.f('history.vsAi', [g.config.level]) : s.t('history.twoPlayer');
              final r = g.result;
              final resultStr = r == null
                  ? s.t('history.ongoing')
                  : resultLine(s, r, humanSide: g.config.mode == GameMode.ai ? g.config.humanSide : null);
              IconData icon = Icons.hourglass_bottom;
              Color? color;
              if (r != null) {
                if (r.isDraw) {
                  icon = Icons.drag_handle;
                  color = Colors.grey;
                } else if (g.config.mode == GameMode.ai) {
                  final won = r.winner == g.config.humanSide;
                  icon = won ? Icons.emoji_events : Icons.close;
                  color = won ? Colors.amber.shade700 : Colors.red;
                } else {
                  icon = Icons.flag;
                  color = r.winner == Side.white ? Colors.blueGrey : Colors.black87;
                }
              }
              final moves = (g.movesUci.length + 1) ~/ 2;
              return ListTile(
                leading: Icon(icon, color: color),
                title: Text('$title${g.config.chess960 ? ' · 960' : ''}'),
                subtitle: Text('$resultStr\n${_date(s, g.createdAt)} · ${s.f('history.moves', [moves])}'),
                isThreeLine: true,
                onTap: () {
                  if (r == null) {
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => GameScreen(config: g.config, resume: g))).then((_) => ref.invalidate(gamesProvider));
                  } else {
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => AnalysisScreen(startFen: g.startFen, uciMoves: g.movesUci)));
                  }
                },
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: s.t('common.delete'),
                  onPressed: () async {
                    await ref.read(databaseProvider).delete(g.id!);
                    ref.invalidate(gamesProvider);
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final games = ref.watch(gamesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('stats.title'))),
      body: games.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) {
          final w = List.filled(11, 0), l = List.filled(11, 0), d = List.filled(11, 0);
          for (final g in list) {
            final r = g.result;
            if (g.config.mode != GameMode.ai || r == null) continue;
            final lv = g.config.level.clamp(1, 10);
            if (r.isDraw) {
              d[lv]++;
            } else if (r.winner == g.config.humanSide) {
              w[lv]++;
            } else {
              l[lv]++;
            }
          }
          int sum(List<int> x) => x.fold(0, (a, b) => a + b);
          final rows = <DataRow>[
            for (var lv = 1; lv <= 10; lv++)
              DataRow(cells: [
                DataCell(Text(s.n(lv))),
                DataCell(Text(s.n(w[lv]), style: const TextStyle(color: Colors.green))),
                DataCell(Text(s.n(l[lv]), style: const TextStyle(color: Colors.red))),
                DataCell(Text(s.n(d[lv]))),
              ]),
            DataRow(cells: [
              DataCell(Text(s.t('stats.total'), style: const TextStyle(fontWeight: FontWeight.bold))),
              DataCell(Text(s.n(sum(w)), style: const TextStyle(fontWeight: FontWeight.bold))),
              DataCell(Text(s.n(sum(l)), style: const TextStyle(fontWeight: FontWeight.bold))),
              DataCell(Text(s.n(sum(d)), style: const TextStyle(fontWeight: FontWeight.bold))),
            ]),
          ];
          return SingleChildScrollView(
            child: Center(
              child: DataTable(
                columns: [
                  DataColumn(label: Text(s.t('stats.level'))),
                  DataColumn(label: Text(s.t('stats.win'))),
                  DataColumn(label: Text(s.t('stats.loss'))),
                  DataColumn(label: Text(s.t('stats.draw'))),
                ],
                rows: rows,
              ),
            ),
          );
        },
      ),
    );
  }
}
