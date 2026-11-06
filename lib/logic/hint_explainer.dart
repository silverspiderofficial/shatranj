import 'package:dartchess/dartchess.dart';

import '../l10n/strings.dart';

/// Material values in centipawns.
int pieceValue(Role r) => switch (r) {
  Role.pawn => 100,
  Role.knight => 320,
  Role.bishop => 330,
  Role.rook => 500,
  Role.queen => 900,
  Role.king => 0,
};

String pieceName(AppStrings s, Role r) => s.t('piece.${r.name}');

/// Produces a short human explanation for a recommended [move] in [pos].
///
/// Heuristics, in priority order: mate, promotion, castling, fork, capture,
/// escaping a threat, check, development, center control, generic.
String explainMove(AppStrings s, Position pos, Move move) {
  if (move is! NormalMove) return '';
  final piece = pos.board.pieceAt(move.from);
  if (piece == null) return '';
  final after = pos.play(move);
  final name = pieceName(s, piece.role);
  final san = pos.makeSan(move).$2;

  if (after.isCheckmate) return s.t('hint.mate');
  if (move.promotion != null) return s.t('hint.promote');

  final target = pos.board.pieceAt(move.to);
  final isCastle = piece.role == Role.king && (target?.color == piece.color || (move.from.file - move.to.file).abs() > 1);
  if (isCastle) return s.t('hint.castle');

  // Fork: the moved piece attacks two or more valuable enemy pieces (or king + piece).
  final dest = move.to;
  final movedPiece = after.board.pieceAt(dest) ?? piece;
  final attacked = attacks(movedPiece, dest, after.board.occupied) & after.board.bySide(piece.color.opposite);
  var valuable = 0;
  for (final sq in attacked.squares) {
    final p = after.board.pieceAt(sq);
    if (p == null) continue;
    if (p.role == Role.king || pieceValue(p.role) > pieceValue(movedPiece.role) || !_isDefended(after, sq)) {
      if (p.role != Role.pawn) valuable++;
    }
  }
  if (valuable >= 2) return s.f('hint.fork', [name]);

  if (target != null && target.color != piece.color) {
    return s.f('hint.capture', [name, pieceName(s, target.role)]);
  }
  final isEp = piece.role == Role.pawn && move.from.file != move.to.file && target == null;
  if (isEp) return s.f('hint.capture', [name, pieceName(s, Role.pawn)]);

  // Escaping a threat: the piece was attacked and undefended / attacked by a cheaper piece.
  final attackers = pos.board.attacksTo(move.from, piece.color.opposite);
  if (attackers.isNotEmpty && piece.role != Role.pawn) {
    final cheapest = attackers.squares
        .map((sq) => pieceValue(pos.board.pieceAt(sq)!.role))
        .fold<int>(100000, (a, b) => a < b ? a : b);
    if (cheapest < pieceValue(piece.role) || !_isDefended(pos, move.from)) {
      return s.f('hint.threat', [name]);
    }
  }

  if (after.isCheck) return s.f('hint.check', [name]);

  if (pos.fullmoves <= 12) {
    final backRank = piece.color == Side.white ? Rank.first : Rank.eighth;
    if ((piece.role == Role.knight || piece.role == Role.bishop) && move.from.rank == backRank) {
      return s.f('hint.develop', [name]);
    }
    if (piece.role == Role.pawn && (move.to.file == File.d || move.to.file == File.e)) {
      return s.t('hint.center');
    }
  }
  return s.t('hint.generic').replaceAll('{0}', san).replaceAll('{1}', name);
}

bool _isDefended(Position pos, Square sq) {
  final p = pos.board.pieceAt(sq);
  if (p == null) return false;
  return pos.board.attacksTo(sq, p.color, occupied: pos.board.occupied).isNotEmpty;
}

/// Game phase for learning tips.
enum GamePhase { opening, middlegame, endgame }

GamePhase phaseOf(Position pos) {
  final b = pos.board;
  final nonPawn = (b.queens | b.rooks | b.bishops | b.knights).size;
  if (pos.fullmoves <= 10 && nonPawn >= 12) return GamePhase.opening;
  if (nonPawn <= 6 || (b.queens.isEmpty && nonPawn <= 8)) return GamePhase.endgame;
  return GamePhase.middlegame;
}
