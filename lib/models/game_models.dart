import 'package:dartchess/dartchess.dart';

/// Why a game ended.
enum EndReason {
  checkmate,
  stalemate,
  insufficient,
  threefold,
  fiftyMove,
  timeout,
  timeoutDraw,
  resign,
  agreement,
}

/// Final result of a game.
class GameResult {
  const GameResult(this.winner, this.reason);

  /// `null` means draw.
  final Side? winner;
  final EndReason reason;

  bool get isDraw => winner == null;

  String get pgnResult => winner == null ? '1/2-1/2' : (winner == Side.white ? '1-0' : '0-1');

  static GameResult? fromStorage(String? result, String? reason) {
    if (result == null || reason == null) return null;
    final r = EndReason.values.firstWhere((e) => e.name == reason, orElse: () => EndReason.agreement);
    final Side? w = switch (result) {
      '1-0' => Side.white,
      '0-1' => Side.black,
      _ => null,
    };
    return GameResult(w, r);
  }
}

enum GameMode { ai, twoPlayer }

/// How the board is displayed in two-player mode.
enum BoardRotation { none, auto, faceToFace }

/// Time control: base minutes + increment seconds. `null` base = no clock.
class TimeControl {
  const TimeControl(this.baseSeconds, this.incrementSeconds);

  final int baseSeconds;
  final int incrementSeconds;

  static const none = TimeControl(0, 0);
  bool get isNone => baseSeconds <= 0;

  static const presets = <TimeControl>[
    TimeControl(60, 0),
    TimeControl(180, 2),
    TimeControl(300, 0),
    TimeControl(600, 0),
    TimeControl(900, 10),
    none,
  ];

  String get label => isNone ? '-' : '${baseSeconds ~/ 60}+$incrementSeconds';

  String encode() => '$baseSeconds+$incrementSeconds';

  static TimeControl decode(String? s) {
    if (s == null || !s.contains('+')) return none;
    final p = s.split('+');
    return TimeControl(int.tryParse(p[0]) ?? 0, int.tryParse(p[1]) ?? 0);
  }

  @override
  bool operator ==(Object other) =>
      other is TimeControl && other.baseSeconds == baseSeconds && other.incrementSeconds == incrementSeconds;

  @override
  int get hashCode => Object.hash(baseSeconds, incrementSeconds);
}

/// Configuration a game is started with.
class GameConfig {
  const GameConfig({
    required this.mode,
    this.level = 3,
    this.humanSide = Side.white,
    this.timeControl = TimeControl.none,
    this.chess960 = false,
    this.rotation = BoardRotation.none,
    this.startFen,
  });

  final GameMode mode;

  /// 1..10, only for [GameMode.ai].
  final int level;

  /// Side the human plays in [GameMode.ai].
  final Side humanSide;
  final TimeControl timeControl;
  final bool chess960;
  final BoardRotation rotation;

  /// Custom start position (Chess960 or imported FEN).
  final String? startFen;

  GameConfig copyWith({String? startFen}) => GameConfig(
    mode: mode,
    level: level,
    humanSide: humanSide,
    timeControl: timeControl,
    chess960: chess960,
    rotation: rotation,
    startFen: startFen ?? this.startFen,
  );
}

/// A stored game (DB row).
class GameRecord {
  GameRecord({
    this.id,
    required this.config,
    required this.startFen,
    required this.movesUci,
    required this.createdAt,
    this.result,
    this.whiteMs,
    this.blackMs,
    this.hintsUsed = 0,
  });

  int? id;
  final GameConfig config;
  final String startFen;
  final List<String> movesUci;
  final DateTime createdAt;
  final GameResult? result;
  final int? whiteMs;
  final int? blackMs;
  final int hintsUsed;

  bool get finished => result != null;

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'mode': config.mode.name,
    'level': config.level,
    'human_side': config.humanSide.name,
    'time_control': config.timeControl.encode(),
    'chess960': config.chess960 ? 1 : 0,
    'rotation': config.rotation.name,
    'start_fen': startFen,
    'moves': movesUci.join(' '),
    'created_at': createdAt.millisecondsSinceEpoch,
    'result': result?.pgnResult,
    'reason': result?.reason.name,
    'white_ms': whiteMs,
    'black_ms': blackMs,
    'hints_used': hintsUsed,
  };

  static GameRecord fromMap(Map<String, Object?> m) {
    final moves = (m['moves'] as String? ?? '').trim();
    final startFen = m['start_fen'] as String;
    return GameRecord(
      id: m['id'] as int?,
      config: GameConfig(
        mode: GameMode.values.firstWhere((e) => e.name == m['mode'], orElse: () => GameMode.ai),
        level: m['level'] as int? ?? 3,
        humanSide: (m['human_side'] as String?) == 'black' ? Side.black : Side.white,
        timeControl: TimeControl.decode(m['time_control'] as String?),
        chess960: (m['chess960'] as int? ?? 0) == 1,
        rotation: BoardRotation.values.firstWhere(
          (e) => e.name == m['rotation'],
          orElse: () => BoardRotation.none,
        ),
        startFen: startFen,
      ),
      startFen: startFen,
      movesUci: moves.isEmpty ? [] : moves.split(' '),
      createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int? ?? 0),
      result: GameResult.fromStorage(m['result'] as String?, m['reason'] as String?),
      whiteMs: m['white_ms'] as int?,
      blackMs: m['black_ms'] as int?,
      hintsUsed: m['hints_used'] as int? ?? 0,
    );
  }
}

/// Engine strength settings for a level.
class LevelSpec {
  const LevelSpec({required this.level, this.elo, this.skill, required this.moveTimeMs, this.depth});

  final int level;
  final int? elo;
  final int? skill;
  final int moveTimeMs;
  final int? depth;

  bool get isRandom => level == 1;

  /// Level 1: random legal moves. Levels 2..10: Stockfish limited by UCI_Elo
  /// (1350 → 2800) with growing think time; the lowest levels also cap
  /// Skill Level and depth so they play like real beginners.
  static LevelSpec of(int level) => switch (level) {
    1 => const LevelSpec(level: 1, moveTimeMs: 0),
    2 => const LevelSpec(level: 2, elo: 1350, skill: 0, moveTimeMs: 150, depth: 2),
    3 => const LevelSpec(level: 3, elo: 1500, skill: 3, moveTimeMs: 250, depth: 4),
    4 => const LevelSpec(level: 4, elo: 1650, skill: 6, moveTimeMs: 300),
    5 => const LevelSpec(level: 5, elo: 1800, skill: 9, moveTimeMs: 400),
    6 => const LevelSpec(level: 6, elo: 2000, skill: 12, moveTimeMs: 500),
    7 => const LevelSpec(level: 7, elo: 2200, skill: 15, moveTimeMs: 700),
    8 => const LevelSpec(level: 8, elo: 2400, skill: 17, moveTimeMs: 900),
    9 => const LevelSpec(level: 9, elo: 2600, skill: 19, moveTimeMs: 1200),
    _ => const LevelSpec(level: 10, elo: 2800, skill: 20, moveTimeMs: 1500),
  };
}
