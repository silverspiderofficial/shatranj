import 'dart:async';
import 'dart:math';

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../logic/chess_game.dart';
import '../logic/hint_explainer.dart';
import '../models/game_models.dart';
import '../models/settings.dart';
import '../services/database_service.dart';
import '../services/engine_service.dart';
import '../services/sound_service.dart';

/// A pending blunder warning shown to the player.
class BlunderWarning {
  const BlunderWarning({required this.mate, required this.dropCp});
  final bool mate;
  final int dropCp;
}

/// Drives one game (vs computer or two players): moves, engine replies,
/// clocks, hints, blunder warnings, autosave.
class GameController extends ChangeNotifier {
  GameController({
    required this.config,
    required this.engine,
    required this.db,
    required this.sound,
    required this._settings,
    required this._strings,
    GameRecord? resume,
  }) {
    if (resume != null) {
      game = ChessGame.fromUci(resume.startFen, resume.movesUci);
      _record = resume;
      whiteMs = resume.whiteMs ?? config.timeControl.baseSeconds * 1000;
      blackMs = resume.blackMs ?? config.timeControl.baseSeconds * 1000;
      hintsUsed = resume.hintsUsed;
    } else {
      game = ChessGame(startFen: config.startFen);
      whiteMs = config.timeControl.baseSeconds * 1000;
      blackMs = config.timeControl.baseSeconds * 1000;
    }
    board = ChessboardController(game: _gameData());
    if (isAi) engine.acquire();
    _startClock();
    _afterPositionChange(initial: true);
  }

  final GameConfig config;
  final EngineService engine;
  final DatabaseService db;
  final SoundService sound;
  AppSettings _settings;
  AppStrings _strings;

  late ChessGame game;
  late final ChessboardController board;
  GameRecord? _record;

  int whiteMs = 0;
  int blackMs = 0;
  Timer? _timer;
  DateTime? _lastTick;

  bool thinking = false;
  int hintsUsed = 0;
  Arrow? hintArrow;
  String? hintText;
  String? tipText;
  BlunderWarning? blunder;
  bool flipped = false;

  /// Evaluation in centipawns from White's point of view (for the eval bar).
  int? evalWhiteCp;

  int _generation = 0;
  final Map<String, EngineResult> _evalCache = {};
  bool _disposed = false;
  final _random = Random();

  bool get isAi => config.mode == GameMode.ai;
  bool get hasClock => !config.timeControl.isNone;
  Side get humanSide => config.humanSide;
  Position get position => game.position;
  GameResult? get result => game.result;
  bool get isHumanTurn => !isAi || position.turn == humanSide;

  int get hintsLeft {
    final limit = _settings.hintLimit.count;
    if (limit < 0) return 1 << 20;
    return max(0, limit - hintsUsed);
  }

  bool get hintsEnabled => isAi && _settings.hintLimit != HintLimit.off && EngineService.isSupported;

  void updateSettings(AppSettings s, AppStrings strings) {
    final evalTurnedOn = !_settings.evalBar && s.evalBar;
    _settings = s;
    _strings = strings;
    if (evalTurnedOn) _backgroundAnalysis();
    _notify();
  }

  // ---------------------------------------------------------------- board

  Side get orientation {
    Side base;
    if (isAi) {
      base = humanSide;
    } else {
      base = config.rotation == BoardRotation.auto ? position.turn : Side.white;
    }
    return flipped ? base.opposite : base;
  }

  PieceOrientationBehavior get pieceOrientation => (!isAi && config.rotation == BoardRotation.faceToFace)
      ? PieceOrientationBehavior.opponentUpsideDown
      : PieceOrientationBehavior.facingUser;

  PlayerSide get _playerSide {
    if (game.isOver || thinking || blunder != null) return PlayerSide.none;
    if (!isAi) return PlayerSide.both;
    if (position.turn != humanSide) return PlayerSide.none;
    return humanSide == Side.white ? PlayerSide.white : PlayerSide.black;
  }

