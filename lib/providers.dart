import 'package:chessground/chessground.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n/strings.dart';
import 'models/settings.dart';
import 'services/database_service.dart';
import 'services/engine_service.dart';
import 'services/sound_service.dart';

/// Overridden in main() with the loaded instance.
final prefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError());

final databaseProvider = Provider<DatabaseService>((ref) => DatabaseService());

final engineProvider = Provider<EngineService>((ref) {
  final e = EngineService();
  ref.onDispose(e.shutdown);
  return e;
});

final soundProvider = Provider<SoundService>((ref) {
  final s = SoundService();
  s.enabled = ref.watch(settingsProvider.select((v) => v.sound));
  ref.onDispose(s.dispose);
  return s;
});

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

final stringsProvider = Provider<AppStrings>((ref) {
  return AppStrings(ref.watch(settingsProvider.select((s) => s.languageFa)));
});

class SettingsNotifier extends Notifier<AppSettings> {
  SharedPreferences get _p => ref.read(prefsProvider);

  @override
  AppSettings build() {
    final p = ref.read(prefsProvider);
    const d = AppSettings();
    T pick<T extends Enum>(List<T> values, String key, T def) {
      final n = p.getString(key);
      return values.firstWhere((v) => v.name == n, orElse: () => def);
    }

    return AppSettings(
      languageFa: p.getBool('languageFa') ?? d.languageFa,
      themeMode: pick(ThemeMode.values, 'themeMode', d.themeMode),
      boardTheme: pick(BoardTheme.values, 'boardTheme', d.boardTheme),
      pieceSet: pick(PieceSet.values, 'pieceSet', d.pieceSet),
      sound: p.getBool('sound') ?? d.sound,
      coordinates: p.getBool('coordinates') ?? d.coordinates,
      showLegalMoves: p.getBool('showLegalMoves') ?? d.showLegalMoves,
      highlightLastMove: p.getBool('highlightLastMove') ?? d.highlightLastMove,
      evalBar: p.getBool('evalBar') ?? d.evalBar,
      blunderWarning: p.getBool('blunderWarning') ?? d.blunderWarning,
      hintLimit: pick(HintLimit.values, 'hintLimit', d.hintLimit),
      tips: p.getBool('tips') ?? d.tips,
    );
  }

  void update(AppSettings s) {
    state = s;
    _p
      ..setBool('languageFa', s.languageFa)
      ..setString('themeMode', s.themeMode.name)
      ..setString('boardTheme', s.boardTheme.name)
      ..setString('pieceSet', s.pieceSet.name)
      ..setBool('sound', s.sound)
      ..setBool('coordinates', s.coordinates)
      ..setBool('showLegalMoves', s.showLegalMoves)
      ..setBool('highlightLastMove', s.highlightLastMove)
      ..setBool('evalBar', s.evalBar)
      ..setBool('blunderWarning', s.blunderWarning)
      ..setString('hintLimit', s.hintLimit.name)
      ..setBool('tips', s.tips);
  }
}
