import 'package:dartchess/dartchess.dart';
import 'package:audioplayers/audioplayers.dart';

enum SoundKind { move, capture, check, end }

/// Plays bundled offline sounds (assets/sounds).
class SoundService {
  final Map<SoundKind, AudioPlayer> _players = {};
  bool enabled = true;

  Future<void> play(SoundKind kind) async {
    if (!enabled) return;
    try {
      final player = _players.putIfAbsent(kind, () {
        final p = AudioPlayer();
        p.setReleaseMode(ReleaseMode.stop);
        p.setPlayerMode(PlayerMode.lowLatency);
        return p;
      });
      await player.stop();
      await player.play(AssetSource('sounds/${kind.name}.wav'));
    } catch (_) {
      // Sound is non-essential; ignore platform errors.
    }
  }

  Future<void> dispose() async {
    for (final p in _players.values) {
      await p.dispose();
    }
    _players.clear();
  }
}

extension SoundKindExt on SoundKind {
  /// Sound for a freshly reached position.
  static SoundKind forPosition(Position p) {
    if (p.isGameOver) return SoundKind.end;
    return p.isCheck ? SoundKind.check : SoundKind.move;
  }
}
