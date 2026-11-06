import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/game_controller.dart';
import '../l10n/content.dart';
import '../l10n/strings.dart';
import '../logic/hint_explainer.dart';
import '../models/game_models.dart';
import '../providers.dart';
import '../widgets/common.dart';
import 'analysis_screen.dart';

String resultLine(AppStrings s, GameResult r, {Side? humanSide}) {
  final reason = s.t('reason.${r.reason.name}');
  String head;
  if (r.isDraw) {
    head = s.t('game.drawResult');
  } else if (humanSide != null) {
    head = r.winner == humanSide ? s.t('game.youWin') : s.t('game.youLose');
  } else {
    head = r.winner == Side.white ? s.t('game.whiteWins') : s.t('game.blackWins');
  }
  return '$head — $reason';
}

class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key, required this.config, this.resume});

  final GameConfig config;
  final GameRecord? resume;

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> with WidgetsBindingObserver {
  late final GameController c;
  bool _resultShown = false;
  bool _blunderShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c = GameController(
      config: widget.config,
      engine: ref.read(engineProvider),
      db: ref.read(databaseProvider),
      sound: ref.read(soundProvider),
      settings: ref.read(settingsProvider),
      strings: ref.read(stringsProvider),
      resume: widget.resume,
    );
    _resultShown = c.result != null;
    c.addListener(_onChange);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      c.pauseClock();
    } else if (state == AppLifecycleState.resumed) {
      c.resumeClock();
    }
  }

  void _onChange() {
    if (!mounted) return;
    if (c.result != null && !_resultShown) {
      _resultShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _showResult());
    }
    if (c.blunder != null && !_blunderShown) {
      _blunderShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _showBlunder());
    }
    if (c.blunder == null) _blunderShown = false;
    if (c.result == null) _resultShown = false;
  }

  Future<void> _showBlunder() async {
    final s = ref.read(stringsProvider);
    final b = c.blunder;
    if (b == null) return;
    final undo = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 40),
        title: Text(s.t('blunder.title')),
        content: Text(b.mate ? s.t('blunder.mate') : s.t('blunder.loses')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.t('blunder.keep'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.t('blunder.undo'))),
        ],
      ),
    );
    if (undo == true) {
      c.takeBackBlunder();
    } else {
      c.keepBlunder();
    }
  }

  Future<void> _showResult() async {
    final s = ref.read(stringsProvider);
    final r = c.result;
    if (r == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.t('game.over')),
        content: Text(resultLine(s, r, humanSide: c.isAi ? c.humanSide : null), style: const TextStyle(fontSize: 18)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => AnalysisScreen(startFen: c.game.startFen, uciMoves: c.game.uciMoves, autoAnalyze: true)),
              );
            },
            child: Text(s.t('game.analyze')),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(s.t('common.ok'))),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    c.removeListener(_onChange);
    c.dispose();
    super.dispose();
  }

  Future<void> _offerDraw() async {
    final s = ref.read(stringsProvider);
    if (c.isAi) {
      final ok = await c.offerDrawToComputer();
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('game.drawDeclined'))));
      }
    } else {
      final ok = await confirmDialog(context, s.t('game.drawOffer2p'), s);
      if (ok) c.agreeDraw();
    }
  }

  Future<void> _resign() async {
    final s = ref.read(stringsProvider);
    final ok = await confirmDialog(context, s.t('game.resignConfirm'), s);
    if (ok) c.resign();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final settings = ref.watch(settingsProvider);
    ref.listen(settingsProvider, (_, next) => c.updateSettings(next, ref.read(stringsProvider)));

    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final orientation = c.orientation;
        final topSide = orientation.opposite;
        final bottomSide = orientation;
        final showEval = c.isAi && settings.evalBar && c.evalWhiteCp != null;
        final title = c.isAi
            ? '${s.t('home.ai')} — ${s.t('stats.level')} ${s.n(c.config.level)}'
            : s.t('home.twoPlayer');
        return Scaffold(
          appBar: AppBar(
            title: Text(title, style: const TextStyle(fontSize: 17)),
            actions: [
              IconButton(
                tooltip: s.t('game.export'),
                icon: const Icon(Icons.ios_share),
                onPressed: () => showExportSheet(context, s, pgn: c.pgn(), fen: c.position.fen),
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                _playerBar(s, topSide, upsideDown: c.pieceOrientation == PieceOrientationBehavior.opponentUpsideDown),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      textDirection: TextDirection.ltr,
                      children: [
                        if (showEval)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: SizedBox(
                              width: 14,
                              child: EvalBar(whiteCp: c.evalWhiteCp, whiteAtBottom: orientation == Side.white, strings: s),
                            ),
                          ),
                        Expanded(
                          child: LtrBoard(
                            builder: (context, size) => Chessboard(
                              size: size,
                              controller: c.board,
                              orientation: orientation,
                              settings: settings.boardSettings(orientation: c.pieceOrientation),
                              onMove: c.onUserMove,
                              shapes: {if (c.hintArrow != null) c.hintArrow!},
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _playerBar(s, bottomSide),
                _statusLine(s),
                MoveList(
                  sans: c.game.sans.take(c.game.length).toList(),
                  cursor: c.game.cursor,
                  strings: s,
                  startPly: c.game.initialPosition.turn == Side.black ? 1 : 0,
                  onTap: (_) {},
                ),
                _actions(s, settings.tips),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _playerBar(AppStrings s, Side side, {bool upsideDown = false}) {
    final String name;
    if (c.isAi) {
      name = side == c.humanSide ? s.t('you') : '${s.t('computer')} (${s.n(c.config.level)})';
    } else {
      name = side == Side.white ? s.t('setup.white') : s.t('setup.black');
    }
    final active = c.result == null && c.position.turn == side;
    final bar = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Icon(Icons.circle, size: 14, color: side == Side.white ? Colors.white : Colors.black,
              shadows: const [Shadow(blurRadius: 2, color: Colors.grey)]),
          const SizedBox(width: 8),
          Text(name, style: TextStyle(fontWeight: active ? FontWeight.bold : FontWeight.normal)),
          if (c.isAi && side != c.humanSide && c.thinking && c.blunder == null) ...[
            const SizedBox(width: 8),
            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
          ],
          const Spacer(),
          if (c.hasClock) ClockFace(ms: side == Side.white ? c.whiteMs : c.blackMs, active: active && c.game.length > 0, strings: s),
        ],
      ),
    );
    return upsideDown ? RotatedBox(quarterTurns: 2, child: bar) : bar;
  }

  Widget _statusLine(AppStrings s) {
    final scheme = Theme.of(context).colorScheme;
    String text;
    Color? color;
    if (c.result != null) {
      text = resultLine(s, c.result!, humanSide: c.isAi ? c.humanSide : null);
      color = scheme.primary;
    } else if (c.hintText != null) {
      text = '💡 ${c.hintText!}';
      color = Colors.green.shade700;
    } else if (c.tipText != null) {
      text = '📘 ${c.tipText!}';
    } else if (c.position.isCheck) {
      text = s.t('game.check');
      color = Colors.red;
    } else if (c.isAi) {
      text = c.position.turn == c.humanSide ? s.t('game.yourTurn') : s.t('game.thinking');
    } else {
      text = c.position.turn == Side.white ? s.t('game.whiteTurn') : s.t('game.blackTurn');
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: SizedBox(
        width: double.infinity,
        child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: color, fontWeight: FontWeight.w600), maxLines: 3),
      ),
    );
  }

  Widget _actions(AppStrings s, bool tipsOn) {
    final over = c.result != null;
    final buttons = <Widget>[
      _btn(Icons.undo, s.t('game.undo'), c.canUndo ? c.undo : null),
      _btn(Icons.redo, s.t('game.redo'), c.canRedo ? c.redo : null),
      if (c.hintsEnabled)
        _btn(
          Icons.lightbulb_outline,
          c.hintsLeft > 1000 ? s.t('game.hint') : '${s.t('game.hint')} (${s.n(c.hintsLeft)})',
          (!over && c.isHumanTurn && !c.thinking && c.hintsLeft > 0) ? c.requestHint : null,
        ),
      if (tipsOn && c.isAi)
        _btn(Icons.school_outlined, s.t('game.tip'), () => c.showTip(kTips[phaseOf(c.position)] ?? const [])),
      _btn(Icons.screen_rotation_alt, s.t('game.flip'), c.flip),
      _btn(Icons.handshake_outlined, s.t('game.draw'), over ? null : _offerDraw),
      _btn(Icons.flag_outlined, s.t('game.resign'), over ? null : _resign),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(children: buttons),
    );
  }

  Widget _btn(IconData icon, String label, VoidCallback? onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Opacity(
          opacity: onTap == null ? 0.35 : 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [Icon(icon), const SizedBox(height: 2), Text(label, style: const TextStyle(fontSize: 11))],
            ),
          ),
        ),
      ),
    );
  }
}
