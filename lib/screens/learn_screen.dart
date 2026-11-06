import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/content.dart';
import '../providers.dart';
import '../services/sound_service.dart';
import '../widgets/common.dart';

class LearnScreen extends ConsumerWidget {
  const LearnScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('learn.title'))),
      body: ListView.separated(
        itemCount: kLessons.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final l = kLessons[i];
          return ListTile(
            leading: CircleAvatar(child: Text(s.n(i + 1))),
            title: Text(s.isFa ? l.titleFa : l.titleEn),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => LessonScreen(index: i))),
          );
        },
      ),
    );
  }
}

/// One interactive lesson: tap a piece to see where it can go, then move it.
class LessonScreen extends ConsumerStatefulWidget {
  const LessonScreen({super.key, required this.index});
  final int index;

  @override
  ConsumerState<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends ConsumerState<LessonScreen> {
  late Position pos;
  late ChessboardController board;
  Move? last;
  String? status;

  Lesson get lesson => kLessons[widget.index];

  @override
  void initState() {
    super.initState();
    pos = Chess.fromSetup(Setup.parseFen(lesson.fen), ignoreImpossibleCheck: true);
    board = ChessboardController(game: _data());
  }

  @override
  void dispose() {
    board.dispose();
    super.dispose();
  }

  GameData _data() => GameData(
    fen: pos.fen,
    lastMove: last,
    playerSide: pos.isGameOver && !lesson.keepTurn ? PlayerSide.none : PlayerSide.white,
    sideToMove: pos.turn,
    kingSquareInCheck: pos.isCheck ? pos.board.kingOf(pos.turn) : null,
    validMoves: pos.turn == Side.white ? makeLegalMoves(pos) : const {},
  );

  void _reset() {
    pos = Chess.fromSetup(Setup.parseFen(lesson.fen), ignoreImpossibleCheck: true);
    last = null;
    status = null;
    board.updatePosition(_data(), animate: false, resetPremove: true);
    setState(() {});
  }

  void _onMove(Move m, {bool? viaDragAndDrop}) {
    final s = ref.read(stringsProvider);
    final normalized = m is NormalMove ? pos.normalizeMove(m) : m;
    if (!pos.isLegal(normalized)) return;
    final san = pos.makeSan(normalized).$2;
    var next = pos.play(normalized);
    last = normalized;
    status = san;
    if (next.isCheckmate) {
      status = '$san — ${s.t('reason.checkmate')}!';
    } else if (next.isStalemate) {
      status = '$san — ${s.t('reason.stalemate')}';
    } else if (lesson.keepTurn) {
      // Give the move back to White so the learner can keep exploring.
      try {
        final parts = next.fen.split(' ');
        parts[1] = 'w';
        parts[3] = '-';
        next = Chess.fromSetup(Setup.parseFen(parts.join(' ')), ignoreImpossibleCheck: true);
      } catch (_) {}
    }
    pos = next;
    ref.read(soundProvider).play(SoundKindExt.forPosition(pos));
    board.updatePosition(_data());
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final settings = ref.watch(settingsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(s.isFa ? lesson.titleFa : lesson.titleEn)),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(s.isFa ? lesson.textFa : lesson.textEn, style: const TextStyle(fontSize: 15, height: 1.6)),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: LtrBoard(
                  builder: (context, size) => Chessboard(
                    size: size,
                    controller: board,
                    orientation: Side.white,
                    settings: settings.boardSettings().copyWith(showValidMoves: true),
                    onMove: _onMove,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(status ?? s.t('learn.tryIt'), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  OutlinedButton.icon(onPressed: _reset, icon: const Icon(Icons.refresh), label: Text(s.t('learn.reset'))),
                  if (widget.index + 1 < kLessons.length)
                    FilledButton.icon(
                      onPressed: () => Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => LessonScreen(index: widget.index + 1)),
                      ),
                      icon: const Icon(Icons.navigate_next),
                      label: Text(s.t('common.next')),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
