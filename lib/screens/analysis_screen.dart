import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/strings.dart';
import '../logic/chess_game.dart';
import '../providers.dart';
import '../services/engine_service.dart';
import '../services/sound_service.dart';
import '../widgets/common.dart';

/// Per-ply analysis data.
class PlyEval {
  const PlyEval({required this.whiteCp, required this.best});
  final int whiteCp;
  final String? best;
}

/// Analysis board: navigate a game, run Stockfish over every position to
/// find blunders/mistakes and show the best move, import/export PGN & FEN.
class AnalysisScreen extends ConsumerStatefulWidget {
  const AnalysisScreen({super.key, this.startFen, this.uciMoves = const [], this.autoAnalyze = false});

  final String? startFen;
  final List<String> uciMoves;
  final bool autoAnalyze;

  @override
  ConsumerState<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends ConsumerState<AnalysisScreen> {
  late ChessGame game;
  late ChessboardController board;
  late EngineService engine;
  Side orientation = Side.white;
  bool engineOn = false;
  EngineResult? live;
  int _gen = 0;

  /// Full-game analysis: index = ply (position index).
  List<PlyEval?> evals = [];
  bool analyzing = false;
  int progress = 0;

  @override
  void initState() {
    super.initState();
    engine = ref.read(engineProvider);
    engine.acquire();
    game = ChessGame.fromUci(widget.startFen ?? kInitialFEN, widget.uciMoves);
    board = ChessboardController(game: _data());
    if (widget.autoAnalyze && EngineService.isSupported && game.length > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fullAnalysis());
    }
  }

  @override
  void dispose() {
    _gen++;
    analyzing = false;
    engine.stop();
    engine.release();
    board.dispose();
    super.dispose();
  }

  GameData _data() {
    final p = game.position;
    return GameData(
      fen: p.fen,
      lastMove: game.lastMove,
      playerSide: analyzing ? PlayerSide.none : PlayerSide.both,
      sideToMove: p.turn,
      kingSquareInCheck: p.isCheck ? p.board.kingOf(p.turn) : null,
      validMoves: game.isOver ? const {} : makeLegalMoves(p),
    );
  }

  void _refresh({bool animate = true}) {
    board.updatePosition(_data(), animate: animate, resetPremove: true);
    live = null;
    setState(() {});
    if (engineOn) _liveEval();
  }

  void _onMove(Move m, {bool? viaDragAndDrop}) {
    final keep = game.cursor;
    if (game.play(m)) {
      if (evals.length > keep + 1) evals = evals.sublist(0, keep + 1);
      ref.read(soundProvider).play(SoundKindExt.forPosition(game.position));
      _refresh();
    }
  }

  Future<void> _liveEval() async {
    final gen = ++_gen;
    final fen = game.position.fen;
    final r = await engine.search(fen, const SearchOptions(moveTimeMs: 700));
    if (!mounted || gen != _gen) return;
    setState(() => live = r);
  }

  Future<void> _fullAnalysis() async {
    if (analyzing) return;
    final gen = ++_gen;
    final n = game.length;
    setState(() {
      analyzing = true;
      progress = 0;
      evals = List.filled(n + 1, null);
    });
    board.updatePosition(_data(), animate: false);
    for (var i = 0; i <= n; i++) {
      final pos = game.positionAt(i);
      int whiteCp;
      String? best;
      if (pos.isCheckmate) {
        whiteCp = pos.turn == Side.white ? -10000 : 10000;
      } else if (pos.isStalemate || pos.isInsufficientMaterial) {
        whiteCp = 0;
      } else {
        final r = await engine.search(pos.fen, const SearchOptions(moveTimeMs: 300));
        if (!mounted || gen != _gen) return;
        whiteCp = pos.turn == Side.white ? r.cp : -r.cp;
        best = r.bestMove;
      }
      evals[i] = PlyEval(whiteCp: whiteCp, best: best);
      setState(() => progress = i + 1);
    }
    setState(() => analyzing = false);
    board.updatePosition(_data(), animate: false);
  }

