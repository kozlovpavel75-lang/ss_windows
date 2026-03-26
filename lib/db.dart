import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'crypto.dart';

class DbPrompt {
  final String id, title, content, category;
  final bool isFavorite;
  final int useCount, ratingSum, ratingCount;
  final String lastUsed;
  const DbPrompt({
    required this.id, required this.title, required this.content,
    required this.category, this.isFavorite = false,
    this.useCount = 0, this.lastUsed = '', this.ratingSum = 0, this.ratingCount = 0,
  });
}

class DbDoc {
  final String id, name, path;
  const DbDoc({required this.id, required this.name, required this.path});
}

class DbTimelineEvent {
  final String id, date, description;
  const DbTimelineEvent({required this.id, required this.date, required this.description});
}

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
    final path = p.join(dbPath, 'ukr_osint.db');
    return await openDatabase(path, version: 2, onCreate: _onCreate, onUpgrade: _onUpgrade);
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''CREATE TABLE prompts (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      content TEXT NOT NULL,
      category TEXT NOT NULL,
      is_favorite INTEGER NOT NULL DEFAULT 0,
      sort_order INTEGER NOT NULL DEFAULT 0,
      use_count INTEGER NOT NULL DEFAULT 0,
      last_used TEXT NOT NULL DEFAULT '',
      rating_sum INTEGER NOT NULL DEFAULT 0,
      rating_count INTEGER NOT NULL DEFAULT 0
    )''');
    await db.execute('CREATE TABLE docs (id TEXT PRIMARY KEY, name TEXT NOT NULL, path TEXT NOT NULL)');
    await db.execute('CREATE TABLE audit_logs (id INTEGER PRIMARY KEY AUTOINCREMENT, message TEXT NOT NULL, created_at TEXT NOT NULL)');
    await db.execute('CREATE TABLE timeline (id TEXT PRIMARY KEY, date TEXT NOT NULL, description TEXT NOT NULL)');
    await db.execute('CREATE TABLE vault (id TEXT PRIMARY KEY, resource TEXT NOT NULL, login TEXT NOT NULL, password TEXT NOT NULL)');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Додаємо нові колонки для статистики промптів
      await db.execute('ALTER TABLE prompts ADD COLUMN use_count INTEGER NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE prompts ADD COLUMN last_used TEXT NOT NULL DEFAULT \'\'');
      await db.execute('ALTER TABLE prompts ADD COLUMN rating_sum INTEGER NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE prompts ADD COLUMN rating_count INTEGER NOT NULL DEFAULT 0');
    }
  }

  CryptoHelper get _c => CryptoHelper.instance;

  // ПРОМПТИ
  Future<List<DbPrompt>> getPrompts() async {
    final db = await database;
    final maps = await db.query('prompts', orderBy: 'sort_order ASC, title ASC');
    final result = <DbPrompt>[];
    for (final m in maps) {
      result.add(DbPrompt(
        id: m['id'] as String,
        title: await _c.decrypt(m['title'] as String),
        content: await _c.decrypt(m['content'] as String),
        category: await _c.decrypt(m['category'] as String),
        isFavorite: (m['is_favorite'] as int? ?? 0) == 1,
        useCount: m['use_count'] as int? ?? 0,
        lastUsed: m['last_used'] as String? ?? '',
        ratingSum: m['rating_sum'] as int? ?? 0,
        ratingCount: m['rating_count'] as int? ?? 0,
      ));
    }
    return result;
  }

  Future<void> insertPrompt(DbPrompt prompt, {int sortOrder = 0}) async {
    final db = await database;
    await db.insert('prompts', {
      'id': prompt.id,
      'title': await _c.encrypt(prompt.title),
      'content': await _c.encrypt(prompt.content),
      'category': await _c.encrypt(prompt.category),
      'is_favorite': prompt.isFavorite ? 1 : 0,
      'sort_order': sortOrder,
      'use_count': prompt.useCount,
      'last_used': prompt.lastUsed,
      'rating_sum': prompt.ratingSum,
      'rating_count': prompt.ratingCount,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updatePrompt(DbPrompt prompt) async {
    final db = await database;
    await db.update('prompts', {
      'title': await _c.encrypt(prompt.title),
      'content': await _c.encrypt(prompt.content),
      'category': await _c.encrypt(prompt.category),
      'is_favorite': prompt.isFavorite ? 1 : 0,
    }, where: 'id = ?', whereArgs: [prompt.id]);
  }

  Future<void> deletePrompt(String id) async {
    final db = await database;
    await db.delete('prompts', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updatePromptOrder(List<DbPrompt> prompts) async {
    final db = await database;
    final batch = db.batch();
    for (int i = 0; i < prompts.length; i++) {
      batch.update('prompts', {'sort_order': i}, where: 'id = ?', whereArgs: [prompts[i].id]);
    }
    await batch.commit(noResult: true);
  }

  Future<void> updateFavorite(String id, bool isFavorite) async {
    final db = await database;
    await db.update('prompts', {'is_favorite': isFavorite ? 1 : 0}, where: 'id = ?', whereArgs: [id]);
  }

  /// Збільшити лічильник використання
  Future<void> recordUsage(String id) async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE prompts SET use_count = use_count + 1, last_used = ? WHERE id = ?',
      [DateTime.now().toIso8601String(), id],
    );
  }

  /// Додати оцінку (1=ні, 2=частково, 3=так)
  Future<void> recordRating(String id, int rating) async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE prompts SET rating_sum = rating_sum + ?, rating_count = rating_count + 1 WHERE id = ?',
      [rating, id],
    );
  }

  Future<List<DbPrompt>> searchPrompts(String query) async {
    final all = await getPrompts();
    final q = query.toLowerCase();
    return all.where((p) => p.title.toLowerCase().contains(q) || p.content.toLowerCase().contains(q)).toList();
  }

  // ДОКУМЕНТИ
  Future<List<DbDoc>> getDocs() async {
    final db = await database;
    final maps = await db.query('docs');
    final result = <DbDoc>[];
    for (final m in maps) {
      result.add(DbDoc(
        id: m['id'] as String,
        name: await _c.decrypt(m['name'] as String),
        path: await _c.decrypt(m['path'] as String),
      ));
    }
    return result;
  }

  Future<void> insertDoc(DbDoc doc) async {
    final db = await database;
    await db.insert('docs', {
      'id': doc.id,
      'name': await _c.encrypt(doc.name),
      'path': await _c.encrypt(doc.path),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteDoc(String id) async {
    final db = await database;
    await db.delete('docs', where: 'id = ?', whereArgs: [id]);
  }

  // ЖУРНАЛ
  Future<List<String>> getLogs({int limit = 100}) async {
    final db = await database;
    final maps = await db.query('audit_logs', orderBy: 'id DESC', limit: limit);
    final result = <String>[];
    for (final m in maps) {
      result.add(await _c.decrypt(m['message'] as String));
    }
    return result;
  }

  Future<void> insertLog(String message) async {
    final db = await database;
    await db.insert('audit_logs', {
      'message': await _c.encrypt(message),
      'created_at': DateTime.now().toIso8601String(),
    });
    await db.execute('DELETE FROM audit_logs WHERE id NOT IN (SELECT id FROM audit_logs ORDER BY id DESC LIMIT 200)');
  }

  Future<void> clearLogs() async {
    final db = await database;
    await db.delete('audit_logs');
  }

  // ХРОНОЛОГІЯ
  Future<List<DbTimelineEvent>> getTimeline() async {
    final db = await database;
    final maps = await db.query('timeline', orderBy: 'date ASC');
    final result = <DbTimelineEvent>[];
    for (final m in maps) {
      result.add(DbTimelineEvent(
        id: m['id'] as String,
        date: await _c.decrypt(m['date'] as String),
        description: await _c.decrypt(m['description'] as String),
      ));
    }
    return result;
  }

  Future<void> insertTimelineEvent(DbTimelineEvent e) async {
    final db = await database;
    await db.insert('timeline', {
      'id': e.id,
      'date': await _c.encrypt(e.date),
      'description': await _c.encrypt(e.description),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteTimelineEvent(String id) async {
    final db = await database;
    await db.delete('timeline', where: 'id = ?', whereArgs: [id]);
  }

  // СЕЙФ
  Future<List<Map<String, String>>> getVault() async {
    final db = await database;
    final maps = await db.query('vault');
    final result = <Map<String, String>>[];
    for (final m in maps) {
      result.add({
        'id': m['id'] as String,
        'r': await _c.decrypt(m['resource'] as String),
        'l': await _c.decrypt(m['login'] as String),
        'p': await _c.decrypt(m['password'] as String),
      });
    }
    return result;
  }

  Future<void> insertVaultEntry(String id, String resource, String login, String password) async {
    final db = await database;
    await db.insert('vault', {
      'id': id,
      'resource': await _c.encrypt(resource),
      'login': await _c.encrypt(login),
      'password': await _c.encrypt(password),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteVaultEntry(String id) async {
    final db = await database;
    await db.delete('vault', where: 'id = ?', whereArgs: [id]);
  }

  // ПОВНЕ ОЧИЩЕННЯ (wipe)
  Future<void> wipeAll() async {
    final db = await database;
    await db.delete('prompts');
    await db.delete('docs');
    await db.delete('audit_logs');
    await db.delete('timeline');
    await db.delete('vault');
  }

  // СТАТИСТИКА
  Future<Map<String, int>> getStats() async {
    final allPrompts = await getPrompts();
    final db = await database;
    final stats = <String, int>{};
    for (final cat in ['ФО', 'ЮО', 'ГЕОІНТ', 'МОНІТОРИНГ']) {
      stats[cat] = allPrompts.where((p) => p.category == cat).length;
    }
    stats['total'] = allPrompts.length;
    stats['docs'] = (await db.rawQuery('SELECT COUNT(*) as cnt FROM docs')).first['cnt'] as int? ?? 0;
    return stats;
  }
}
