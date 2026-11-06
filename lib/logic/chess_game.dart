import 'dart:math';

import 'package:dartchess/dartchess.dart';

import '../models/game_models.dart';

/// Pure game state: positions, moves, SAN, undo/redo cursor and every FIDE
/// end-of-game rule (checkmate, stalemate, insufficient material, threefold
/// repetition, fifty-move rule). Has no Flutter dependency so it is unit
/// testable.
class ChessGame {
  ChessGame({String? startFen}) : startFen = startFen ?? kInitialFEN {
    _positions.add(_parse(this.startFen));
  }

  /// Builds a game from a start FEN and a list of UCI moves.
  factory ChessGame.fromUci(String startFen, List<String> uciMoves) {
    final g = ChessGame(startFen: startFen);
    for (final u in uciMoves) {
      final m = Move.parse(u);
      if (m == null || !g.play(m)) break;
    }
    return g;
  }

  final String startFen;
  final List<Position> _positions = [];
  final List<Move> _moves = [];
  final List<String> _sans = [];

  /// Number of plies currently "on the board" (undo moves this back).
  int _cursor = 0;

  GameResult? _result;

  static Position _parse(String fen) => Chess.fromSetup(Setup.parseFen(fen));

  /// Validates a FEN; returns null when invalid.
  static Position? tryParseFen(String fen) {
    try {
      return _parse(fen.trim());
    } catch (_) {
      return null;
    }
  }

  Position get position => _positions[_cursor];
  Position get initialPosition => _positions.first;
  int get cursor => _cursor;
  int get length => _moves.length;
  List<Move> get moves => List.unmodifiable(_moves.take(_cursor));
  List<Move> get allMoves => List.unmodifiable(_moves);
  List<String> get sans => List.unmodifiable(_sans);
  Move? get lastMove => _cursor == 0 ? null : _moves[_cursor - 1];
  Position positionAt(int ply) => _positions[ply];
  Side get turn => position.turn;
  bool get canUndo => _cursor > 0;
  bool get canRedo => _cursor < _moves.length;
  GameResult? get result => _result;
  bool get isOver => _result != null;

  List<String> get uciMoves => _moves.take(_cursor).map((m) => m.uci).toList();

  /// Plays [move] at the current cursor, discarding any redo history.
  /// Returns false if the move is illegal or the game is over.
  bool play(Move move) {
    if (_result != null) return false;
    final pos = position;
    final normalized = move is NormalMove ? pos.normalizeMove(move) : move;
    if (!pos.isLegal(normalized)) return false;
    final (next, san) = pos.makeSan(normalized);
    if (_cursor < _moves.length) {
      _moves.removeRange(_cursor, _moves.length);
      _sans.removeRange(_cursor, _sans.length);
      _positions.removeRange(_cursor + 1, _positions.length);
    }
    _moves.add(normalized);
    _sans.add(san);
    _positions.add(next);
    _cursor++;
    _result = _computeResult();
    return true;
  }

  /// Plays a move given in UCI (e.g. `e2e4`, `e7e8q`, `e1g1`).
  bool playUci(String uci) {
    final m = Move.parse(uci);
    return m != null && play(m);
  }

  /// Plays a move given in SAN (e.g. `Nf3`).
  bool playSan(String san) {
    final m = position.parseSan(san);
    return m != null && play(m);
  }

  void undo() {
    if (!canUndo) return;
    _cursor--;
    _result = null;
  }

  void redo() {
    if (!canRedo) return;
    _cursor++;
    _result = _computeResult();
  }

  /// Jump to a given ply (for move list navigation).
  void goTo(int ply) {
    _cursor = ply.clamp(0, _moves.length);
    _result = _computeResult();
  }

  /// Ends the game with an external reason (resign, agreement, timeout).
  void finish(GameResult result) => _result = result;

  /// Clears an externally set result (used when undoing after resign etc.).
  void clearResult() => _result = _computeResult();

  /// Position key for repetition: placement, side, castling, en passant.
  static String repetitionKey(Position p) => p.fen.split(' ').take(4).join(' ');

  int get repetitionCount {
    final key = repetitionKey(position);
    var count = 0;
    for (var i = 0; i <= _cursor; i++) {
      if (repetitionKey(_positions[i]) == key) count++;
    }
    return count;
  }