  GameData _gameData() {
    final p = position;
    return GameData(
      fen: p.fen,
      lastMove: game.lastMove,
      playerSide: _playerSide,
      sideToMove: p.turn,
      kingSquareInCheck: p.isCheck ? p.board.kingOf(p.turn) : null,
      validMoves: makeLegalMoves(p),
    );
  }

  void _refreshBoard({bool animate = true}) {
    board.updatePosition(_gameData(), animate: animate);
  }

  // ---------------------------------------------------------------- moves

  /// Called by the board when the user plays a move.
  Future<void> onUserMove(Move move, {bool? viaDragAndDrop}) async {
    if (!isHumanTurn || game.isOver || thinking) return;
    final fenBefore = position.fen;
    final played = _applyMove(move, triggerEngine: false);
    if (!played) return;
    if (isAi && !game.isOver) {
      if (_settings.blunderWarning && EngineService.isSupported) {
        final gen = _generation;
        thinking = true;
        _refreshBoard(animate: false);
        _notify();
        final warning = await _checkBlunder(fenBefore, position.fen);
        if (_disposed || gen != _generation) return;
        thinking = false;
        if (warning != null) {
          blunder = warning;
          _refreshBoard(animate: false);
          _notify();
          return; // wait for the player's decision
        }
      }
      _engineMove();
    }
  }

  bool _applyMove(Move move, {bool triggerEngine = true}) {
    final before = position;
    final isCapture = move is NormalMove &&
        (before.board.pieceAt(move.to) != null && before.board.pieceAt(move.to)!.color != before.turn ||
            (before.board.pieceAt(move.from)?.role == Role.pawn && move.from.file != move.to.file));
    final mover = before.turn;
    if (!game.play(move)) return false;
    _generation++;
    hintArrow = null;
    hintText = null;
    if (hasClock && game.length > 0) {
      if (mover == Side.white) {
        whiteMs += config.timeControl.incrementSeconds * 1000;
      } else {
        blackMs += config.timeControl.incrementSeconds * 1000;
      }
    }
    if (game.isOver) {
      sound.play(SoundKind.end);
    } else if (position.isCheck) {
      sound.play(SoundKind.check);
    } else {
      sound.play(isCapture ? SoundKind.capture : SoundKind.move);
    }
    _refreshBoard();
    _afterPositionChange(triggerEngine: triggerEngine);
    return true;
  }

  void _afterPositionChange({bool initial = false, bool triggerEngine = true}) {
    if (game.isOver) {
      _timer?.cancel();
    }
    _save();
    if (isAi && !game.isOver) {
      if (position.turn != humanSide) {
        if (triggerEngine) _engineMove();
      } else {
        _backgroundAnalysis();
      }
    }
    _notify();
  }

  Future<void> _engineMove() async {
    if (game.isOver || position.turn == humanSide || !isAi) return;
    final gen = _generation;
    thinking = true;
    _refreshBoard(animate: false);
    _notify();
    final spec = LevelSpec.of(config.level);
    Move? move;
    if (spec.isRandom || !EngineService.isSupported) {
      await Future<void>.delayed(Duration(milliseconds: 350 + _random.nextInt(400)));
      move = randomLegalMove(position, _random);
    } else {
      final res = await engine.search(
        position.fen,
        SearchOptions(
          moveTimeMs: spec.moveTimeMs,
          depth: spec.depth,
          elo: spec.elo,
          skill: spec.skill,
          chess960: config.chess960,
        ),
      );
      if (res.bestMove != null) move = Move.parse(res.bestMove!);
      move ??= randomLegalMove(position, _random);
    }
    if (_disposed || gen != _generation) return;
    thinking = false;
    if (move != null) {
      _applyMove(move);
    } else {
      _refreshBoard(animate: false);
      _notify();
    }
  }

  Future<EngineResult> _evaluate(String fen) async {
    final cached = _evalCache[fen];
    if (cached != null) return cached;
    final r = await engine.search(fen, SearchOptions(moveTimeMs: 350, chess960: config.chess960));
    if (r.bestMove != null || r.scoreCp != null || r.mateIn != null) _evalCache[fen] = r;
    return r;
  }

