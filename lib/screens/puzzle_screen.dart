import 'dart:math';

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/strings.dart';
import '../services/sound_service.dart';
import '../providers.dart';
import '../widgets/common.dart';

/// One tactic from the bundled offline set (lichess puzzle DB, CC0).
class Puzzle {
  const Puzzle({required this.id, required this.fen, required this.moves, required this.rating, required this.themes});
  final String id;
  final String fen;
  final List<String> moves;
  final int rating;
  final String themes;

  static Puzzle? parse(String line) {
    final p = line.split(',');
    if (p.length < 4) return null;
    return Puzzle(
      id: p[0],
      fen: p[1],
      moves: p[2].split(' '),
      rating: int.tryParse(p[3]) ?? 1500,
      themes: p.length > 4 ? p[4] : '',
    );
  }
}

final puzzlesProvider = FutureProvider<List<Puzzle>>((ref) async {
  final raw = await rootBundle.loadString('assets/puzzles/puzzles.csv');
  return raw.split('\n').where((l) => l.trim().isNotEmpty).map(Puzzle.parse).whereType<Puzzle>().toList();
});

enum PuzzleBand { all, easy, medium, hard }

class PuzzleScreen extends ConsumerStatefulWidget {
  const PuzzleScreen({super.key});

  @override
  ConsumerState<PuzzleScreen> createState() => _PuzzleScreenState();
}

class _PuzzleScreenState extends ConsumerState<PuzzleScreen> {
  ChessboardController? board;
  Puzzle? puzzle;
  late Position pos;
  int step = 0;
  Move? lastMove;
  Side userSide = Side.white;
  String? message;
  Color? messageColor;
  bool solved = false;
  bool failedOnce = false;
  bool busy = false;
  Arrow? hintArrow;
  PuzzleBand band = PuzzleBand.all;
  final _random = Random();

  int get rating => ref.read(prefsProvider).getInt('puzzleRating') ?? 1200;
  Set<String> get solvedIds => (ref.read(prefsProvider).getStringList('puzzlesSolved') ?? const []).toSet();

  @override
  void dispose() {
    board?.dispose();
    super.dispose();
  }

  bool _inBand(Puzzle p) => switch (band) {
    PuzzleBand.all => true,
    PuzzleBand.easy => p.rating < 1300,
    PuzzleBand.medium => p.rating >= 1300 && p.rating < 1900,
    PuzzleBand.hard => p.rating >= 1900,
  };

  void _next(List<Puzzle> all) {
    final done = solvedIds;
    var pool = all.where((p) => _inBand(p) && !done.contains(p.id)).toList();
    if (pool.isEmpty) pool = all.where(_inBand).toList();
    if (pool.isEmpty) return;
    if (band == PuzzleBand.all) {
      // Prefer puzzles near the player's rating.
      final near = pool.where((p) => (p.rating - rating).abs() < 300).toList();
      if (near.isNotEmpty) pool = near;
    }
    _load(pool[_random.nextInt(pool.length)]);
  }