  GameResult? _computeResult() {
    final p = position;
    if (p.isCheckmate) return GameResult(p.turn.opposite, EndReason.checkmate);
    if (p.isStalemate) return const GameResult(null, EndReason.stalemate);
    if (p.isInsufficientMaterial) return const GameResult(null, EndReason.insufficient);
    if (repetitionCount >= 3) return const GameResult(null, EndReason.threefold);
    if (p.halfmoves >= 100) return const GameResult(null, EndReason.fiftyMove);
    return null;
  }

  /// Result when [side]'s clock runs out: a draw if the opponent has no
  /// possible mating material, otherwise a loss.
  GameResult timeoutResult(Side side) {
    final opponent = side.opposite;
    if (position.hasInsufficientMaterial(opponent)) {
      return const GameResult(null, EndReason.timeoutDraw);
    }
    return GameResult(opponent, EndReason.timeout);
  }

  /// Exports the main line as PGN.
  String toPgn({Map<String, String> headers = const {}}) {
    final h = PgnGame.defaultHeaders();
    h.addAll(headers);
    if (startFen != kInitialFEN) {
      h['SetUp'] = '1';
      h['FEN'] = startFen;
      if (_isChess960Fen(startFen)) h['Variant'] = 'Chess960';
    }
    h['Result'] = _result?.pgnResult ?? '*';
    final root = PgnNode<PgnNodeData>();
    PgnNode<PgnNodeData> node = root;
    for (var i = 0; i < _cursor; i++) {
      final child = PgnChildNode(PgnNodeData(san: _sans[i]));
      node.children.add(child);
      node = child;
    }
    return PgnGame(headers: h, moves: root, comments: const []).makePgn();
  }

  static bool _isChess960Fen(String fen) => !fen.startsWith('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR');

  /// Parses a PGN (main line only). Returns null on failure.
  static ChessGame? fromPgn(String pgn) {
    try {
      final game = PgnGame.parsePgn(pgn);
      final fen = game.headers['FEN'] ?? kInitialFEN;
      final g = ChessGame(startFen: fen);
      var count = 0;
      for (final node in game.moves.mainline()) {
        if (!g.playSan(node.san)) break;
        count++;
      }
      if (count == 0 && game.headers['FEN'] == null) return null;
      return g;
    } catch (_) {
      return null;
    }
  }
}

/// Generates a random Chess960 start position (one of 960).
String chess960Fen([Random? random]) {
  final r = random ?? Random();
  final rank = List<String?>.filled(8, null);
  // Bishops on opposite colors.
  rank[r.nextInt(4) * 2] = 'b';
  rank[r.nextInt(4) * 2 + 1] = 'b';
  List<int> empty() => [for (var i = 0; i < 8; i++) if (rank[i] == null) i];
  var e = empty();
  rank[e[r.nextInt(e.length)]] = 'q';
  e = empty();
  rank[e[r.nextInt(e.length)]] = 'n';
  e = empty();
  rank[e[r.nextInt(e.length)]] = 'n';
  // Remaining three squares: rook, king, rook (king between rooks).
  e = empty();
  rank[e[0]] = 'r';
  rank[e[1]] = 'k';
  rank[e[2]] = 'r';
  final black = rank.join();
  final white = black.toUpperCase();
  return '$black/pppppppp/8/8/8/8/PPPPPPPP/$white w KQkq - 0 1';
}

/// Picks a uniformly random legal move (level 1 "bot").
Move? randomLegalMove(Position pos, [Random? random]) {
  final r = random ?? Random();
  final all = <Move>[];
  for (final entry in pos.legalMoves.entries) {
    for (final to in entry.value.squares) {
      final from = entry.key;
      final piece = pos.board.pieceAt(from);
      final isPromo = piece?.role == Role.pawn && (to.rank == Rank.first || to.rank == Rank.eighth);
      if (isPromo) {
        for (final role in [Role.queen, Role.rook, Role.bishop, Role.knight]) {
          all.add(NormalMove(from: from, to: to, promotion: role));
        }
      } else {
        all.add(NormalMove(from: from, to: to));
      }
    }
  }
  if (all.isEmpty) return null;
  return all[r.nextInt(all.length)];
}
