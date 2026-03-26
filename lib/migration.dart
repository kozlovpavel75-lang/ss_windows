import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'dart:convert';
import 'db.dart';

// ─────────────────────────────────────────────
// МІГРАЦІЯ SharedPreferences → SQLite
//
// Запускається ОДИН РАЗ при першому старті
// нової версії. Після успіху ставить прапор
// 'migration_done_v1 = true' у SharedPreferences,
// очищує старі незашифровані дані,
// і більше не запускається.
// ─────────────────────────────────────────────

class MigrationHelper {

  static final _uuid = Uuid();
  static String _uid() => _uuid.v4();

  /// Повертає true якщо міграція вже була виконана
  static Future<bool> isMigrationDone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('migration_done_v1') ?? false;
  }

  /// Основна функція міграції.
  /// Викликати ОДИН РАЗ при старті додатку.
  static Future<void> migrate() async {
    if (await isMigrationDone()) return;

    final prefs = await SharedPreferences.getInstance();
    final db    = DatabaseHelper.instance;

    // ── 1. Промпти ──────────────────────────
    final promptsStr = prefs.getString('prompts');
    if (promptsStr != null) {
      try {
        final list = json.decode(promptsStr) as List;
        for (int i = 0; i < list.length; i++) {
          final item = list[i] as Map<String, dynamic>;
          await db.insertPrompt(
            DbPrompt(
              id:         item['id']?.toString()       ?? _uid(),
              title:      item['title']?.toString()    ?? '',
              content:    item['content']?.toString()  ?? '',
              category:   item['category']?.toString() ?? 'МОНІТОРИНГ',
              isFavorite: item['isFavorite'] as bool?  ?? false,
            ),
            sortOrder: i,
          );
        }
      } catch (_) {
        // Якщо дані пошкоджені — просто пропускаємо
      }
    }

    // ── 2. Документи ────────────────────────
    final docsStr = prefs.getString('docs');
    if (docsStr != null) {
      try {
        final list = json.decode(docsStr) as List;
        for (final item in list) {
          final m = item as Map<String, dynamic>;
          await db.insertDoc(DbDoc(
            id:   m['id']?.toString()   ?? _uid(),
            name: m['name']?.toString() ?? '',
            path: m['path']?.toString() ?? '',
          ));
        }
      } catch (_) {}
    }

    // ── 3. Журнал дій ───────────────────────
    final logs = prefs.getStringList('logs') ?? [];
    for (final log in logs.reversed) {
      await db.insertLog(log);
    }

    // ── 4. Хронологія ───────────────────────
    final timelineStr = prefs.getString('timeline');
    if (timelineStr != null) {
      try {
        final list = json.decode(timelineStr) as List;
        for (final item in list) {
          final m = item as Map<String, dynamic>;
          await db.insertTimelineEvent(DbTimelineEvent(
            id:          _uid(),
            date:        m['d']?.toString() ?? '',
            description: m['t']?.toString() ?? '',
          ));
        }
      } catch (_) {}
    }

    // ── 5. Сейф ─────────────────────────────
    final vaultStr = prefs.getString('vault');
    if (vaultStr != null) {
      try {
        final list = json.decode(vaultStr) as List;
        for (final item in list) {
          final m = item as Map<String, dynamic>;
          await db.insertVaultEntry(
            _uid(),
            m['r']?.toString() ?? '',
            m['l']?.toString() ?? '',
            m['p']?.toString() ?? '',
          );
        }
      } catch (_) {}
    }

    // ── 6. Ставимо прапор "міграція виконана" ──
    await prefs.setBool('migration_done_v1', true);

    // ── 7. Очищуємо старі незашифровані дані ──
    await _cleanupOldPrefs(prefs);
  }

  /// Видалити старі SP-дані після успішної міграції
  static Future<void> _cleanupOldPrefs(SharedPreferences prefs) async {
    await prefs.remove('prompts');
    await prefs.remove('docs');
    await prefs.remove('logs');
    await prefs.remove('timeline');
    await prefs.remove('vault');
    await prefs.remove('master_pass');
  }
}
