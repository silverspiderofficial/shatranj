import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/game_models.dart';
import '../providers.dart';
import 'analysis_screen.dart';
import 'game_screen.dart';
import 'history_screen.dart';
import 'learn_screen.dart';
import 'puzzle_screen.dart';
import 'settings_screen.dart';
import 'setup_screen.dart';

final unfinishedProvider = FutureProvider.autoDispose<GameRecord?>((ref) => ref.read(databaseProvider).latestUnfinished());

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final unfinished = ref.watch(unfinishedProvider).value;
    final scheme = Theme.of(context).colorScheme;

    Future<void> open(Widget w) async {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
      ref.invalidate(unfinishedProvider);
    }

    Widget tile(IconData icon, String label, Widget target, {bool primary = false}) {
      return Card(
        color: primary ? scheme.primaryContainer : null,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => open(target),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 40, color: scheme.primary),
                const SizedBox(height: 8),
                Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('app.title')),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            const Center(child: Text('♞', style: TextStyle(fontSize: 72))),
            if (unfinished != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FilledButton.icon(
                  icon: const Icon(Icons.play_circle_outline),
                  label: Padding(padding: const EdgeInsets.all(10), child: Text(s.t('home.continue'))),
                  onPressed: () => open(GameScreen(config: unfinished.config, resume: unfinished)),
                ),
              ),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.3,
              children: [
                tile(Icons.computer, s.t('home.ai'), const SetupScreen(mode: GameMode.ai), primary: true),
                tile(Icons.people, s.t('home.twoPlayer'), const SetupScreen(mode: GameMode.twoPlayer), primary: true),
                tile(Icons.extension, s.t('home.puzzles'), const PuzzleScreen()),
                tile(Icons.analytics, s.t('home.analysis'), const AnalysisScreen()),
                tile(Icons.history, s.t('home.history'), const HistoryScreen()),
                tile(Icons.settings, s.t('home.settings'), const SettingsScreen()),
                tile(Icons.school, s.t('home.learn'), const LearnScreen()),
                tile(Icons.bar_chart, s.t('home.stats'), const StatsScreen()),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
