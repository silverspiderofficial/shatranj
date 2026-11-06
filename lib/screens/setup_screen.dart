import 'dart:math';

import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/strings.dart';
import '../logic/chess_game.dart';
import '../models/game_models.dart';
import '../providers.dart';
import 'game_screen.dart';

enum ColorChoice { white, black, random }

/// New-game options for both "vs computer" and "two players".
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key, required this.mode});

  final GameMode mode;

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  int level = 3;
  ColorChoice color = ColorChoice.white;
  TimeControl time = TimeControl.none;
  bool custom = false;
  int customMinutes = 10;
  int customIncrement = 5;
  bool chess960 = false;
  BoardRotation rotation = BoardRotation.none;

  bool get isAi => widget.mode == GameMode.ai;

  @override
  void initState() {
    super.initState();
    final p = ref.read(prefsProvider);
    level = p.getInt('lastLevel') ?? 3;
  }

  String _levelLabel(AppStrings s, int l) {
    if (l == 1) return s.t('level.1');
    return s.f('level.n', [l, LevelSpec.of(l).elo ?? 0]);
  }

  Future<void> _start() async {
    final side = switch (color) {
      ColorChoice.white => Side.white,
      ColorChoice.black => Side.black,
      ColorChoice.random => Random().nextBool() ? Side.white : Side.black,
    };
    final tc = custom ? TimeControl(customMinutes * 60, customIncrement) : time;
    ref.read(prefsProvider).setInt('lastLevel', level);
    // Starting a new game abandons any unfinished one.
    await ref.read(databaseProvider).discardUnfinished();
    final config = GameConfig(
      mode: widget.mode,
      level: level,
      humanSide: side,
      timeControl: tc,
      chess960: chess960,
      rotation: rotation,
      startFen: chess960 ? chess960Fen() : kInitialFEN,
    );
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => GameScreen(config: config)));
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(isAi ? s.t('setup.title') : s.t('home.twoPlayer'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (isAi) ...[
            Text(s.t('setup.level'), style: Theme.of(context).textTheme.titleMedium),
            Slider(
              value: level.toDouble(),
              min: 1,
              max: 10,
              divisions: 9,
              label: s.n(level),
              onChanged: (v) => setState(() => level = v.round()),
            ),
            Text(_levelLabel(s, level), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            Text(s.t('setup.color'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<ColorChoice>(
              segments: [
                ButtonSegment(value: ColorChoice.white, label: Text(s.t('setup.white'))),
                ButtonSegment(value: ColorChoice.black, label: Text(s.t('setup.black'))),
                ButtonSegment(value: ColorChoice.random, label: Text(s.t('setup.random'))),
              ],
              selected: {color},
              onSelectionChanged: (v) => setState(() => color = v.first),
            ),
          ] else ...[
            Text(s.t('setup.rotation'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<BoardRotation>(
              segments: [
                ButtonSegment(value: BoardRotation.none, label: Text(s.t('setup.rotNone'))),
                ButtonSegment(value: BoardRotation.auto, label: Text(s.t('setup.rotAuto'))),
                ButtonSegment(value: BoardRotation.faceToFace, label: Text(s.t('setup.rotFace'))),
              ],
              selected: {rotation},
              onSelectionChanged: (v) => setState(() => rotation = v.first),
            ),
          ],
          const SizedBox(height: 16),
          Text(s.t('setup.time'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tc in TimeControl.presets)
                ChoiceChip(
                  label: Text(tc.isNone ? s.t('setup.noTime') : s.n(tc.label)),
                  selected: !custom && time == tc,
                  onSelected: (_) => setState(() {
                    custom = false;
                    time = tc;
                  }),
                ),
              ChoiceChip(
                label: Text(s.t('setup.custom')),
                selected: custom,
                onSelected: (_) => setState(() => custom = true),
              ),
            ],
          ),
          if (custom) ...[
            const SizedBox(height: 8),
            Text('${s.t('setup.minutes')}: ${s.n(customMinutes)}'),
            Slider(
              value: customMinutes.toDouble(),
              min: 1,
              max: 90,
              divisions: 89,
              onChanged: (v) => setState(() => customMinutes = v.round()),
            ),
            Text('${s.t('setup.increment')}: ${s.n(customIncrement)}'),
            Slider(
              value: customIncrement.toDouble(),
              min: 0,
              max: 60,
              divisions: 60,
              onChanged: (v) => setState(() => customIncrement = v.round()),
            ),
          ],
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(s.t('setup.chess960')),
            value: chess960,
            onChanged: (v) => setState(() => chess960 = v),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _start,
            icon: const Icon(Icons.play_arrow),
            label: Padding(padding: const EdgeInsets.all(12), child: Text(s.t('common.start'), style: const TextStyle(fontSize: 18))),
          ),
        ],
      ),
    );
  }
}