  /// Annotation for move index i (position i -> i+1).
  String? _mark(int i) {
    if (i + 1 >= evals.length) return null;
    final a = evals[i], b = evals[i + 1];
    if (a == null || b == null) return null;
    final mover = game.positionAt(i).turn;
    final sign = mover == Side.white ? 1 : -1;
    final before = (a.whiteCp * sign).clamp(-1500, 1500);
    final after = (b.whiteCp * sign).clamp(-1500, 1500);
    final loss = before - after;
    if (loss >= 300) return '??';
    if (loss >= 150) return '?';
    if (loss >= 70) return '?!';
    return null;
  }

  Map<int, String> get _marks {
    final m = <int, String>{};
    for (var i = 0; i < game.length; i++) {
      final k = _mark(i);
      if (k != null) m[i] = k;
    }
    return m;
  }

  Arrow? get _bestArrow {
    String? uci;
    if (evals.length > game.cursor && evals[game.cursor] != null) {
      uci = evals[game.cursor]!.best;
    } else if (engineOn && live != null) {
      uci = live!.bestMove;
    }
    final m = uci == null ? null : Move.parse(uci);
    if (m is! NormalMove) return null;
    var dest = m.to;
    final piece = game.position.board.pieceAt(m.from);
    if (piece?.role == Role.king && game.position.board.pieceAt(m.to)?.color == piece?.color) {
      dest = Square.fromCoords(m.to.file > m.from.file ? File.g : File.c, m.from.rank);
    }
    return Arrow(color: const Color(0xAA1565C0), orig: m.from, dest: dest);
  }

  int? get _currentWhiteCp {
    if (evals.length > game.cursor && evals[game.cursor] != null) return evals[game.cursor]!.whiteCp;
    if (engineOn && live != null) {
      return game.position.turn == Side.white ? live!.cp : -live!.cp;
    }
    return null;
  }

