import 'dart:math';

import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shatranj/l10n/strings.dart';
import 'package:shatranj/logic/chess_game.dart';
import 'package:shatranj/logic/hint_explainer.dart';
import 'package:shatranj/models/game_models.dart';

void main() {
  group('basic moves', () {
    test('initial position has 20 legal moves', () {
      final g = ChessGame();
      var count = 0;
      for (final s in g.position.legalMoves.values) {
        count += s.size;
      }
      expect(count, 20);
    });

    test('illegal move is rejected', () {
      final g = ChessGame();
      expect(g.playUci('e2e5'), isFalse);
      expect(g.length, 0);
    });

    test('SAN is recorded', () {
      final g = ChessGame();
      g.playUci('e2e4');
      g.playUci('e7e5');
      g.playUci('g1f3');
      expect(g.sans, ['e4', 'e5', 'Nf3']);
    });
  });

  group('end of game rules', () {
    test("fool's mate is checkmate, black wins", () {
      final g = ChessGame();
      for (final m in ['f2f3', 'e7e5', 'g2g4', 'd8h4']) {
        expect(g.playUci(m), isTrue);
      }
      expect(g.result?.reason, EndReason.checkmate);
      expect(g.result?.winner, Side.black);
    });

    test('stalemate', () {
      final g = ChessGame(startFen: 'k7/8/1K6/8/8/8/8/2Q5 w - - 0 1');
      expect(g.playUci('c1c7'), isTrue);
      expect(g.result?.reason, EndReason.stalemate);
      expect(g.result?.isDraw, isTrue);
    });

    test('insufficient material after capture', () {
      final g = ChessGame(startFen: '8/8/4k3/8/8/3nK3/8/8 w - - 0 1');
      expect(g.playUci('e3d3'), isTrue);
      expect(g.result?.reason, EndReason.insufficient);
    });

    test('threefold repetition', () {
      final g = ChessGame();
      for (var i = 0; i < 2; i++) {
        for (final m in ['g1f3', 'g8f6', 'f3g1', 'f6g8']) {
          expect(g.playUci(m), isTrue);
        }
      }
      expect(g.result?.reason, EndReason.threefold);
    });

    test('fifty-move rule', () {
      final g = ChessGame(startFen: '4k3/8/8/8/8/8/R7/4K3 w - - 99 80');
      expect(g.playUci('a2a3'), isTrue);
      expect(g.result?.reason, EndReason.fiftyMove);
    });

    test('timeout draw when opponent cannot mate', () {
      final g = ChessGame(startFen: '4k3/8/8/8/8/8/8/R3K3 b - - 0 1');
      expect(g.timeoutResult(Side.white).winner, isNull); // black has only a king
      expect(g.timeoutResult(Side.black).winner, Side.white);
    });
  });

  group('special moves', () {
    test('kingside and queenside castling', () {
      final g = ChessGame(startFen: 'r3k2r/pppppppp/8/8/8/8/PPPPPPPP/R3K2R w KQkq - 0 1');
      expect(g.playUci('e1g1'), isTrue);
      expect(g.sans.last, 'O-O');
      expect(g.playUci('e8c8'), isTrue);
      expect(g.sans.last, 'O-O-O');
    });

    test('cannot castle through check', () {
      final g = ChessGame(startFen: 'r3k2r/8/8/8/8/5r2/8/R3K2R w KQkq - 0 1');
      expect(g.playUci('e1g1'), isFalse);
      expect(g.playUci('e1c1'), isTrue);
    });

    test('cannot castle out of check', () {
      final g = ChessGame(startFen: 'r3k2r/8/8/8/4r3/8/8/R3K2R w KQkq - 0 1');
      expect(g.playUci('e1g1'), isFalse);
      expect(g.playUci('e1c1'), isFalse);
    });

    test('en passant', () {
      final g = ChessGame(startFen: '4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1');
      expect(g.playUci('e5d6'), isTrue);
      expect(g.sans.last, 'exd6');
      expect(g.position.board.pieceAt(Square.d5), isNull);
    });

    test('promotion to knight', () {
      final g = ChessGame(startFen: '7k/3P4/8/8/8/8/8/K7 w - - 0 1');
      expect(g.playUci('d7d8n'), isTrue);
      expect(g.position.board.pieceAt(Square.d8)?.role, Role.knight);
    });
  });

  group('undo / redo / pgn', () {
    test('undo and redo', () {
      final g = ChessGame();
      g.playUci('e2e4');
      g.playUci('e7e5');
      g.undo();
      expect(g.cursor, 1);
      expect(g.canRedo, isTrue);
      g.redo();
      expect(g.cursor, 2);
      g.undo();
      g.playUci('c7c5');
      expect(g.sans, ['e4', 'c5']);
      expect(g.canRedo, isFalse);
    });

    test('PGN round trip', () {
      final g = ChessGame();
      for (final m in ['e2e4', 'e7e5', 'g1f3', 'b8c6', 'f1b5']) {
        g.playUci(m);
      }
      final pgn = g.toPgn();
      final back = ChessGame.fromPgn(pgn)!;
      expect(back.sans, g.sans);
      expect(back.position.fen, g.position.fen);
    });

    test('FEN validation', () {
      expect(ChessGame.tryParseFen(kInitialFEN), isNotNull);
      expect(ChessGame.tryParseFen('not a fen'), isNull);
    });
  });

  group('chess960 and bots', () {
    test('chess960 positions are valid', () {
      final r = Random(1);
      for (var i = 0; i < 200; i++) {
        final fen = chess960Fen(r);
        final back = fen.split('/').first;
        final b1 = back.indexOf('b'), b2 = back.lastIndexOf('b');
        expect(b1 % 2 != b2 % 2, isTrue, reason: fen);
        final k = back.indexOf('k');
        expect(back.indexOf('r') < k && back.lastIndexOf('r') > k, isTrue, reason: fen);
        expect(ChessGame.tryParseFen(fen), isNotNull, reason: fen);
      }
    });

    test('random bot always plays legal moves', () {
      final r = Random(2);
      final g = ChessGame();
      for (var i = 0; i < 300 && !g.isOver; i++) {
        final m = randomLegalMove(g.position, r);
        expect(m, isNotNull);
        expect(g.play(m!), isTrue);
      }
    });

    test('level specs', () {
      expect(LevelSpec.of(1).isRandom, isTrue);
      expect(LevelSpec.of(2).elo, 1350);
      expect(LevelSpec.of(10).elo, 2800);
    });
  });

  group('hints', () {
    test('knight fork is explained', () {
      // White knight jumps to c7 forking king e8 and rook a8.
      final pos = Chess.fromSetup(Setup.parseFen('r3k3/8/8/1N6/8/8/8/4K3 w - - 0 1'));
      final text = explainMove(const AppStrings(true), pos, NormalMove(from: Square.b5, to: Square.c7));
      expect(text, contains('چنگال'));
    });

    test('mate is explained', () {
      final pos = Chess.fromSetup(Setup.parseFen('6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1'));
      final text = explainMove(const AppStrings(false), pos, NormalMove(from: Square.a1, to: Square.a8));
      expect(text, contains('checkmates'));
    });

    test('persian digits', () {
      expect(AppStrings.toPersianDigits('1+0 e4'), '۱+۰ e۴');
    });
  });
}
