import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/game_models.dart';

/// Local SQLite storage for games (finished and unfinished).
class DatabaseService {
  Database? _db;

  Future<Database> get db async => _db ??= await _open();

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    return openDatabase(
      p.join(dir, 'shatranj.db'),
      version: 1,
      onCreate: (db, v) async {
        await db.execute('''
          CREATE TABLE games (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            mode TEXT NOT NULL,
            level INTEGER,
            human_side TEXT,
            time_control TEXT,
            chess960 INTEGER DEFAULT 0,
            rotation TEXT,
            start_fen TEXT NOT NULL,
            moves TEXT,
            created_at INTEGER,
            result TEXT,
            reason TEXT,
            white_ms INTEGER,
            black_ms INTEGER,
            hints_used INTEGER DEFAULT 0
          )
        ''');
      },
    );
  }

  /// Inserts or updates; returns the row id.
  Future<int> save(GameRecord g) async {
    final d = await db;
    if (g.id == null) {
      g.id = await d.insert('games', g.toMap());
    } else {
      await d.update('games', g.toMap(), where: 'id = ?', whereArgs: [g.id]);
    }
    return g.id!;
  }

  Future<List<GameRecord>> allGames() async {
    final d = await db;
    final rows = await d.query('games', orderBy: 'created_at DESC');
    return rows.map(GameRecord.fromMap).toList();
  }

  /// The most recent unfinished game that has at least one move.
  Future<GameRecord?> latestUnfinished() async {
    final d = await db;
    final rows = await d.query(
      'games',
      where: "result IS NULL AND moves IS NOT NULL AND moves != ''",
      orderBy: 'created_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : GameRecord.fromMap(rows.first);
  }

  Future<void> delete(int id) async {
    final d = await db;
    await d.delete('games', where: 'id = ?', whereArgs: [id]);
  }

  /// Abandons every unfinished game except [keepId].
  Future<void> discardUnfinished({int? keepId}) async {
    final d = await db;
    await d.delete(
      'games',
      where: keepId == null ? 'result IS NULL' : 'result IS NULL AND id != ?',
      whereArgs: keepId == null ? null : [keepId],
    );
  }
}
