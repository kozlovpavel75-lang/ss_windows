import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'dart:convert';

// ─────────────────────────────────────────────
// МОДЕЛЬ ДАНИХ (дублюємо тут щоб db.dart був
// незалежним від main.dart)
// ─────────────────────────────────────────────

class DbPrompt {
  final String id, title, content, category;
  final bool isFavorite;
  const DbPrompt({
    required this.id,
    required this.title,
    required this.content,
    required this.category,
    this.isFavorite = false,
  });

  Map<String, dynamic> toMap() => {
    'id':         id,
    'title':      title,
    'content':    content,
    'category':   category,
    'is_favorite': isFavorite ? 1 : 0,
  };

  factory DbPrompt.fromMap(Map<String, dynamic> m) => DbPrompt(
    id:         m['id'] as String,
    title:      m['title'] as String,
    content:    m['content'] as String,
    category:   m['category'] as String,
    isFavorite: (m['is_favorite'] as int? ?? 0) == 1,
  );
}

class DbDoc {
  final String id, name, path;
  const DbDoc({required this.id, required this.name, required this.path});

  Map<String, dynamic> toMap() => {'id': id, 'name': name, 'path': path};

  factory DbDoc.fromMap(Map<String, dynamic> m) => DbDoc(
    id:   m['id'] as String,
    name: m['name'] as String,
    path: m['path'] as String,
  );
}

class DbTimelineEvent {
  final String id, date, description;
  const DbTimelineEvent({
    required this.id,
    required this.date,
    required this.description,
  });

  Map<String, dynamic> toMap() => {
    'id':          id,
    'date':        date,
    'description': description,
  };

  factory DbTimelineEvent.fromMap(Map<String, dynamic> m) => DbTimelineEvent(
    id:          m['id'] as String,
    date:        m['date'] as String,
    description: m['description'] as String,
  );
}