  void _load(Puzzle p) {
    puzzle = p;
    pos = Chess.fromSetup(Setup.parseFen(p.fen));
    step = 0;
    lastMove = null;
    solved = false;
    failedOnce = false;
    message = null;
    hintArrow = null;
    userSide = pos.turn.opposite;
    board ??= ChessboardController(game: _data());
    board!.updatePosition(_data(), animate: false, resetPremove: true);
    setState(() {});
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted && puzzle == p) _playScripted();
    });
  }

  GameData _data() => GameData(
    fen: pos.fen,
    lastMove: lastMove,
    playerSide: (solved || busy || pos.turn != userSide) ? PlayerSide.none : (userSide == Side.white ? PlayerSide.white : PlayerSide.black),
    sideToMove: pos.turn,
    kingSquareInCheck: pos.isCheck ? pos.board.kingOf(pos.turn) : null,
    validMoves: makeLegalMoves(pos),
  );

  void _apply(Move m) {
    final normalized = m is NormalMove ? pos.normalizeMove(m) : m;
    final capture = m is NormalMove && pos.board.pieceAt(m.to) != null;
    pos = pos.play(normalized);
    lastMove = normalized;
    final sound = ref.read(soundProvider);
    if (pos.isCheck) {
      sound.play(SoundKind.check);
    } else {
      sound.play(capture ? SoundKind.capture : SoundKind.move);
    }
  }

  void _playScripted() {
    final p = puzzle!;
    if (step >= p.moves.length) return;
    final m = Move.parse(p.moves[step]);
    if (m == null) return;
    _apply(m);
    step++;
    busy = false;
    board!.updatePosition(_data());
    setState(() {});
  }

  bool _sameMove(Move a, Move b) {
    if (a is! NormalMove || b is! NormalMove) return a.uci == b.uci;
    final na = pos.normalizeMove(a) as NormalMove;
    final nb = pos.normalizeMove(b) as NormalMove;
    return na.from == nb.from && na.to == nb.to && na.promotion == nb.promotion;
  }

  void _onMove(Move m, {bool? viaDragAndDrop}) {
    final s = ref.read(stringsProvider);
    final p = puzzle!;
    if (solved || step >= p.moves.length) return;
    final expected = Move.parse(p.moves[step])!;
    final normalized = m is NormalMove ? pos.normalizeMove(m) : m;
    final matesAnyway = pos.isLegal(normalized) && pos.play(normalized).isCheckmate;
    hintArrow = null;
    if (_sameMove(m, expected) || matesAnyway) {
      _apply(m);
      step++;
      if (step >= p.moves.length || matesAnyway) {
        _solved(s);
      } else {
        message = s.t('puzzle.correct');
        messageColor = Colors.green;
        busy = true;
        board!.updatePosition(_data());
        setState(() {});
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted && puzzle == p) _playScripted();
        });
      }
    } else {
      if (!failedOnce) {
        failedOnce = true;
        _updateRating(p.rating, 0);
      }
      message = s.t('puzzle.wrong');
      messageColor = Colors.red;
      board!.updatePosition(_data(), animate: false); // snap the piece back
      setState(() {});
    }
  }

  void _solved(AppStrings s) {
    solved = true;
    message = s.t('puzzle.solved');
    messageColor = Colors.green;
    if (!failedOnce) _updateRating(puzzle!.rating, 1);
    final prefs = ref.read(prefsProvider);
    final set = solvedIds..add(puzzle!.id);
    prefs.setStringList('puzzlesSolved', set.toList());
    ref.read(soundProvider).play(SoundKind.end);
    board!.updatePosition(_data());
    setState(() {});
  }

  void _updateRating(int puzzleRating, double score) {
    final r = rating;
    final expected = 1 / (1 + pow(10, (puzzleRating - r) / 400));
    final next = (r + 32 * (score - expected)).round().clamp(400, 3000);
    ref.read(prefsProvider).setInt('puzzleRating', next);
  }

  void _showSolution() {
    final p = puzzle!;
    if (step >= p.moves.length) return;
    final m = Move.parse(p.moves[step]);
    if (m is NormalMove) {
      if (!failedOnce) {
        failedOnce = true;
        _updateRating(p.rating, 0);
      }
      setState(() => hintArrow = Arrow(color: const Color(0xCC15781B), orig: m.from, dest: m.to));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final settings = ref.watch(settingsProvider);
    final puzzles = ref.watch(puzzlesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('puzzle.title'))),
      body: puzzles.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (all) {
          if (puzzle == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && puzzle == null) _next(all);
            });
            return const Center(child: CircularProgressIndicator());
          }
          final p = puzzle!;
          final sideName = userSide == Side.white ? s.t('setup.white') : s.t('setup.black');
          return SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: SegmentedButton<PuzzleBand>(
                    segments: [
                      for (final b in PuzzleBand.values) ButtonSegment(value: b, label: Text(s.t('puzzle.band.${b.name}'))),
                    ],
                    selected: {band},
                    onSelectionChanged: (v) {
                      setState(() => band = v.first);
                      _next(all);
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(s.f('puzzle.rating', [p.rating])),
                      Text(s.f('puzzle.yourRating', [rating])),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: LtrBoard(
                      builder: (context, size) => Chessboard(
                        size: size,
                        controller: board!,
                        orientation: userSide,
                        settings: settings.boardSettings(),
                        onMove: _onMove,
                        shapes: {?hintArrow},
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    message ?? s.f('puzzle.findBest', [sideName]),
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: messageColor),
                    textAlign: TextAlign.center,
                  ),
                ),
                Text(s.f('puzzle.solvedCount', [solvedIds.length, all.length]), style: Theme.of(context).textTheme.bodySmall),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      OutlinedButton.icon(
                        onPressed: solved ? null : _showSolution,
                        icon: const Icon(Icons.lightbulb_outline),
                        label: Text(s.t('puzzle.solution')),
                      ),
                      FilledButton.icon(
                        onPressed: () => _next(all),
                        icon: const Icon(Icons.skip_next),
                        label: Text(s.t('puzzle.next')),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