  /// Analyses the position while the human thinks: feeds the eval bar,
  /// hints and the blunder check.
  Future<void> _backgroundAnalysis() async {
    if (!isAi || !EngineService.isSupported || game.isOver) return;
    final needed = _settings.evalBar || _settings.blunderWarning || hintsEnabled;
    if (!needed) return;
    final gen = _generation;
    final fen = position.fen;
    final turn = position.turn;
    final r = await _evaluate(fen);
    if (_disposed || gen != _generation) return;
    evalWhiteCp = turn == Side.white ? r.cp : -r.cp;
    _notify();
  }

  Future<BlunderWarning?> _checkBlunder(String fenBefore, String fenAfter) async {
    final before = await _evaluate(fenBefore);
    final after = await _evaluate(fenAfter);
    final beforeCp = before.cp; // player's view
    final afterCp = -after.cp; // engine result is from opponent's view
    final drop = beforeCp - afterCp;
    final mateAgainst = after.mateIn != null && after.mateIn! > 0;
    if (beforeCp > 600 && afterCp > 400 && !mateAgainst) return null; // still winning comfortably
    if (mateAgainst && !(before.mateIn != null && before.mateIn! < 0)) {
      return BlunderWarning(mate: true, dropCp: drop);
    }
    if (drop >= 200) return BlunderWarning(mate: false, dropCp: drop);
    return null;
  }

  /// Player chose to take back the blunder.
  void takeBackBlunder() {
    blunder = null;
    game.undo();
    _generation++;
    _refreshBoard();
    _afterPositionChange();
  }

  /// Player keeps the move; the engine replies.
  void keepBlunder() {
    blunder = null;
    _refreshBoard(animate: false);
    _notify();
    _engineMove();
  }

  // ---------------------------------------------------------------- hints

  Future<void> requestHint() async {
    if (!hintsEnabled || !isHumanTurn || game.isOver || thinking) return;
    if (hintsLeft <= 0) return;
    final gen = _generation;
    thinking = true;
    _refreshBoard(animate: false);
    _notify();
    final pos = position;
    final r = await _evaluate(pos.fen);
    if (_disposed || gen != _generation) return;
    thinking = false;
    final best = r.bestMove == null ? null : Move.parse(r.bestMove!);
    if (best is NormalMove) {
      final normalized = pos.normalizeMove(best) as NormalMove;
      // Draw castling arrows to the king's destination square.
      var dest = best.to;
      final piece = pos.board.pieceAt(best.from);
      if (piece?.role == Role.king && pos.board.pieceAt(best.to)?.color == piece?.color) {
        dest = Square.fromCoords(best.to.file > best.from.file ? File.g : File.c, best.from.rank);
      }
      hintArrow = Arrow(color: const Color(0xCC15781B), orig: best.from, dest: dest);
      hintText = explainMove(_strings, pos, normalized);
      hintsUsed++;
      _save();
    }
    _refreshBoard(animate: false);
    _notify();
  }

  void showTip(List<(String, String)> tips) {
    if (tips.isEmpty) return;
    final t = tips[_random.nextInt(tips.length)];
    tipText = _strings.isFa ? t.$1 : t.$2;
    _notify();
  }

  void clearTip() {
    tipText = null;
    _notify();
  }

  // ---------------------------------------------------------------- undo / redo

  void undo() {
    if (!game.canUndo) return;
    engine.stop();
    blunder = null;
    thinking = false;
    game.undo();
    if (isAi) {
      while (game.canUndo && position.turn != humanSide) {
        game.undo();
      }
    }
    _generation++;
    hintArrow = null;
    hintText = null;
    _startClock();
    _refreshBoard();
    _save();
    if (isAi && position.turn != humanSide) {
      _engineMove(); // human plays black and undid to the start
    } else {
      _backgroundAnalysis();
    }
    _notify();
  }

