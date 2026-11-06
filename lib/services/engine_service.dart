import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:multistockfish/multistockfish.dart';

/// Result of one engine search.
class EngineResult {
  const EngineResult({required this.bestMove, this.scoreCp, this.mateIn, this.pv = const [], this.depth = 0});

  /// UCI move, e.g. `e2e4`. `null` when there is no legal move.
  final String? bestMove;

  /// Score in centipawns from the side-to-move's point of view.
  final int? scoreCp;

  /// Mate in N (positive: side to move mates; negative: gets mated).
  final int? mateIn;
  final List<String> pv;
  final int depth;

  /// Score clamped into centipawns, mate mapped to ±10000.
  int get cp {
    if (mateIn != null) return mateIn! > 0 ? 10000 - mateIn! : -10000 - mateIn!;
    return scoreCp ?? 0;
  }
}

/// Options for one search.
class SearchOptions {
  const SearchOptions({this.moveTimeMs = 500, this.depth, this.elo, this.skill, this.chess960 = false});

  final int moveTimeMs;
  final int? depth;

  /// When set, `UCI_LimitStrength` is enabled with this Elo.
  final int? elo;

  /// Stockfish `Skill Level` 0..20 (20 = full strength).
  final int? skill;
  final bool chess960;

  static const analysis = SearchOptions(moveTimeMs: 400);
}

/// Owns the single on-device Stockfish process (multistockfish, light flavor).
///
/// Stockfish runs in its own native threads/isolates, so searching never blocks
/// the UI. Searches are serialized through a queue. The engine is created when
/// the first screen [acquire]s it and disposed when the last one [release]s it,
/// and also when the app is detached.
class EngineService {
  Stockfish? _engine;
  Future<Stockfish>? _starting;
  StreamSubscription<String>? _sub;
  int _users = 0;
  Future<void> _queue = Future.value();
  Completer<EngineResult>? _pending;
  _InfoAccumulator _info = _InfoAccumulator();
  bool _disposed = false;

  /// Whether the native engine is available on this platform.
  static bool get isSupported =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  void acquire() {
    _users++;
    _disposed = false;
  }

  Future<void> release() async {
    _users = (_users - 1).clamp(0, 1 << 30);
    if (_users == 0) await shutdown();
  }

  Future<Stockfish> _ensureEngine() async {
    final e = _engine;
    if (e != null && e.state.value == StockfishState.ready) return e;
    return _starting ??= _start();
  }

  Future<Stockfish> _start() async {
    try {
      final engine = await Stockfish.create();
      _engine = engine;
      _sub = engine.stdout.listen(_onLine);
      engine.stdin = 'uci';
      engine.stdin = 'setoption name Threads value 1';
      engine.stdin = 'setoption name Hash value 32';
      engine.stdin = 'isready';
      return engine;
    } finally {
      _starting = null;
    }
  }

  void _onLine(String line) {
    if (line.startsWith('info') && line.contains(' score ')) {
      _info.parse(line);
    } else if (line.startsWith('bestmove')) {
      final parts = line.split(' ');
      final best = parts.length > 1 && parts[1] != '(none)' ? parts[1] : null;
      final res = EngineResult(
        bestMove: best,
        scoreCp: _info.cp,
        mateIn: _info.mate,
        pv: _info.pv,
        depth: _info.depth,
      );
      final p = _pending;
      _pending = null;
      if (p != null && !p.isCompleted) p.complete(res);
    }
  }

  /// Searches [fen] and returns the best move with its evaluation.
  Future<EngineResult> search(String fen, SearchOptions o) {
    final completer = Completer<EngineResult>();
    _queue = _queue.then((_) async {
      if (_disposed && _users == 0) {
        completer.complete(const EngineResult(bestMove: null));
        return;
      }
      try {
        final engine = await _ensureEngine();
        _info = _InfoAccumulator();
        _pending = Completer<EngineResult>();
        final limit = o.elo != null;
        engine.stdin = 'setoption name UCI_Chess960 value ${o.chess960}';
        engine.stdin = 'setoption name UCI_LimitStrength value $limit';
        if (limit) engine.stdin = 'setoption name UCI_Elo value ${o.elo!.clamp(1320, 3190)}';
        engine.stdin = 'setoption name Skill Level value ${o.skill ?? 20}';
        engine.stdin = 'position fen $fen';
        final go = StringBuffer('go movetime ${o.moveTimeMs}');
        if (o.depth != null) go.write(' depth ${o.depth}');
        engine.stdin = go.toString();
        final res = await _pending!.future.timeout(
          Duration(milliseconds: o.moveTimeMs + 8000),
          onTimeout: () {
            engine.stdin = 'stop';
            return const EngineResult(bestMove: null);
          },
        );
        completer.complete(res);
      } catch (e) {
        if (!completer.isCompleted) completer.complete(const EngineResult(bestMove: null));
      }
    });
    return completer.future;
  }

  /// Stops the current search early (its result still arrives).
  void stop() {
    if (_pending != null) _engine?.stdin = 'stop';
  }

  /// Disposes the native engine. Safe to call multiple times.
  Future<void> shutdown() async {
    _disposed = true;
    stop();
    final e = _engine;
    _engine = null;
    await _sub?.cancel();
    _sub = null;
    if (e != null && e.state.value != StockfishState.disposed) {
      try {
        await e.dispose();
      } catch (_) {}
    }
  }
}

class _InfoAccumulator {
  int? cp;
  int? mate;
  List<String> pv = const [];
  int depth = 0;

  void parse(String line) {
    final t = line.split(' ');
    // Only use the main line (multipv 1).
    final mpv = t.indexOf('multipv');
    if (mpv >= 0 && mpv + 1 < t.length && t[mpv + 1] != '1') return;
    final d = t.indexOf('depth');
    if (d >= 0 && d + 1 < t.length) depth = int.tryParse(t[d + 1]) ?? depth;
    final s = t.indexOf('score');
    if (s >= 0 && s + 2 < t.length) {
      if (t[s + 1] == 'cp') {
        cp = int.tryParse(t[s + 2]);
        mate = null;
      } else if (t[s + 1] == 'mate') {
        mate = int.tryParse(t[s + 2]);
        cp = null;
      }
    }
    final p = t.indexOf('pv');
    if (p >= 0) pv = t.sublist(p + 1);
  }
}