// ─────────────────────────────────────────────
// ГОЛОВНИЙ КЛАС БАЗИ ДАНИХ
// ─────────────────────────────────────────────

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._internal();
  static Database? _db;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path   = p.join(dbPath, 'ukr_osint.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // Промпти
    await db.execute('''
      CREATE TABLE prompts (
        id         TEXT PRIMARY KEY,
        title      TEXT NOT NULL,
        content    TEXT NOT NULL,
        category   TEXT NOT NULL,
        is_favorite INTEGER NOT NULL DEFAULT 0,
        sort_order INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // Документи (PDF)
    await db.execute('''
      CREATE TABLE docs (
        id   TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        path TEXT NOT NULL
      )
    ''');

    // Журнал дій
    await db.execute('''
      CREATE TABLE audit_logs (
        id        INTEGER PRIMARY KEY AUTOINCREMENT,
        message   TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    // Хронологія
    await db.execute('''
      CREATE TABLE timeline (
        id          TEXT PRIMARY KEY,
        date        TEXT NOT NULL,
        description TEXT NOT NULL
      )
    ''');

    // Сейф (паролі)
    await db.execute('''
      CREATE TABLE vault (
        id       TEXT PRIMARY KEY,
        resource TEXT NOT NULL,
        login    TEXT NOT NULL,
        password TEXT NOT NULL
      )
    ''');
  }

  // ══════════════════════════════════════════
  // ПРОМПТИ
  // ══════════════════════════════════════════

  Future<List<DbPrompt>> getPrompts() async {
    final db   = await database;
    final maps = await db.query('prompts', orderBy: 'sort_order ASC, title ASC');
    return maps.map(DbPrompt.fromMap).toList();
  }

  Future<void> insertPrompt(DbPrompt prompt, {int sortOrder = 0}) async {
    final db  = await database;
    final map = prompt.toMap();
    map['sort_order'] = sortOrder;
    await db.insert('prompts', map, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updatePrompt(DbPrompt prompt) async {
    final db = await database;
    await db.update('prompts', prompt.toMap(),
        where: 'id = ?', whereArgs: [prompt.id]);
  }

  Future<void> deletePrompt(String id) async {
    final db = await database;
    await db.delete('prompts', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updatePromptOrder(List<DbPrompt> prompts) async {
    final db = await database;
    final batch = db.batch();
    for (int i = 0; i < prompts.length; i++) {
      batch.update(
        'prompts',
        {'sort_order': i},
        where: 'id = ?',
        whereArgs: [prompts[i].id],
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> updateFavorite(String id, bool isFavorite) async {
    final db = await database;
    await db.update(
      'prompts',
      {'is_favorite': isFavorite ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Повнотекстовий пошук
  Future<List<DbPrompt>> searchPrompts(String query) async {
    final db = await database;
    final q  = '%${query.toLowerCase()}%';
    final maps = await db.query(
      'prompts',
      where: 'LOWER(title) LIKE ? OR LOWER(content) LIKE ?',
      whereArgs: [q, q],
      orderBy: 'is_favorite DESC, sort_order ASC',
    );
    return maps.map(DbPrompt.fromMap).toList();
  }

  // ══════════════════════════════════════════
  // ДОКУМЕНТИ
  // ══════════════════════════════════════════

  Future<List<DbDoc>> getDocs() async {
    final db   = await database;
    final maps = await db.query('docs');
    return maps.map(DbDoc.fromMap).toList();
  }

  Future<void> insertDoc(DbDoc doc) async {
    final db = await database;
    await db.insert('docs', doc.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteDoc(String id) async {
    final db = await database;
    await db.delete('docs', where: 'id = ?', whereArgs: [id]);
  }

  // ══════════════════════════════════════════
  // ЖУРНАЛ ДІЙ
  // ══════════════════════════════════════════

  Future<List<String>> getLogs({int limit = 100}) async {
    final db   = await database;
    final maps = await db.query(
      'audit_logs',
      orderBy: 'id DESC',
      limit:   limit,
    );
    return maps.map((m) => m['message'] as String).toList();
  }

  Future<void> insertLog(String message) async {
    final db = await database;
    await db.insert('audit_logs', {
      'message':    message,
      'created_at': DateTime.now().toIso8601String(),
    });
    // Тримаємо не більше 200 записів
    await db.execute('''
      DELETE FROM audit_logs
      WHERE id NOT IN (
        SELECT id FROM audit_logs ORDER BY id DESC LIMIT 200
      )
    ''');
  }

  Future<void> clearLogs() async {
    final db = await database;
    await db.delete('audit_logs');
  }

  // ══════════════════════════════════════════
  // ХРОНОЛОГІЯ
  // ══════════════════════════════════════════

  Future<List<DbTimelineEvent>> getTimeline() async {
    final db   = await database;
    final maps = await db.query('timeline', orderBy: 'date ASC');
    return maps.map(DbTimelineEvent.fromMap).toList();
  }

  Future<void> insertTimelineEvent(DbTimelineEvent e) async {
    final db = await database;
    await db.insert('timeline', e.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteTimelineEvent(String id) async {
    final db = await database;
    await db.delete('timeline', where: 'id = ?', whereArgs: [id]);
  }

  // ══════════════════════════════════════════
  // СЕЙФ
  // ══════════════════════════════════════════

  Future<List<Map<String, String>>> getVault() async {
    final db   = await database;
    final maps = await db.query('vault');
    return maps.map((m) => {
      'id':       m['id'] as String,
      'r':        m['resource'] as String,
      'l':        m['login'] as String,
      'p':        m['password'] as String,
    }).toList();
  }

  Future<void> insertVaultEntry(String id, String resource, String login, String password) async {
    final db = await database;
    await db.insert('vault', {
      'id':       id,
      'resource': resource,
      'login':    login,
      'password': password,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteVaultEntry(String id) async {
    final db = await database;
    await db.delete('vault', where: 'id = ?', whereArgs: [id]);
  }

  // ══════════════════════════════════════════
  // СТАТИСТИКА
  // ══════════════════════════════════════════

  Future<Map<String, int>> getStats() async {
    final db = await database;
    final stats = <String, int>{};
    for (final cat in ['ФО', 'ЮО', 'ГЕОІНТ', 'МОНІТОРИНГ']) {
      final result = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM prompts WHERE category = ?', [cat],
      );
      stats[cat] = (result.first['cnt'] as int? ?? 0);
    }
    stats['total'] = (await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM prompts',
    )).first['cnt'] as int? ?? 0;
    stats['docs'] = (await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM docs',
    )).first['cnt'] as int? ?? 0;
    return stats;
  }
}