  void redo() {
    if (!game.canRedo || thinking) return;
    game.redo();
    if (isAi) {
      while (game.canRedo && position.turn != humanSide) {
        game.redo();
      }
    }
    _generation++;
    _refreshBoard();
    _afterPositionChange();
  }

  bool get canUndo => game.canUndo && !thinking;
  bool get canRedo => game.canRedo && !thinking;

  void flip() {
    flipped = !flipped;
    _notify();
  }

  // ---------------------------------------------------------------- draw / resign

  void resign() {
    if (game.isOver) return;
    final loser = isAi ? humanSide : position.turn;
    _finish(GameResult(loser.opposite, EndReason.resign));
  }

  /// Draw offer to the computer: accepted when the engine is not better.
  Future<bool> offerDrawToComputer() async {
    if (!isAi || game.isOver) return false;
    if (game.length < 20) return false;
    if (!EngineService.isSupported || LevelSpec.of(config.level).isRandom) {
      final accept = _random.nextBool();
      if (accept) _finish(const GameResult(null, EndReason.agreement));
      return accept;
    }
    final r = await _evaluate(position.fen);
    final engineSide = humanSide.opposite;
    final cpForEngine = position.turn == engineSide ? r.cp : -r.cp;
    final accept = cpForEngine <= 30;
    if (accept) _finish(const GameResult(null, EndReason.agreement));
    return accept;
  }

  void agreeDraw() => _finish(const GameResult(null, EndReason.agreement));

  void _finish(GameResult r) {
    engine.stop();
    thinking = false;
    blunder = null;
    game.finish(r);
    _generation++;
    _timer?.cancel();
    sound.play(SoundKind.end);
    _refreshBoard(animate: false);
    _save();
    _notify();
  }

  // ---------------------------------------------------------------- clock

  void _startClock() {
    _timer?.cancel();
    if (!hasClock || game.isOver) return;
    _lastTick = DateTime.now();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
  }

  void _tick() {
    final now = DateTime.now();
    final elapsed = now.difference(_lastTick ?? now).inMilliseconds;
    _lastTick = now;
    if (game.isOver || blunder != null) return;
    // The clock starts with White's first move.
    if (game.length == 0 && game.cursor == 0) return;
    if (position.turn == Side.white) {
      whiteMs -= elapsed;
    } else {
      blackMs -= elapsed;
    }
    if (whiteMs <= 0 || blackMs <= 0) {
      final side = whiteMs <= 0 ? Side.white : Side.black;
      if (side == Side.white) whiteMs = 0;
      if (side == Side.black) blackMs = 0;
      _finish(game.timeoutResult(side));
      return;
    }
    _notify();
  }

  /// Pauses the clock (app in background) and resumes it.
  void pauseClock() => _timer?.cancel();
  void resumeClock() => _startClock();

  // ---------------------------------------------------------------- persistence

  Future<void> _save() async {
    if (game.length == 0 && _record == null) return;
    final rec = GameRecord(
      id: _record?.id,
      config: config,
      startFen: game.startFen,
      movesUci: game.uciMoves,
      createdAt: _record?.createdAt ?? DateTime.now(),
      result: game.result,
      whiteMs: hasClock ? whiteMs : null,
      blackMs: hasClock ? blackMs : null,
      hintsUsed: hintsUsed,
    );
    _record = rec;
    try {
      await db.save(rec);
    } catch (_) {}
  }

  int? get recordId => _record?.id;

  String pgn() {
    final white = isAi ? (humanSide == Side.white ? _strings.t('you') : 'Stockfish L${config.level}') : 'White';
    final black = isAi ? (humanSide == Side.black ? _strings.t('you') : 'Stockfish L${config.level}') : 'Black';
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return game.toPgn(
      headers: {
        'Event': 'Offline Chess',
        'Site': 'Shatranj app',
        'Date': '${now.year}.${two(now.month)}.${two(now.day)}',
        'White': white,
        'Black': black,
      },
    );
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _save();
    board.dispose();
    if (isAi) {
      engine.stop();
      engine.release();
    }
    super.dispose();
  }
}