  Future<void> _import() async {
    final s = ref.read(stringsProvider);
    final controller = TextEditingController();
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.length < 20000) controller.text = data.text!;
    if (!mounted) return;
    final text = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(s.t('analysis.importTitle')),
        content: Directionality(
          textDirection: TextDirection.ltr,
          child: TextField(
            controller: controller,
            maxLines: 8,
            minLines: 4,
            decoration: InputDecoration(hintText: s.t('analysis.importHint'), border: const OutlineInputBorder()),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(s.t('common.cancel'))),
          FilledButton(onPressed: () => Navigator.pop(c, controller.text), child: Text(s.t('common.import'))),
        ],
      ),
    );
    if (text == null || text.trim().isEmpty) return;
    final t = text.trim();
    ChessGame? g;
    if (ChessGame.tryParseFen(t) != null && !t.contains('[') && !t.contains('1.')) {
      g = ChessGame(startFen: t);
    } else {
      g = ChessGame.fromPgn(t);
      g?.goTo(g.length);
    }
    if (!mounted) return;
    if (g == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('analysis.invalid'))));
      return;
    }
    _gen++;
    setState(() {
      game = g!;
      evals = [];
      analyzing = false;
    });
    _refresh(animate: false);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final settings = ref.watch(settingsProvider);
    final arrow = _bestArrow;
    final cp = _currentWhiteCp;
    final marks = _marks;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('analysis.title')),
        actions: [
          IconButton(icon: const Icon(Icons.file_download_outlined), tooltip: s.t('analysis.importTitle'), onPressed: analyzing ? null : _import),
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: s.t('game.export'),
            onPressed: () => showExportSheet(context, s, pgn: game.toPgn(), fen: game.position.fen),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (analyzing)
              LinearProgressIndicator(value: game.length == 0 ? null : progress / (game.length + 1)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Row(
                  textDirection: TextDirection.ltr,
                  children: [
                    if (cp != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: SizedBox(width: 14, child: EvalBar(whiteCp: cp, whiteAtBottom: orientation == Side.white, strings: s)),
                      ),
                    Expanded(
                      child: LtrBoard(
                        builder: (context, size) => Chessboard(
                          size: size,
                          controller: board,
                          orientation: orientation,
                          settings: settings.boardSettings(),
                          onMove: _onMove,
                          shapes: {?arrow},
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _info(s, cp, marks),
            MoveList(
              sans: game.sans,
              cursor: game.cursor,
              strings: s,
              marks: marks,
              startPly: game.initialPosition.turn == Side.black ? 1 : 0,
              onTap: (ply) {
                game.goTo(ply);
                _refresh(animate: false);
              },
            ),
            _nav(s),
          ],
        ),
      ),
    );
  }

  Widget _info(AppStrings s, int? cp, Map<int, String> marks) {
    final lines = <String>[];
    if (analyzing) lines.add(s.f('analysis.running', [progress, game.length + 1]));
    if (game.cursor > 0) {
      final m = marks[game.cursor - 1];
      if (m != null) {
        final label = switch (m) {
          '??' => s.t('analysis.blunder'),
          '?' => s.t('analysis.mistake'),
          _ => s.t('analysis.inaccuracy'),
        };
        final prevBest = evals.length > game.cursor - 1 ? evals[game.cursor - 1]?.best : null;
        var bestSan = '';
        if (prevBest != null) {
          final mv = Move.parse(prevBest);
          if (mv != null) {
            try {
              bestSan = game.positionAt(game.cursor - 1).makeSan(game.positionAt(game.cursor - 1).normalizeMove(mv as NormalMove)).$2;
            } catch (_) {}
          }
        }
        lines.add('${game.sans[game.cursor - 1]}$m  $label${bestSan.isEmpty ? '' : ' — ${s.t('analysis.best').replaceAll('{0}', bestSan)}'}');
      }
    }
    if (!analyzing && evals.isNotEmpty && evals.every((e) => e != null)) {
      var wb = 0, wm = 0, bb = 0, bm = 0;
      marks.forEach((i, m) {
        final white = game.positionAt(i).turn == Side.white;
        if (m == '??') white ? wb++ : bb++;
        if (m == '?') white ? wm++ : bm++;
      });
      lines.add(s.f('analysis.summary', [wb, wm, bb, bm]));
    }
    if (cp != null) {
      final txt = cp.abs() >= 9000 ? (cp > 0 ? '+M' : '-M') : '${cp >= 0 ? '+' : ''}${(cp / 100).toStringAsFixed(2)}';
      lines.add('${s.t('analysis.engine')}: $txt');
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Column(children: [for (final l in lines) Text(l, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13))]),
    );
  }

  Widget _nav(AppStrings s) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(icon: const Icon(Icons.first_page), onPressed: () { game.goTo(0); _refresh(animate: false); }),
          IconButton(icon: const Icon(Icons.chevron_left), onPressed: game.cursor > 0 ? () { game.goTo(game.cursor - 1); _refresh(); } : null),
          IconButton(icon: const Icon(Icons.chevron_right), onPressed: game.canRedo ? () { game.goTo(game.cursor + 1); _refresh(); } : null),
          IconButton(icon: const Icon(Icons.last_page), onPressed: () { game.goTo(game.length); _refresh(animate: false); }),
          IconButton(
            icon: const Icon(Icons.screen_rotation_alt),
            onPressed: () => setState(() => orientation = orientation.opposite),
          ),
          if (EngineService.isSupported)
            IconButton(
              tooltip: s.t('analysis.engine'),
              icon: Icon(engineOn ? Icons.memory : Icons.memory_outlined, color: engineOn ? Colors.green : null),
              onPressed: () {
                setState(() => engineOn = !engineOn);
                if (engineOn) _liveEval();
              },
            ),
          if (EngineService.isSupported)
            IconButton(
              tooltip: s.t('analysis.run'),
              icon: const Icon(Icons.analytics_outlined),
              onPressed: analyzing || game.length == 0 ? null : _fullAnalysis,
            ),
        ],
      ),
    );
  }
}
