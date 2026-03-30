import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:exif/exif.dart';
import 'package:archive/archive.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:crypto/crypto.dart' as crypto;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:image/image.dart' as img;
import 'db.dart';
import 'migration.dart';
import 'crypto.dart';

// ─────────────────────────────────────────────
// ГЛОБАЛЬНИЙ СТАН
// ─────────────────────────────────────────────
ValueNotifier<bool> isMatrixMode  = ValueNotifier(false);
ValueNotifier<bool> isKyivMode    = ValueNotifier(false);

// Кольори категорій — єдине місце
const Map<String, Color> catColors = {
  'ФО':         Color(0xFF6FA8DC), // синій
  'ЮО':         Color(0xFFE8D98C), // золотий
  'ГЕОІНТ':     Color(0xFF4ADE80), // зелений
  'МОНІТОРИНГ': Color(0xFFE8A05A), // помаранчевий
  'ІНШІ':       Color(0xFFB39DDB), // фіолетовий
  'ЗВІТИ':      Color(0xFF80CBC4), // бірюзовий
};
Color catColor(String cat) => catColors[cat] ?? AppColors.accent;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarColor: Colors.transparent),
  );
  // Ініціалізація sqflite для Windows/Linux (desktop)
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  try {
    await CryptoHelper.instance.init();
    await MigrationHelper.migrate();
  } catch (e) {
    debugPrint('INIT ERROR: \$e');
  }

  // ── Перевірка ліцензії ──────────────────────────────
  final isLicensed = await LicenseGuard.check();
  if (isLicensed) {
    runApp(const PromptApp());
  } else {
    runApp(const LicenseApp());
  }
}

// ─────────────────────────────────────────────
// КОЛЬОРИ
// ─────────────────────────────────────────────
class AppColors {
  static const bg        = Color(0xFF040E22);
  static const bgCard    = Color(0xFF0A152F);
  static const bgDeep    = Color(0xFF040B16);
  static const uaBlue    = Color(0xFF0057B7);
  static const uaYellow  = Color(0xFFE8D98C);
  static const accent    = Color(0xFF6FA8DC);
  static const textPri   = Color(0xFFEEEEEE);
  static const textSec   = Color(0x99FFFFFF);
  static const textHint  = Color(0x40FFFFFF);
  static const border    = Color(0x14FFFFFF);
  static const success   = Color(0xFF4ADE80);
  static const danger    = Color(0xFFFF6B6B);
}

// ─────────────────────────────────────────────
// МОДЕЛІ ДАНИХ
// ─────────────────────────────────────────────
class Prompt {
  String id, title, content, category;
  bool isFavorite;
  int useCount;
  String lastUsed;
  int ratingSum;
  int ratingCount;
  Map<String, Map<String, int>> modelRatings;
  String notes; // коментарі аналітика
  Prompt({required this.id, required this.title, required this.content,
          required this.category, this.isFavorite = false,
          this.useCount = 0, this.lastUsed = '', this.ratingSum = 0, this.ratingCount = 0,
          Map<String, Map<String, int>>? modelRatings, this.notes = ''}) : modelRatings = modelRatings ?? {};
  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'content': content,
      'category': category, 'isFavorite': isFavorite,
      'useCount': useCount, 'lastUsed': lastUsed, 'ratingSum': ratingSum, 'ratingCount': ratingCount,
      'modelRatings': modelRatings.map((k, v) => MapEntry(k, {'sum': v['sum'], 'count': v['count']})),
      'notes': notes};
  factory Prompt.fromJson(Map<String, dynamic> j) {
    Map<String, Map<String, int>> mr = {};
    if (j['modelRatings'] != null) {
      (j['modelRatings'] as Map<String, dynamic>).forEach((k, v) {
        mr[k] = {'sum': (v['sum'] as num?)?.toInt() ?? 0, 'count': (v['count'] as num?)?.toInt() ?? 0};
      });
    }
    return Prompt(
      id: j['id'], title: j['title'], content: j['content'],
      category: j['category'], isFavorite: j['isFavorite'] ?? false,
      useCount: j['useCount'] ?? 0, lastUsed: j['lastUsed'] ?? '',
      ratingSum: j['ratingSum'] ?? 0, ratingCount: j['ratingCount'] ?? 0,
      modelRatings: mr, notes: j['notes'] ?? '');
  }
  double get avgRating => ratingCount > 0 ? ratingSum / ratingCount : 0;
  double modelAvg(String model) {
    final r = modelRatings[model];
    if (r == null || (r['count'] ?? 0) == 0) return 0;
    return r['sum']! / r['count']!;
  }
  void addRating(int score, Set<String> models) {
    ratingSum += score;
    ratingCount++;
    for (final m in models) {
      modelRatings.putIfAbsent(m, () => {'sum': 0, 'count': 0});
      modelRatings[m]!['sum'] = (modelRatings[m]!['sum'] ?? 0) + score;
      modelRatings[m]!['count'] = (modelRatings[m]!['count'] ?? 0) + 1;
    }
    if (models.isEmpty) {
      modelRatings.putIfAbsent('Без моделі', () => {'sum': 0, 'count': 0});
      modelRatings['Без моделі']!['sum'] = (modelRatings['Без моделі']!['sum'] ?? 0) + score;
      modelRatings['Без моделі']!['count'] = (modelRatings['Без моделі']!['count'] ?? 0) + 1;
    }
  }
  List<String> get variables {
    final reg = RegExp(r'\{([^}]+)\}');
    return reg.allMatches(content).map((m) => m.group(1)!).toSet().toList();
  }
}

class PDFDoc {
  String id, name, path;
  PDFDoc({required this.id, required this.name, required this.path});
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'path': path};
  factory PDFDoc.fromJson(Map<String, dynamic> j) =>
      PDFDoc(id: j['id'], name: j['name'], path: j['path']);
}

class PromptEnhancer {
  final String name, desc, pros, cons, conflicts, rec, payload;
  bool isSelected;
  PromptEnhancer({
    required this.name, required this.desc, required this.pros,
    required this.cons, required this.conflicts, required this.rec,
    required this.payload, this.isSelected = false,
  });
}

// ─────────────────────────────────────────────
// ВІЗУАЛЬНІ ЕФЕКТИ
// ─────────────────────────────────────────────
class MatrixEffect extends StatefulWidget {
  const MatrixEffect({super.key});
  @override State<MatrixEffect> createState() => _MatrixEffectState();
}
class _MatrixEffectState extends State<MatrixEffect> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  final List<double> _y = List.generate(40, (i) => math.Random().nextDouble() * -500);
  final List<int>    _s = List.generate(40, (i) => 3 + math.Random().nextInt(5));
  static const _chars = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ!@#\$%^&*";
  @override void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat();
    _ctrl.addListener(_tick);
  }
  void _tick() {
    for (int i = 0; i < _y.length; i++) {
      _y[i] += _s[i];
      // size невідомий тут — використовуємо велике значення, painter обріже
      if (_y[i] > 2000) _y[i] = math.Random().nextDouble() * -200;
    }
  }
  @override void dispose() { _ctrl.removeListener(_tick); _ctrl.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => AnimatedBuilder(
    animation: _ctrl,
    builder: (_, __) => CustomPaint(painter: _MatrixPainter(List.from(_y), _s, _chars), child: Container()),
  );
}

class _MatrixPainter extends CustomPainter {
  final List<double> yPos; final List<int> speeds; final String chars;
  _MatrixPainter(this.yPos, this.speeds, this.chars);
  @override void paint(Canvas canvas, Size size) {
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..color = Colors.black);
    for (int i = 0; i < yPos.length; i++) {
      double x = i * 20.0; if (x > size.width) break;
      for (int j = 0; j < 12; j++) {
        final char = chars[math.Random().nextInt(chars.length)];
        final tp = TextPainter(
          text: TextSpan(text: char, style: TextStyle(
            color: j == 0 ? Colors.white : Colors.greenAccent.withOpacity(math.max(0, 1 - (j * 0.1))),
            fontSize: 16, fontFamily: 'JetBrainsMono',
          )),
          textDirection: TextDirection.ltr,
        );
        tp.layout(); tp.paint(canvas, Offset(x, yPos[i] - (j * 16)));
      }
    }
  }
  @override bool shouldRepaint(covariant CustomPainter _) => true;
}

class _TopoGridPainter extends CustomPainter {
  @override void paint(Canvas canvas, Size size) {
    final p = Paint()..color = AppColors.uaBlue.withOpacity(0.03)..strokeWidth = 1.0;
    for (double i = 0; i < size.width;  i += 40) canvas.drawLine(Offset(i, 0), Offset(i, size.height), p);
    for (double i = 0; i < size.height; i += 40) canvas.drawLine(Offset(0, i), Offset(size.width, i), p);
  }
  @override bool shouldRepaint(covariant CustomPainter _) => false;
}

// Кільцева діаграма для дашборду
class _DonutPainter extends CustomPainter {
  final Map<String, int> stats;
  final int total;
  const _DonutPainter(this.stats, this.total);

  @override void paint(Canvas canvas, Size size) {
    if (total == 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;
    const strokeW = 18.0;
    const gap     = 0.04; // зазор між сегментами (радіани)

    double startAngle = -math.pi / 2;
    final paint = Paint()..style = PaintingStyle.stroke..strokeWidth = strokeW..strokeCap = StrokeCap.butt;

    for (final entry in stats.entries) {
      if (entry.value == 0) continue;
      final sweep = (entry.value / total) * (2 * math.pi) - gap;
      paint.color = catColor(entry.key);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle, sweep, false, paint,
      );
      startAngle += sweep + gap;
    }

    // Центр — загальна кількість
    final tp = TextPainter(
      text: TextSpan(
        text: '$total',
        style: const TextStyle(color: AppColors.textPri, fontSize: 22, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override bool shouldRepaint(covariant _DonutPainter old) =>
      old.stats != stats || old.total != total;
}

// Тема "Нічний Київ" — намальований силует
class _KyivNightPainter extends CustomPainter {
  @override void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Небо — темно-синій фон
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h),
        Paint()..color = const Color(0xFF020B1A));

    // Зірки
    final starPaint = Paint()..color = Colors.white;
    final rng = math.Random(42); // фіксований seed — зірки завжди на місці
    for (int i = 0; i < 120; i++) {
      final x   = rng.nextDouble() * w;
      final y   = rng.nextDouble() * h * 0.6;
      final r   = rng.nextDouble() * 1.2 + 0.3;
      final opacity = rng.nextDouble() * 0.6 + 0.2;
      canvas.drawCircle(Offset(x, y), r, Paint()..color = Colors.white.withOpacity(opacity));
    }

    // Місяць
    canvas.drawCircle(Offset(w * 0.82, h * 0.12), 22,
        Paint()..color = const Color(0xFFE8D98C).withOpacity(0.9));
    // Тінь місяця (серп)
    canvas.drawCircle(Offset(w * 0.82 + 14, h * 0.12), 18,
        Paint()..color = const Color(0xFF020B1A));

    // Горизонт — силует міста
    final cityPaint = Paint()..color = const Color(0xFF0A1628);
    final city = Path();
    city.moveTo(0, h);

    // Київські силуети — ліва частина
    city.lineTo(0, h * 0.72);
    city.lineTo(w * 0.04, h * 0.72);
    city.lineTo(w * 0.04, h * 0.65);
    city.lineTo(w * 0.06, h * 0.65);
    city.lineTo(w * 0.06, h * 0.68);
    city.lineTo(w * 0.09, h * 0.68);
    city.lineTo(w * 0.09, h * 0.58);
    city.lineTo(w * 0.10, h * 0.55); // шпиль
    city.lineTo(w * 0.11, h * 0.58);
    city.lineTo(w * 0.11, h * 0.68);
    city.lineTo(w * 0.15, h * 0.68);
    city.lineTo(w * 0.15, h * 0.62);
    city.lineTo(w * 0.18, h * 0.62);
    city.lineTo(w * 0.18, h * 0.70);
    city.lineTo(w * 0.22, h * 0.70);
    city.lineTo(w * 0.22, h * 0.60);
    city.lineTo(w * 0.25, h * 0.60);
    city.lineTo(w * 0.25, h * 0.66);

    // Центр — Лавра (купол)
    city.lineTo(w * 0.32, h * 0.66);
    city.lineTo(w * 0.32, h * 0.52);
    // Великий купол
    city.cubicTo(w * 0.35, h * 0.38, w * 0.40, h * 0.38, w * 0.43, h * 0.52);
    city.lineTo(w * 0.43, h * 0.45);
    city.lineTo(w * 0.435, h * 0.40); // хрест
    city.lineTo(w * 0.43, h * 0.45);
    // Малий купол поруч
    city.lineTo(w * 0.46, h * 0.52);
    city.cubicTo(w * 0.47, h * 0.43, w * 0.50, h * 0.43, w * 0.51, h * 0.52);
    city.lineTo(w * 0.51, h * 0.62);

    // Права частина
    city.lineTo(w * 0.55, h * 0.62);
    city.lineTo(w * 0.55, h * 0.55);
    city.lineTo(w * 0.58, h * 0.55);
    city.lineTo(w * 0.58, h * 0.62);
    city.lineTo(w * 0.62, h * 0.62);
    city.lineTo(w * 0.62, h * 0.50);
    city.lineTo(w * 0.63, h * 0.47); // шпиль
    city.lineTo(w * 0.64, h * 0.50);
    city.lineTo(w * 0.64, h * 0.62);
    city.lineTo(w * 0.70, h * 0.62);
    city.lineTo(w * 0.70, h * 0.68);
    city.lineTo(w * 0.75, h * 0.68);
    city.lineTo(w * 0.75, h * 0.60);
    city.lineTo(w * 0.80, h * 0.60);
    city.lineTo(w * 0.80, h * 0.70);
    city.lineTo(w * 0.85, h * 0.70);
    city.lineTo(w * 0.85, h * 0.64);
    city.lineTo(w * 0.90, h * 0.64);
    city.lineTo(w * 0.90, h * 0.70);
    city.lineTo(w, h * 0.70);
    city.lineTo(w, h);
    city.close();
    canvas.drawPath(city, cityPaint);

    // Підсвітка куполів — синьо-жовта
    final glowPaint = Paint()
      ..color = const Color(0xFF0057B7).withOpacity(0.15)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawCircle(Offset(w * 0.375, h * 0.50), 30, glowPaint);

    final glowYellow = Paint()
      ..color = const Color(0xFFE8D98C).withOpacity(0.08)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);
    canvas.drawCircle(Offset(w * 0.375, h * 0.50), 50, glowYellow);

    // Відображення у "воді" внизу
    final reflectPaint = Paint()
      ..color = const Color(0xFF0057B7).withOpacity(0.06);
    canvas.drawRect(Rect.fromLTWH(0, h * 0.80, w, h * 0.20), reflectPaint);

    // Горизонтальні лінії — ефект води
    for (int i = 0; i < 8; i++) {
      final y = h * 0.82 + i * 8.0;
      canvas.drawLine(
        Offset(0, y), Offset(w, y),
        Paint()..color = Colors.white.withOpacity(0.02)..strokeWidth = 1,
      );
    }
  }

  @override bool shouldRepaint(covariant CustomPainter _) => false;
}

class ScrambleText extends StatefulWidget {
  final String text; final TextStyle style;
  const ScrambleText({super.key, required this.text, required this.style});
  @override State<ScrambleText> createState() => _ScrambleTextState();
}
class _ScrambleTextState extends State<ScrambleText> {
  String _disp = ""; Timer? _t;
  @override void initState() {
    super.initState(); int f = 0;
    _t = Timer.periodic(const Duration(milliseconds: 30), (t) {
      if (!mounted) return;
      setState(() {
        f++; _disp = "";
        for (int i = 0; i < widget.text.length; i++) {
          if (f > i + 3) _disp += widget.text[i];
          else _disp += "X#&?@"[math.Random().nextInt(5)];
        }
        if (f > widget.text.length + 10) t.cancel();
      });
    });
  }
  @override void dispose() { _t?.cancel(); super.dispose(); }
  @override Widget build(BuildContext context) => Text(_disp, style: widget.style);
}

// ─────────────────────────────────────────────
// КОРЕНЕВИЙ ВІДЖЕТ
// ─────────────────────────────────────────────
// ─────────────────────────────────────────────
// ЛІЦЕНЗІЙНИЙ ЗАХИСТ
// ─────────────────────────────────────────────

class LicenseGuard {
  static const _salt    = 'Марс Іванович';
  static const _keyPref = 'license_key_v1';
  static const _storage = FlutterSecureStorage();

  // Файл-маркер у папці поруч з exe.
  // Якщо папку видалено — файл зникає — ліцензія анульована.
  static Future<File> _licenseFile() async {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    return File('$exeDir/.lic');
  }

  // Отримуємо Windows MachineGuid з реєстру через Process
  static Future<String> _getWindowsMachineGuid() async {
    try {
      final result = await Process.run('reg', [
        'query',
        r'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Cryptography',
        '/v', 'MachineGuid',
      ]);
      final output = result.stdout as String;
      final match = RegExp(r'MachineGuid\s+REG_SZ\s+(\S+)').firstMatch(output);
      if (match != null) return match.group(1)!.trim();
    } catch (_) {}
    return _fallbackId();
  }

  static Future<String> _expectedKey() async {
    final deviceId = await _getWindowsMachineGuid();
    final hmac = crypto.Hmac(
      crypto.sha256,
      utf8.encode(_salt),
    );
    final digest = hmac.convert(utf8.encode(deviceId));
    final hex = digest.toString().toUpperCase().substring(0, 24);
    return [0,4,8,12,16,20].map((i) => hex.substring(i, i+4)).join('-');
  }

  static Future<String> getDeviceId() async {
    return await _getWindowsMachineGuid();
  }

  static String _fallbackId() {
    // Якщо реєстр недоступний — використовуємо ім'я комп'ютера
    return Platform.localHostname;
  }

  // Перевірка ліцензії:
  // 1. Ключ у flutter_secure_storage має збігатися з очікуваним
  // 2. Файл .lic у папці exe має існувати і містити той самий ключ
  // Якщо папку видалено і перевстановлено — файл .lic відсутній — false
  static Future<bool> check() async {
    try {
      final saved = await _storage.read(key: _keyPref);
      if (saved == null || saved.isEmpty) return false;

      final expected = await _expectedKey();
      if (saved.trim().toUpperCase() != expected.toUpperCase()) return false;

      // Перевіряємо файл у папці застосунку
      final licFile = await _licenseFile();
      if (!licFile.existsSync()) return false;
      final fileKey = licFile.readAsStringSync().trim().toUpperCase();
      if (fileKey != expected.toUpperCase()) return false;

      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> activate(String inputKey) async {
    final expected = await _expectedKey();
    if (inputKey.trim().toUpperCase() == expected.toUpperCase()) {
      final key = inputKey.trim().toUpperCase();
      // Зберігаємо в обох місцях одночасно
      await _storage.write(key: _keyPref, value: key);
      final licFile = await _licenseFile();
      await licFile.writeAsString(key);
      return true;
    }
    return false;
  }
}

// ── Додаток-заглушка при відсутності ліцензії ──

// Відкриття PDF на Windows через стандартну програму
void _openPdfWindows(String path) async {
  try {
    await Process.run('explorer', [path]);
  } catch (e) {
    debugPrint('Cannot open PDF: \$e');
  }
}

class LicenseApp extends StatelessWidget {
  const LicenseApp({super.key});
  @override Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(),
    home: const LicenseScreen(),
  );
}

class LicenseScreen extends StatefulWidget {
  const LicenseScreen({super.key});
  @override State<LicenseScreen> createState() => _LicenseScreenState();
}

class _LicenseScreenState extends State<LicenseScreen> {
  final _keyCtrl = TextEditingController();
  String _deviceId = 'Завантаження...';
  bool _loading = false;
  String _error = '';

  @override void initState() {
    super.initState();
    _loadDeviceId();
  }

  Future<void> _loadDeviceId() async {
    final id = await LicenseGuard.getDeviceId();
    if (mounted) setState(() => _deviceId = id);
  }

  Future<void> _activate() async {
    setState(() { _loading = true; _error = ''; });
    final ok = await LicenseGuard.activate(_keyCtrl.text);
    if (!mounted) return;
    if (ok) {
      // Перезапускаємо додаток
      runApp(const PromptApp());
    } else {
      setState(() {
        _loading = false;
        _error = 'Невірний ключ. Перевірте Device ID та ключ.';
      });
    }
  }

  void _copyDeviceId() {
    Clipboard.setData(ClipboardData(text: _deviceId));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Device ID скопійовано'), duration: Duration(seconds: 2)),
    );
  }

  @override Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF0D1117),
    body: SafeArea(child: Center(child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        // Логотип
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            color: const Color(0xFF005BBB).withOpacity(0.15),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF005BBB), width: 2),
          ),
          child: const Icon(Icons.lock_outline, color: Color(0xFF005BBB), size: 40),
        ),
        const SizedBox(height: 20),
        const Text('АКТИВАЦІЯ ДОДАТКУ', style: TextStyle(
          color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 2,
        )),
        const SizedBox(height: 6),
        const Text('Введіть ліцензійний ключ для цього пристрою',
          style: TextStyle(color: Colors.white38, fontSize: 12),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),

        // Device ID
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Device ID цього пристрою:',
              style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: Text(_deviceId,
                style: const TextStyle(
                  color: Color(0xFFFFD700), fontFamily: 'monospace',
                  fontSize: 13, fontWeight: FontWeight.bold,
                ))),
              IconButton(
                icon: const Icon(Icons.copy, color: Colors.white38, size: 18),
                onPressed: _copyDeviceId,
                tooltip: 'Копіювати',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ]),
          ]),
        ),
        const SizedBox(height: 8),
        const Text('Надішліть цей ID адміністратору для отримання ключа',
          style: TextStyle(color: Colors.white24, fontSize: 10),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),

        // Поле вводу ключа
        TextField(
          controller: _keyCtrl,
          style: const TextStyle(
            color: Colors.white, fontFamily: 'monospace',
            fontSize: 14, letterSpacing: 1,
          ),
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            hintText: 'XXXX-XXXX-XXXX-XXXX-XXXX-XXXX',
            hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
            filled: true,
            fillColor: const Color(0xFF161B22),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Colors.white12),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Colors.white12),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF005BBB), width: 2),
            ),
          ),
          onSubmitted: (_) => _activate(),
        ),
        if (_error.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(_error, style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            textAlign: TextAlign.center),
        ],
        const SizedBox(height: 16),

        // Кнопка активації
        SizedBox(width: double.infinity, child: ElevatedButton(
          onPressed: _loading ? null : _activate,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF005BBB),
            disabledBackgroundColor: Colors.white12,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: _loading
            ? const SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Text('АКТИВУВАТИ', style: TextStyle(
                color: Colors.white, fontSize: 14,
                fontWeight: FontWeight.bold, letterSpacing: 2,
              )),
        )),
      ]),
    ))),
  );
}

class PromptApp extends StatelessWidget {
  const PromptApp({super.key});
  @override Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isMatrixMode,
      builder: (_, matrix, __) => ValueListenableBuilder<bool>(
      valueListenable: isKyivMode,
      builder: (_, kyiv, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: AppColors.bg,
          fontFamily: 'JetBrainsMono',
          appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, elevation: 0),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: matrix ? Colors.black87 : AppColors.bgCard,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: matrix ? const BorderSide(color: Colors.green) : BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: matrix ? const BorderSide(color: Colors.green) : const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: matrix ? const BorderSide(color: Colors.greenAccent, width: 2) : const BorderSide(color: AppColors.uaBlue, width: 2),
            ),
            labelStyle: TextStyle(color: matrix ? Colors.greenAccent : AppColors.textSec),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.uaBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              minimumSize: const Size(double.infinity, 50),
            ),
          ),
        ),
        home: const SplashScreen(),
      ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// СПЛЕШ ЕКРАН
// ─────────────────────────────────────────────
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override State<SplashScreen> createState() => _SplashScreenState();
}
class _SplashScreenState extends State<SplashScreen> {
  @override void initState() {
    super.initState();
    Timer(const Duration(milliseconds: 1800), () {
      if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainScreen()));
    });
  }
  @override Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: SizedBox.expand(child: Image.asset('assets/splash.png', fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text('🔱', style: TextStyle(fontSize: 64)),
        SizedBox(height: 16),
        Text('ПРОМПТАРНЯ', style: TextStyle(color: AppColors.uaYellow, fontSize: 22, letterSpacing: 4)),
      ])),
    )),
  );
}

// ─────────────────────────────────────────────
// ГОЛОВНИЙ ЕКРАН
// ─────────────────────────────────────────────
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override State<MainScreen> createState() => _MainScreenState();
}
class _MainScreenState extends State<MainScreen> with TickerProviderStateMixin {
  late TabController _tc;
  List<Prompt> prompts = []; List<PDFDoc> docs = []; List<String> logs = [];
  bool _searchActive = false;
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();
  // Анімація цифр на HOME
  late AnimationController _countCtrl;
  late Animation<double> _countAnim;
  // Parallax
  final _scrollCtrl = ScrollController();
  double _scrollOffset = 0;

  // Tutorial keys
  final _keyTabs = GlobalKey();
  final _keySearch = GlobalKey();
  final _keyMenu = GlobalKey();
  final _keyFab = GlobalKey();

  // Пасхалка
  int _easterTaps = 0;

  static const cats = ['HOME', 'ФО', 'ЮО', 'ГЕОІНТ', 'МОНІТОРИНГ', 'ЗВІТИ', 'ІНШІ', 'ІНСТРУМЕНТИ', 'ДОКУМЕНТИ'];

  // Адаптивний колір AppBar по вкладці
  static const _tabColors = {
    'HOME':        Color(0xFF040B16),
    'ФО':          Color(0xFF0A1628),
    'ЮО':          Color(0xFF1A1200),
    'ГЕОІНТ':      Color(0xFF0A1A0A),
    'МОНІТОРИНГ':  Color(0xFF1A0E00),
    'ІНШІ':        Color(0xFF120A1A),
    'ЗВІТИ':       Color(0xFF0A1A1A),
    'ІНСТРУМЕНТИ': Color(0xFF040B16),
    'ДОКУМЕНТИ':   Color(0xFF040B16),
  };
  Color get _currentTabColor => _tabColors[cats[_tc.index]] ?? AppColors.bg;

  @override void initState() {
    super.initState();
    _tc = TabController(length: cats.length, vsync: this, initialIndex: 1);
    _tc.addListener(() { if (mounted) setState(() {}); });
    _countCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _countAnim = CurvedAnimation(parent: _countCtrl, curve: Curves.easeOutCubic);
    _scrollCtrl.addListener(() {
      if (mounted) setState(() => _scrollOffset = _scrollCtrl.offset);
    });
    _load();
    _checkFirstLaunch();
  }

  void _checkFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool('tutorial_seen') ?? false;
    if (!seen) {
      // Даємо UI час побудуватись
      await Future.delayed(const Duration(milliseconds: 1500));
      if (!mounted) return;
      _showTutorial();
    }
  }

  void _showTutorial() {
    final targets = <TargetFocus>[
      TargetFocus(
        identify: 'tabs',
        keyTarget: _keyTabs,
        alignSkip: Alignment.bottomCenter,
        shape: ShapeLightFocus.RRect,
        radius: 8,
        contents: [TargetContent(
          align: ContentAlign.bottom,
          child: _tutorialCard(
            '📋 ВКЛАДКИ КАТЕГОРІЙ',
            'Промпти розділені на категорії: ФО, ЮО, ГЕОІНТ, МОНІТОРИНГ, ІНШІ та ІНСТРУМЕНТИ.\n\nПереключайте свайпом або тапом. Натисніть де завгодно щоб продовжити.',
          ),
        )],
      ),
      TargetFocus(
        identify: 'search',
        keyTarget: _keySearch,
        alignSkip: Alignment.bottomCenter,
        contents: [TargetContent(
          align: ContentAlign.bottom,
          child: _tutorialCard(
            '🔍 ПОШУК',
            'Знайдіть потрібний промпт за назвою або текстом. Пошук працює по всіх категоріях одночасно.',
          ),
        )],
      ),
      TargetFocus(
        identify: 'menu',
        keyTarget: _keyMenu,
        alignSkip: Alignment.bottomCenter,
        contents: [TargetContent(
          align: ContentAlign.bottom,
          child: _tutorialCard(
            '⋯ МЕНЮ',
            'Імпорт промптів з TXT-файлу, бекап (локальний та портативний для іншого пристрою), журнал дій, статистика, режим Matrix.',
          ),
        )],
      ),
      TargetFocus(
        identify: 'fab',
        keyTarget: _keyFab,
        alignSkip: Alignment.topCenter,
        contents: [TargetContent(
          align: ContentAlign.top,
          child: _tutorialCard(
            '➕ НОВИЙ ПРОМПТ',
            'Створіть власний промпт або імпортуйте готовий набір через меню. Використовуйте {ЗМІННІ} в фігурних дужках.',
          ),
        )],
      ),
    ];

    TutorialCoachMark(
      targets: targets,
      colorShadow: Colors.black,
      opacityShadow: 0.85,
      textSkip: 'ПРОПУСТИТИ',
      textStyleSkip: const TextStyle(color: AppColors.uaYellow, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1),
      paddingFocus: 6,
      onFinish: () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('tutorial_seen', true);
      },
      onSkip: () {
        SharedPreferences.getInstance().then((prefs) => prefs.setBool('tutorial_seen', true));
        return true;
      },
    ).show(context: context);
  }

  Widget _tutorialCard(String title, String body) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard.withOpacity(0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.uaYellow.withOpacity(0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(title, style: const TextStyle(color: AppColors.uaYellow, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
        const SizedBox(height: 8),
        Text(body, style: const TextStyle(color: AppColors.textPri, fontSize: 13, height: 1.4)),
        const SizedBox(height: 8),
        const Align(alignment: Alignment.centerRight, child: Text('ТАП → ДАЛІ', style: TextStyle(color: AppColors.textHint, fontSize: 10, letterSpacing: 1))),
      ]),
    );
  }

  void _startCountAnim() {
    _countCtrl.reset();
    _countCtrl.forward();
  }

  @override void dispose() {
    _tc.dispose(); _searchCtrl.dispose();
    _countCtrl.dispose(); _scrollCtrl.dispose();
    super.dispose();
  }

  static final _uuid = Uuid();
  String _uid() => _uuid.v4();

  void _load() async {
    try {
      final db = DatabaseHelper.instance;
      final dbPrompts = await db.getPrompts();
      final dbDocs    = await db.getDocs();
      final dbLogs    = await db.getLogs();
      if (!mounted) return;
      setState(() {
        prompts = dbPrompts.map((p) => Prompt(
          id: p.id, title: p.title, content: p.content,
          category: p.category, isFavorite: p.isFavorite,
          useCount: p.useCount, lastUsed: p.lastUsed,
          ratingSum: p.ratingSum, ratingCount: p.ratingCount,
        )).toList();
        docs = dbDocs.map((d) => PDFDoc(id: d.id, name: d.name, path: d.path)).toList();
        logs = dbLogs;
        // Стартовий набір не створюється — користувач імпортує промпти через Імпорт TXT
      });
      _startCountAnim();
    } catch (e) {
      debugPrint('DB LOAD ERROR: $e');
      if (!mounted) return;
      setState(() {
        prompts = [];
        docs = [];
        logs = ['⚠ Помилка завантаження бази: $e'];
      });
      _startCountAnim();
    }
  }

  // _save() більше не потрібен глобально.
  // Залишаємо порожнім для сумісності.
  void _save() {}

  void _log(String a) {
    if (!mounted) return;
    final now = DateTime.now();
    final ts = "[${now.day.toString().padLeft(2,'0')}.${now.month.toString().padLeft(2,'0')} ${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}]";
    final msg = "$ts $a";
    setState(() { logs.insert(0, msg); if (logs.length > 100) logs.removeLast(); });
    DatabaseHelper.instance.insertLog(msg);
  }


  // ── Крипто хелпери ──────────────────────────────────
  // Новий V3: HMAC-SHA256 keystream XOR (кросплатформний)
  static List<int> _xorWithHmacStream(List<int> data, List<int> key) {
    final result = <int>[];
    int blockIdx = 0;
    List<int> keystream = [];
    int posInBlock = 0;
    for (int i = 0; i < data.length; i++) {
      if (posInBlock >= keystream.length) {
        // Генеруємо наступний блок keystream
        final counter = utf8.encode(blockIdx.toString());
        final hmac = crypto.Hmac(crypto.sha256, key);
        keystream = hmac.convert([...key, ...counter]).bytes;
        blockIdx++;
        posInBlock = 0;
      }
      result.add(data[i] ^ keystream[posInBlock]);
      posInBlock++;
    }
    return result;
  }

  // Старий V2: сумісність з Android-бекапами
  static List<int> _xorV2Legacy(List<int> encrypted, List<int> passBytes) {
    // Використовуємо той самий алгоритм що на Android (з маскуванням до 32 біт)
    int hash = 0x5A5A5A5A;
    for (int i = 0; i < passBytes.length; i++) {
      hash = ((hash * 33) + passBytes[i]) & 0xFFFFFFFF;
    }
    final decrypted = <int>[];
    int seed = hash;
    for (int i = 0; i < encrypted.length; i++) {
      seed = ((seed * 1103515245 + 12345) & 0x7FFFFFFF);
      decrypted.add(encrypted[i] ^ (seed & 0xFF));
    }
    return decrypted;
  }

  void _import() async {
    FilePickerResult? r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['txt']);
    if (r == null || r.files.single.path == null) return;
    try {
      // Читаємо як байти і декодуємо з підтримкою UTF-8 і Windows-1251
      final bytes = await File(r.files.single.path!).readAsBytes();
      String c;
      try {
        c = utf8.decode(bytes);
      } catch (_) {
        // Fallback: Latin-1 (покриває Windows-1251 частково)
        c = String.fromCharCodes(bytes);
      }
      List<Prompt> imp = [];
      for (var b in c.split('===')) {
        if (b.trim().isEmpty) continue;
        String cat = 'ІНШІ', title = 'БЕЗ НАЗВИ', text = ''; bool isT = false;
        for (var l in b.trim().split('\n')) {
          String lw = l.toLowerCase().trim();
          if (lw.startsWith('категорія:')) {
            String raw = l.substring(10).trim().toUpperCase();
            if (raw.contains('ФІЗ') || raw == 'ФО') cat = 'ФО';
            else if (raw.contains('ЮР') || raw == 'ЮО') cat = 'ЮО';
            else if (raw.contains('ГЕО')) cat = 'ГЕОІНТ';
            else if (raw.contains('ЗВІТ')) cat = 'ЗВІТИ';
            else if (raw.contains('МОНІТОР')) cat = 'МОНІТОРИНГ';
            else if (raw.contains('ІНШ')) cat = 'ІНШІ';
            else cat = 'ІНШІ';
          } else if (lw.startsWith('назва:')) { title = l.substring(6).trim(); }
            else if (lw.startsWith('текст:')) { text = l.substring(6).trim(); isT = true; }
            else if (isT) text += "\n$l";
        }
        if (text.isNotEmpty && title.isNotEmpty) imp.add(Prompt(id: _uid(), title: title, content: text.trim(), category: cat));
      }
      if (!mounted) return;
      if (imp.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Промптів не знайдено. Перевірте формат файлу (Категорія:/Назва:/Текст:)'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 4),
        ));
        return;
      }

      // Перевірка дублікатів
      int duplicates = 0;
      final toImport = <Prompt>[];
      for (final p in imp) {
        final existing = prompts.where((e) => _similarity(e.title, p.title) > 0.8 || _similarity(e.content, p.content) > 0.85);
        if (existing.isNotEmpty) {
          duplicates++;
        } else {
          toImport.add(p);
        }
      }

      // Якщо є дублікати — запитуємо
      if (duplicates > 0) {
        final action = await showDialog<String>(context: context, builder: (_) => AlertDialog(
          backgroundColor: AppColors.bgCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.border)),
          title: const Text('ЗНАЙДЕНО ДУБЛІКАТИ', style: TextStyle(fontSize: 15, color: AppColors.uaYellow)),
          content: Text('${imp.length} промптів у файлі.\n$duplicates схожих вже є в базі.\n${toImport.length} нових.', style: const TextStyle(fontSize: 13, color: AppColors.textSec)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, 'cancel'), child: const Text('СКАСУВАТИ', style: TextStyle(color: AppColors.textSec))),
            TextButton(onPressed: () => Navigator.pop(context, 'new_only'), child: const Text('ТІЛЬКИ НОВІ', style: TextStyle(color: AppColors.accent))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.uaBlue),
              onPressed: () => Navigator.pop(context, 'all'),
              child: const Text('ІМПОРТ УСІХ'),
            ),
          ],
        ));
        if (action == 'cancel' || action == null) return;
        if (action == 'new_only') {
          imp = toImport;
        }
        // action == 'all' — імпортуємо все
      }

      final db = DatabaseHelper.instance;
      for (int i = 0; i < imp.length; i++) {
        await db.insertPrompt(DbPrompt(
          id: imp[i].id, title: imp[i].title,
          content: imp[i].content, category: imp[i].category,
        ), sortOrder: prompts.length + i);
      }
      setState(() => prompts.addAll(imp));
      _log("Імпортовано: ${imp.length} записів з TXT${duplicates > 0 ? ' ($duplicates дублікатів)' : ''}");
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Імпортовано ${imp.length} промптів${duplicates > 0 ? ' (пропущено $duplicates дублікатів)' : ''}', style: const TextStyle(color: Colors.greenAccent)),
        backgroundColor: AppColors.bgCard,
      ));
    } catch(e) {
      _log("Помилка імпорту TXT: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Помилка імпорту: $e'),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
      ));
    }
  }

  // Порівняння схожості рядків (Jaccard на словах)
  double _similarity(String a, String b) {
    final wa = a.toLowerCase().split(RegExp(r'\s+')).toSet();
    final wb = b.toLowerCase().split(RegExp(r'\s+')).toSet();
    if (wa.isEmpty || wb.isEmpty) return 0;
    return wa.intersection(wb).length / wa.union(wb).length;
  }

  // ── БЕКАП: ЕКСПОРТ (зашифрований JSON) ──
  void _backupExport() async {
    try {
      final allPrompts = prompts.map((p) => p.toJson()).toList();
      final allDocs = docs.map((d) => d.toJson()).toList();
      final timeline = await DatabaseHelper.instance.getTimeline();
      final timelineJson = timeline.map((e) => {'id': e.id, 'date': e.date, 'description': e.description}).toList();

      final backup = {
        'version': 1,
        'created': DateTime.now().toIso8601String(),
        'prompts': allPrompts,
        'docs': allDocs,
        'timeline': timelineJson,
      };

      final jsonStr = jsonEncode(backup);
      final encrypted = await CryptoHelper.instance.encrypt(jsonStr);

      final dir = await getApplicationDocumentsDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final file = File('${dir.path}/ukr_osint_backup_$ts.bak');
      await file.writeAsString(encrypted);

      // Бекап збережено локально (Windows версія)
      _log("Бекап: експортовано ${allPrompts.length} промптів, ${timelineJson.length} подій");

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Бекап створено: ${allPrompts.length} промптів', style: const TextStyle(color: Colors.greenAccent)),
        backgroundColor: AppColors.bgCard,
      ));
    } catch (e) {
      _log("Помилка бекапу: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Помилка створення бекапу'), backgroundColor: Colors.red));
    }
  }

  // ── ПОРТАТИВНИЙ БЕКАП (для переносу між пристроями) ──
  void _portableExport() async {
    // Запитуємо пароль у користувача
    final passCtrl = TextEditingController();
    final password = await showDialog<String>(context: context, builder: (_) => AlertDialog(
      backgroundColor: AppColors.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.uaBlue, width: 0.5)),
      title: const Text('ПАРОЛЬ ДЛЯ БЕКАПУ', style: TextStyle(fontSize: 15, color: AppColors.textPri)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Цей пароль потрібен для відновлення на іншому пристрої. Запам\'ятайте його!', style: TextStyle(fontSize: 12, color: AppColors.textSec)),
        const SizedBox(height: 12),
        TextField(controller: passCtrl, obscureText: true, style: const TextStyle(color: AppColors.textPri),
          decoration: const InputDecoration(labelText: 'Пароль (мін. 4 символи)')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('СКАСУВАТИ', style: TextStyle(color: AppColors.textSec))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.uaBlue),
          onPressed: () {
            if (passCtrl.text.length >= 4) Navigator.pop(context, passCtrl.text);
          },
          child: const Text('ЕКСПОРТ'),
        ),
      ],
    ));
    if (password == null || password.length < 4) return;

    try {
      final allPrompts = prompts.map((p) => p.toJson()).toList();
      final timeline = await DatabaseHelper.instance.getTimeline();
      final timelineJson = timeline.map((e) => {'id': e.id, 'date': e.date, 'description': e.description}).toList();

      final backup = {
        'version': 2,
        'type': 'portable',
        'created': DateTime.now().toIso8601String(),
        'prompts': allPrompts,
        'timeline': timelineJson,
      };

      final jsonStr = jsonEncode(backup);
      // Шифруємо паролем користувача через PBKDF2-подібний підхід
      // Використовуємо простий XOR з хешем пароля для портативності
      final passBytes = utf8.encode(password);
      final dataBytes = utf8.encode(jsonStr);
      // Створюємо ключ з пароля (SHA-256 подібний)
      int hash = 0x5A5A5A5A;
      for (int i = 0; i < passBytes.length; i++) {
        hash = ((hash << 5) + hash + passBytes[i]) & 0xFFFFFFFF;
      }
      // XOR кожен байт з потоком з хешу
      final encrypted = <int>[];
      int seed = hash;
      for (int i = 0; i < dataBytes.length; i++) {
        seed = ((seed * 1103515245 + 12345) & 0x7FFFFFFF);
        encrypted.add(dataBytes[i] ^ (seed & 0xFF));
      }
      // Зберігаємо як base64 з маркером
      final payload = 'PROMPTARNYA_V2:${base64Encode(encrypted)}';

      final dir = await getApplicationDocumentsDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final file = File('${dir.path}/promptarnya_portable_$ts.pbak');
      await file.writeAsString(payload);

      // Портативний бекап збережено локально (Windows версія)
      _log("Портативний бекап: ${allPrompts.length} промптів");

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Портативний бекап: ${allPrompts.length} промптів', style: const TextStyle(color: Colors.greenAccent)),
        backgroundColor: AppColors.bgCard,
      ));
    } catch (e) {
      _log("Помилка портативного бекапу: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Помилка створення бекапу'), backgroundColor: Colors.red));
    }
  }

  void _portableImport() async {
    FilePickerResult? r = await FilePicker.platform.pickFiles(type: FileType.any);
    if (r == null || r.files.single.path == null) return;

    final fileContent = await File(r.files.single.path!).readAsString();

    // Перевіряємо чи це портативний формат
    if (!fileContent.startsWith('PROMPTARNYA_V2:') && !fileContent.startsWith('PROMPTARNYA_V3:')) {
      // Спробуємо як старий формат (device-locked)
      _backupImport();
      return;
    }

    // Запитуємо пароль
    final passCtrl = TextEditingController();
    if (!mounted) return;
    final password = await showDialog<String>(context: context, builder: (_) => AlertDialog(
      backgroundColor: AppColors.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.uaBlue, width: 0.5)),
      title: const Text('ПАРОЛЬ БЕКАПУ', style: TextStyle(fontSize: 15, color: AppColors.textPri)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Введіть пароль який використовувався при створенні бекапу.', style: TextStyle(fontSize: 12, color: AppColors.textSec)),
        const SizedBox(height: 12),
        TextField(controller: passCtrl, obscureText: true, style: const TextStyle(color: AppColors.textPri),
          decoration: const InputDecoration(labelText: 'Пароль')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('СКАСУВАТИ', style: TextStyle(color: AppColors.textSec))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.uaBlue),
          onPressed: () => Navigator.pop(context, passCtrl.text),
          child: const Text('РОЗШИФРУВАТИ'),
        ),
      ],
    ));
    if (password == null || password.isEmpty) return;

    try {
      // Підтримуємо V2 (старий Android) і V3 (новий кросплатформний)
      final prefixLen = fileContent.startsWith('PROMPTARNYA_V3:') ? 'PROMPTARNYA_V3:'.length : 'PROMPTARNYA_V2:'.length;
      final b64 = fileContent.substring(prefixLen);
      final encrypted = base64Decode(b64);

      // Дешифруємо через HMAC-SHA256
      final passBytes = utf8.encode(password);
      List<int> decrypted;
      if (fileContent.startsWith('PROMPTARNYA_V3:')) {
        decrypted = _xorWithHmacStream(encrypted, passBytes);
      } else {
        // V2 — старий алгоритм для сумісності з Android-бекапами
        decrypted = _xorV2Legacy(encrypted, passBytes);
      }

      final jsonStr = utf8.decode(decrypted);
      final backup = jsonDecode(jsonStr) as Map<String, dynamic>;

      final importedPrompts = (backup['prompts'] as List? ?? [])
          .map((j) => Prompt.fromJson(j as Map<String, dynamic>))
          .toList();
      final importedTimeline = (backup['timeline'] as List? ?? [])
          .map((j) => j as Map<String, dynamic>)
          .toList();

      if (!mounted) return;
      final confirmed = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.uaBlue, width: 0.5)),
        title: const Text('ВІДНОВЛЕННЯ З БЕКАПУ', style: TextStyle(fontSize: 15, color: AppColors.textPri)),
        content: Text('Знайдено:\n• ${importedPrompts.length} промптів\n• ${importedTimeline.length} подій\n\nІснуючі записи з тими ж ID будуть оновлені.',
          style: const TextStyle(fontSize: 13, color: AppColors.textSec)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('СКАСУВАТИ', style: TextStyle(color: AppColors.textSec))),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: AppColors.uaBlue), onPressed: () => Navigator.pop(context, true), child: const Text('ВІДНОВИТИ')),
        ],
      ));
      if (confirmed != true) return;

      final db = DatabaseHelper.instance;
      for (int i = 0; i < importedPrompts.length; i++) {
        final p = importedPrompts[i];
        await db.insertPrompt(DbPrompt(id: p.id, title: p.title, content: p.content,
          category: p.category, isFavorite: p.isFavorite,
          useCount: p.useCount, lastUsed: p.lastUsed,
          ratingSum: p.ratingSum, ratingCount: p.ratingCount,
        ), sortOrder: i);
      }
      for (final t in importedTimeline) {
        await db.insertTimelineEvent(DbTimelineEvent(
          id: t['id'] as String, date: t['date'] as String, description: t['description'] as String));
      }

      final freshPrompts = await db.getPrompts();
      if (!mounted) return;
      setState(() {
        prompts.clear();
        prompts.addAll(freshPrompts.map((dp) => Prompt(
          id: dp.id, title: dp.title, content: dp.content,
          category: dp.category, isFavorite: dp.isFavorite,
          useCount: dp.useCount, lastUsed: dp.lastUsed,
          ratingSum: dp.ratingSum, ratingCount: dp.ratingCount,
        )));
      });

      _log("Портативний імпорт: ${importedPrompts.length} промптів");
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Відновлено: ${importedPrompts.length} промптів', style: const TextStyle(color: Colors.greenAccent)),
        backgroundColor: AppColors.bgCard,
      ));
    } catch (e) {
      _log("Помилка імпорту: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Невірний пароль або пошкоджений файл'), backgroundColor: Colors.red));
    }
  }

  // ── БЕКАП: ІМПОРТ (зашифрований JSON) ──
  void _backupImport() async {
    FilePickerResult? r = await FilePicker.platform.pickFiles(type: FileType.any);
    if (r == null || r.files.single.path == null) return;
    try {
      final encrypted = await File(r.files.single.path!).readAsString();
      final jsonStr = await CryptoHelper.instance.decrypt(encrypted);
      final backup = jsonDecode(jsonStr) as Map<String, dynamic>;

      final importedPrompts = (backup['prompts'] as List? ?? [])
          .map((j) => Prompt.fromJson(j as Map<String, dynamic>))
          .toList();
      final importedTimeline = (backup['timeline'] as List? ?? [])
          .map((j) => j as Map<String, dynamic>)
          .toList();

      if (!mounted) return;

      // Підтвердження
      final confirmed = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.uaBlue, width: 0.5)),
        title: const Text('ВІДНОВЛЕННЯ З БЕКАПУ', style: TextStyle(fontSize: 15, color: AppColors.textPri)),
        content: Text(
          'Знайдено:\n• ${importedPrompts.length} промптів\n• ${importedTimeline.length} подій хронології\n\nІснуючі записи з тими ж ID будуть перезаписані.',
          style: const TextStyle(fontSize: 13, color: AppColors.textSec),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('СКАСУВАТИ', style: TextStyle(color: AppColors.textSec))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.uaBlue),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ВІДНОВИТИ'),
          ),
        ],
      ));

      if (confirmed != true) return;

      final db = DatabaseHelper.instance;
      for (int i = 0; i < importedPrompts.length; i++) {
        final p = importedPrompts[i];
        await db.insertPrompt(DbPrompt(
          id: p.id, title: p.title, content: p.content,
          category: p.category, isFavorite: p.isFavorite,
        ), sortOrder: i);
      }
      for (final t in importedTimeline) {
        await db.insertTimelineEvent(DbTimelineEvent(
          id: t['id'] as String, date: t['date'] as String,
          description: t['description'] as String,
        ));
      }

      // Оновлюємо стан
      final freshPrompts = await db.getPrompts();
      if (!mounted) return;
      setState(() {
        prompts.clear();
        prompts.addAll(freshPrompts.map((dp) => Prompt(
          id: dp.id, title: dp.title, content: dp.content,
          category: dp.category, isFavorite: dp.isFavorite,
          useCount: dp.useCount, lastUsed: dp.lastUsed,
          ratingSum: dp.ratingSum, ratingCount: dp.ratingCount,
        )));
      });

      _log("Бекап: імпортовано ${importedPrompts.length} промптів, ${importedTimeline.length} подій");
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Відновлено: ${importedPrompts.length} промптів', style: const TextStyle(color: Colors.greenAccent)),
        backgroundColor: AppColors.bgCard,
      ));
    } catch (e) {
      _log("Помилка імпорту бекапу: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Помилка: невірний файл або інший ключ шифрування'),
        backgroundColor: Colors.red,
      ));
    }
  }

  void _addP({Prompt? p}) {
    final tC = TextEditingController(text: p?.title ?? '');
    final cC = TextEditingController(text: p?.content ?? '');
    String sC = (p != null && ['ФО','ЮО','ГЕОІНТ','МОНІТОРИНГ','ЗВІТИ','ІНШІ'].contains(p.category)) ? p.category : 'ФО';
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (c, setS) => AlertDialog(
      backgroundColor: isMatrixMode.value ? Colors.black87 : AppColors.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: isMatrixMode.value ? Colors.green : AppColors.uaBlue, width: 0.5)),
      title: Text(p == null ? 'НОВИЙ ЗАПИС' : 'РЕДАГУВАННЯ', style: TextStyle(color: isMatrixMode.value ? Colors.greenAccent : AppColors.textPri, fontWeight: FontWeight.w500, letterSpacing: 1.5, fontSize: 15)),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(dropdownColor: AppColors.bgCard, isExpanded: true, value: sC,
          items: ['ФО','ЮО','ГЕОІНТ','МОНІТОРИНГ','ЗВІТИ','ІНШІ'].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
          onChanged: (v) => setS(() => sC = v!)),
        const SizedBox(height: 10),
        TextField(controller: tC, style: const TextStyle(color: AppColors.textPri), decoration: const InputDecoration(labelText: 'НАЗВА')),
        const SizedBox(height: 10),
        TextField(controller: cC, maxLines: 4, style: const TextStyle(color: AppColors.textPri, fontSize: 13), decoration: const InputDecoration(labelText: 'ЗМІСТ {VAR}')),
      ])),
      actions: [
        if (p != null) TextButton(
          onPressed: () async {
            Navigator.pop(ctx);
            setState(() { p.title = "█████████"; p.content = "████████████████"; });
            HapticFeedback.heavyImpact();
            await Future.delayed(const Duration(milliseconds: 600));
            if (!mounted) return;
            setState(() => prompts.remove(p));
            await DatabaseHelper.instance.deletePrompt(p.id);
          },
          child: const Text('ВИДАЛИТИ', style: TextStyle(color: Colors.redAccent)),
        ),
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text('СКАСУВАТИ', style: TextStyle(color: isMatrixMode.value ? Colors.green : AppColors.textSec))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: isMatrixMode.value ? Colors.green.withOpacity(0.2) : AppColors.uaBlue),
          onPressed: () {
            if (tC.text.trim().isEmpty) return;
            setState(() {
              if (p == null) {
                final np = Prompt(id: _uid(), title: tC.text.trim(), content: cC.text.trim(), category: sC);
                prompts.add(np);
                DatabaseHelper.instance.insertPrompt(DbPrompt(id: np.id, title: np.title, content: np.content, category: np.category, isFavorite: np.isFavorite));
                _log("Створено: ${tC.text.trim()}");
              } else {
                p.title = tC.text.trim(); p.content = cC.text.trim(); p.category = sC;
                DatabaseHelper.instance.updatePrompt(DbPrompt(id: p.id, title: p.title, content: p.content, category: p.category, isFavorite: p.isFavorite));
                _log("Оновлено: ${tC.text.trim()}");
              }
            });
            Navigator.pop(ctx);
          },
          child: Text('ЗБЕРЕГТИ', style: TextStyle(color: isMatrixMode.value ? Colors.greenAccent : Colors.white)),
        ),
      ],
    )));
  }

  void _showCompareSelector(Prompt source) {
    // Показуємо список промптів з тієї ж категорії для порівняння
    final candidates = prompts.where((p) => p.id != source.id && p.category == source.category).toList();
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Немає інших промптів у цій категорії для порівняння'),
        backgroundColor: AppColors.bgCard,
      ));
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(12),
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.uaBlue.withOpacity(0.3)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Text('ПОРІВНЯТИ «${source.title}» З:', style: const TextStyle(fontSize: 13, color: AppColors.uaYellow, letterSpacing: 0.5, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          const Divider(color: AppColors.border, height: 0),
          Flexible(child: ListView.builder(
            shrinkWrap: true,
            itemCount: candidates.length,
            itemBuilder: (_, i) => ListTile(
              dense: true,
              leading: Icon(Icons.description_outlined, color: catColor(candidates[i].category), size: 18),
              title: Text(candidates[i].title, style: const TextStyle(fontSize: 12, color: AppColors.textPri)),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => DiffScreen(a: source, b: candidates[i]),
                ));
              },
            ),
          )),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  void _pickPDF() async {
    FilePickerResult? r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    if (r == null || r.files.single.path == null) return;
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/${DateTime.now().millisecondsSinceEpoch}_${r.files.single.name}';
    await File(r.files.single.path!).copy(path);
    if (!mounted) return;
    final newDoc = PDFDoc(id: _uid(), name: r.files.single.name, path: path);
    setState(() => docs.add(newDoc));
    await DatabaseHelper.instance.insertDoc(DbDoc(id: newDoc.id, name: newDoc.name, path: newDoc.path));
    _log("Додано документ: ${r.files.single.name}");
  }

  List<Prompt> _filtered(String cat) {
    var items = prompts.where((p) => p.category == cat).toList();
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      items = items.where((p) => p.title.toLowerCase().contains(q) || p.content.toLowerCase().contains(q)).toList();
    }
    items.sort((a, b) => (b.isFavorite ? 1 : 0).compareTo(a.isFavorite ? 1 : 0));
    return items;
  }

  // ── APPBAR ──
  PreferredSizeWidget _appBar() {
    final m = isMatrixMode.value;
    if (_searchActive) return AppBar(
      leading: IconButton(icon: Icon(Icons.arrow_back, color: m ? Colors.greenAccent : AppColors.textSec), onPressed: () => setState(() { _searchActive = false; _searchQuery = ''; _searchCtrl.clear(); })),
      title: TextField(
        controller: _searchCtrl, autofocus: true,
        style: TextStyle(color: m ? Colors.greenAccent : AppColors.textPri, fontSize: 15),
        decoration: const InputDecoration(hintText: 'Пошук...', border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, filled: false),
        onChanged: (v) => setState(() => _searchQuery = v),
      ),
      bottom: _tabBar(),
    );

    return AppBar(
      title: GestureDetector(
        onTap: () {
          _easterTaps++;
          if (_easterTaps >= 5) {
            _easterTaps = 0;
            HapticFeedback.heavyImpact();
            {}; // Гра недоступна у Windows версії
          }
        },
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('🔱', style: TextStyle(fontSize: 20, color: m ? Colors.greenAccent : AppColors.uaYellow)),
          const SizedBox(width: 8),
          Text('ПРОМПТАРНЯ', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2.5, fontSize: 17, color: m ? Colors.greenAccent : AppColors.uaYellow)),
        ]),
      ),
      actions: [
        // Пошук
        IconButton(
          key: _keySearch,
          icon: Icon(Icons.search, color: m ? Colors.greenAccent : AppColors.textSec, size: 22),
          onPressed: () => setState(() => _searchActive = true),
        ),
        // Тема Київ
        IconButton(
          icon: Icon(
            isKyivMode.value ? Icons.location_city : Icons.location_city_outlined,
            color: isKyivMode.value ? AppColors.uaYellow : Colors.white38,
            size: 22,
          ),
          onPressed: () { isKyivMode.value = !isKyivMode.value; HapticFeedback.mediumImpact(); },
          tooltip: 'Тема Київ',
        ),
        // Три крапки — решта в меню
        PopupMenuButton<String>(
          key: _keyMenu,
          icon: Icon(Icons.more_vert, color: m ? Colors.greenAccent : AppColors.textSec, size: 22),
          color: AppColors.bgCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: AppColors.border)),
          onSelected: (val) {
            if (val == 'stats')  _showStats();
            if (val == 'logs')   _showLogs();
            if (val == 'import') _import();
            if (val == 'backup_export') _backupExport();
            if (val == 'backup_import') _backupImport();
            if (val == 'portable_export') _portableExport();
            if (val == 'portable_import') _portableImport();
            if (val == 'matrix') { isMatrixMode.value = !isMatrixMode.value; HapticFeedback.vibrate(); }
          },
          itemBuilder: (_) => [
            PopupMenuItem(value: 'stats',  child: _menuItem(Icons.analytics,    'Статистика',       AppColors.uaYellow)),
            PopupMenuItem(value: 'logs',   child: _menuItem(Icons.receipt_long, 'Журнал дій',       AppColors.textSec)),
            PopupMenuItem(value: 'import', child: _menuItem(Icons.download,     'Імпорт TXT',       AppColors.accent)),
            const PopupMenuDivider(),
            PopupMenuItem(value: 'backup_export', child: _menuItem(Icons.backup,         'Бекап (цей пристрій)',  AppColors.success)),
            PopupMenuItem(value: 'backup_import', child: _menuItem(Icons.restore,        'Відновити (цей пристрій)',   AppColors.accent)),
            const PopupMenuDivider(),
            PopupMenuItem(value: 'portable_export', child: _menuItem(Icons.share,     'Бекап (на інший пристрій)',  AppColors.uaYellow)),
            PopupMenuItem(value: 'portable_import', child: _menuItem(Icons.move_to_inbox, 'Імпорт з іншого пристрою', AppColors.uaYellow)),
            const PopupMenuDivider(),
            PopupMenuItem(value: 'matrix', child: _menuItem(Icons.terminal,     'Режим Matrix',     Colors.greenAccent)),
          ],
        ),
      ],
      bottom: _tabBar(),
    );
  }

  Widget _menuItem(IconData icon, String label, Color color) => Row(children: [
    Icon(icon, size: 18, color: color),
    const SizedBox(width: 12),
    Text(label, style: TextStyle(color: color, fontSize: 13)),
  ]);

  PreferredSizeWidget _tabBar() {
    final m = isMatrixMode.value;
    final bar = TabBar(
      key: _keyTabs,
      controller: _tc, isScrollable: true,
      labelColor: m ? Colors.greenAccent : AppColors.uaYellow,
      unselectedLabelColor: AppColors.textSec,
      indicatorColor: m ? Colors.greenAccent : AppColors.uaYellow,
      tabs: cats.map((c) => Tab(text: c)).toList(),
    );
    return PreferredSize(
      preferredSize: Size.fromHeight(bar.preferredSize.height + 2),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        bar,
        if (!m) Container(height: 2, decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.uaBlue, AppColors.uaBlue, AppColors.uaYellow, AppColors.uaYellow],
            stops: [0, 0.5, 0.5, 1],
          ),
        )),
      ]),
    );
  }

  void _showStats() {
    final m = isMatrixMode.value;
    final s = {'ФО': 0, 'ЮО': 0, 'ГЕОІНТ': 0, 'МОНІТОРИНГ': 0, 'ЗВІТИ': 0, 'ІНШІ': 0};
    int tot = prompts.length;
    for (var p in prompts) if (s.containsKey(p.category)) s[p.category] = s[p.category]! + 1;
    showDialog(context: context, builder: (c) => AlertDialog(
      backgroundColor: m ? Colors.black87 : AppColors.bg,
      title: Text('СТАТИСТИКА БАЗИ', style: TextStyle(color: m ? Colors.greenAccent : AppColors.textPri)),
      content: Column(mainAxisSize: MainAxisSize.min, children: s.entries.map((e) => Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(e.key), Text('${e.value}', style: TextStyle(color: m ? Colors.greenAccent : AppColors.accent, fontWeight: FontWeight.bold))]),
        const SizedBox(height: 4),
        LinearProgressIndicator(value: tot == 0 ? 0 : e.value / tot, color: m ? Colors.green : AppColors.uaBlue, backgroundColor: Colors.white10),
        const SizedBox(height: 10),
      ])).toList()),
    ));
  }

  void _showLogs() => showDialog(context: context, builder: (c) => AlertDialog(
    backgroundColor: Colors.black,
    title: const Text('ЖУРНАЛ ДІЙ', style: TextStyle(color: Colors.greenAccent)),
    content: SizedBox(width: double.maxFinite, height: 300, child: logs.isEmpty
        ? const Center(child: Text('НЕМАЄ ЗАПИСІВ', style: TextStyle(color: Colors.white24)))
        : ListView.builder(itemCount: logs.length, itemBuilder: (_, i) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(logs[i], style: const TextStyle(fontSize: 10, color: Colors.greenAccent, fontFamily: 'JetBrainsMono'))))),
    actions: [
      TextButton(onPressed: () { setState(() { logs.clear(); }); DatabaseHelper.instance.clearLogs(); Navigator.pop(c); }, child: const Text('CLEAR', style: TextStyle(color: Colors.redAccent))),
      TextButton(onPressed: () => Navigator.pop(c), child: const Text('CLOSE', style: TextStyle(color: Colors.white54))),
    ],
  ));

  @override Widget build(BuildContext context) {
    final m = isMatrixMode.value;
    final k = isKyivMode.value;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      color: m ? Colors.black : k ? const Color(0xFF020B1A) : _currentTabColor,
      child: Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: _appBar(),
      body: Stack(children: [
        // ── Фон ──
        Positioned.fill(child:
          m ? const MatrixEffect()
          : k ? _kyivBackground()
          : CustomPaint(painter: _TopoGridPainter(), child: Container())
        ),
        // Контент під AppBar
        SafeArea(child: Column(children: [
          // Синьо-жовта смужка
          Container(height: 2, decoration: const BoxDecoration(gradient: LinearGradient(
            colors: [AppColors.uaBlue, AppColors.uaBlue, AppColors.uaYellow, AppColors.uaYellow],
            stops: [0, 0.5, 0.5, 1],
          ))),
          Expanded(child: TabBarView(controller: _tc, children: cats.map((cat) {
            if (cat == 'HOME')        return _buildHome();
            if (cat == 'ІНСТРУМЕНТИ') return ToolsMenu(onLog: _log);
            if (cat == 'ДОКУМЕНТИ')   return _buildDocs();
            return _buildPromptList(cat);
          }).toList())),
        ])),
      ]),
      floatingActionButton: (_tc.index == 0 || cats[_tc.index] == 'ІНСТРУМЕНТИ') ? null : FloatingActionButton(
        key: _keyFab,
        backgroundColor: m ? Colors.green.withOpacity(0.3) : AppColors.uaBlue,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: m ? Colors.greenAccent : AppColors.uaYellow, width: 1.5)),
        onPressed: () => cats[_tc.index] == 'ДОКУМЕНТИ' ? _pickPDF() : _addP(),
        child: Icon(cats[_tc.index] == 'ДОКУМЕНТИ' ? Icons.picture_as_pdf : Icons.add, color: m ? Colors.greenAccent : Colors.white),
      ),
      ),
    );
  }

  // Київ-фон — реальне фото
  Widget _kyivBackground() {
    return SizedBox.expand(
      child: Image.asset(
        'assets/kyiv_night.jpg',
        fit: BoxFit.cover,
        color: Colors.black.withOpacity(0.45),
        colorBlendMode: BlendMode.darken,
        errorBuilder: (_, __, ___) => CustomPaint(
          painter: _KyivNightPainter(),
          child: Container(),
        ),
      ),
    );
  }

  // ── ДАШБОРД ─────────────────────────────────
  Widget _buildHome() {
    final m = isMatrixMode.value;
    final stats = <String, int>{};
    for (final cat in ['ФО', 'ЮО', 'ГЕОІНТ', 'МОНІТОРИНГ', 'ЗВІТИ', 'ІНШІ']) {
      stats[cat] = prompts.where((p) => p.category == cat).length;
    }
    final total  = prompts.length;
    final favCnt = prompts.where((p) => p.isFavorite).length;

    // Анімовані значення (count-up від 0 до реального числа)
    final aniTotal = (_countAnim.value * total).round();
    final aniFav   = (_countAnim.value * favCnt).round();
    final aniDocs  = (_countAnim.value * docs.length).round();

    return AnimatedBuilder(
      animation: _countAnim,
      builder: (_, __) => NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n is ScrollUpdateNotification) setState(() => _scrollOffset = n.metrics.pixels);
        return false;
      },
      child: SingleChildScrollView(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Parallax фон-заголовок ──
        Transform.translate(
          offset: Offset(0, -_scrollOffset * 0.3),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('ПРОМПТАРНЯ', style: TextStyle(
                fontSize: 9, letterSpacing: 3,
                color: m ? Colors.green.withOpacity(0.5) : AppColors.uaYellow.withOpacity(0.4),
              )),
              const SizedBox(height: 4),
              Text('ОПЕРАТИВНИЙ ЦЕНТР', style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 1,
                color: m ? Colors.greenAccent : AppColors.textPri,
              )),
            ]),
          ),
        ),

        // ── Метрики з анімованими цифрами ──
        Row(children: [
          _metricCard('ЗАПИСІВ',    aniTotal.toString(),  AppColors.uaBlue),
          const SizedBox(width: 10),
          _metricCard('ОБРАНИХ',    aniFav.toString(),    AppColors.uaYellow),
          const SizedBox(width: 10),
          _metricCard('ДОКУМЕНТІВ', aniDocs.toString(),   AppColors.accent),
        ]),

        const SizedBox(height: 20),

        // ── Кільцева діаграма ──
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('РОЗПОДІЛ ПО КАТЕГОРІЯХ',
                style: TextStyle(fontSize: 10, letterSpacing: 1, color: m ? Colors.greenAccent : AppColors.textSec)),
            const SizedBox(height: 16),
            Row(children: [
              // Діаграма
              SizedBox(
                width: 110, height: 110,
                child: total == 0
                  ? Center(child: Text('—', style: TextStyle(color: AppColors.textHint)))
                  : CustomPaint(painter: _DonutPainter(stats, total)),
              ),
              const SizedBox(width: 20),
              // Легенда
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: stats.entries.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    Container(width: 10, height: 10, margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(color: catColor(e.key), borderRadius: BorderRadius.circular(3))),
                    Text(e.key, style: TextStyle(fontSize: 11, color: m ? Colors.greenAccent : AppColors.textSec)),
                    const Spacer(),
                    Text('${e.value}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
                        color: m ? Colors.greenAccent : catColor(e.key))),
                  ]),
                )).toList(),
              )),
            ]),
          ]),
        ),

        const SizedBox(height: 16),

        // ── Останні використані промпти ──
        if (prompts.any((p) => p.useCount > 0)) ...[
          Text('ОСТАННІ ВИКОРИСТАНІ',
              style: TextStyle(fontSize: 10, letterSpacing: 1, color: m ? Colors.greenAccent : AppColors.textSec)),
          const SizedBox(height: 8),
          ...(() {
            final recent = prompts.where((p) => p.lastUsed.isNotEmpty).toList()
              ..sort((a, b) => b.lastUsed.compareTo(a.lastUsed));
            return recent.take(3).map((p) => Container(
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(m ? 0.02 : 0.04),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: catColor(p.category).withOpacity(0.3)),
              ),
              child: ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                leading: Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: catColor(p.category),
                    boxShadow: [BoxShadow(color: catColor(p.category).withOpacity(0.6), blurRadius: 6, spreadRadius: 1)],
                  ),
                ),
                title: Text(p.title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: m ? Colors.greenAccent : AppColors.textPri), maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (p.ratingCount > 0) ...[
                    Icon(Icons.star_rounded, size: 12, color: p.avgRating >= 2.5 ? AppColors.uaYellow : Colors.orange),
                    const SizedBox(width: 2),
                    Text(p.avgRating.toStringAsFixed(1), style: const TextStyle(fontSize: 10, color: AppColors.textSec)),
                    const SizedBox(width: 8),
                  ],
                  Text('×${p.useCount}', style: const TextStyle(fontSize: 10, color: AppColors.textHint, fontFamily: 'JetBrainsMono')),
                ]),
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.push(context, MaterialPageRoute(builder: (_) => GenScreen(p: p, onLog: _log)));
                },
              ),
            ));
          })(),
          const SizedBox(height: 12),
        ],

        // ── Швидкий доступ ──
        Text('ШВИДКИЙ ДОСТУП',
            style: TextStyle(fontSize: 10, letterSpacing: 1, color: m ? Colors.greenAccent : AppColors.textSec)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _quickChip('СКАНЕР',     Icons.radar,           () => Navigator.push(context, MaterialPageRoute(builder: (_) => ScannerScreen(onLog: _log)))),
          _quickChip('ІПН',        Icons.fingerprint,     () => Navigator.push(context, MaterialPageRoute(builder: (_) => IpnScreen(onLog: _log)))),
          _quickChip('ТЕЛЕФОН',    Icons.phone_outlined,  () => Navigator.push(context, MaterialPageRoute(builder: (_) => PhoneScreen(onLog: _log)))),
          _quickChip('DORKS',      Icons.travel_explore,  () => Navigator.push(context, MaterialPageRoute(builder: (_) => DorksScreen(onLog: _log)))),
          _quickChip('АВТО',       Icons.directions_car,  () => Navigator.push(context, MaterialPageRoute(builder: (_) => AutoScreen(onLog: _log)))),
          _quickChip('ХРОНОЛОГІЯ', Icons.timeline,        () => Navigator.push(context, MaterialPageRoute(builder: (_) => TimeScreen(onLog: _log)))),
        ]),
      ]),
      ),   // SingleChildScrollView
      ),   // NotificationListener
    );     // AnimatedBuilder
  }

  Widget _metricCard(String label, String value, Color color) => Expanded(child: Container(
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
    decoration: BoxDecoration(
      color: color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withOpacity(0.25)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 9, letterSpacing: 0.8, color: color.withOpacity(0.7))),
      const SizedBox(height: 4),
      Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
    ]),
  ));

  Widget _quickChip(String label, IconData icon, VoidCallback onTap) => InkWell(
    onTap: () { HapticFeedback.lightImpact(); onTap(); },
    borderRadius: BorderRadius.circular(8),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: AppColors.uaYellow),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSec, letterSpacing: 0.5)),
      ]),
    ),
  );

  // Preview змінних у картці — зелений текст, {змінні} кольором категорії
  Widget _buildPreview(String content, String cat) {
    final m = isMatrixMode.value;
    final reg = RegExp(r'\{([^}]+)\}');
    final spans = <InlineSpan>[];
    int last = 0;
    // Беремо тільки перший рядок, обрізаємо до 120 символів
    var firstLine = content.split('\n').first;
    if (firstLine.length > 120) firstLine = '${firstLine.substring(0, 120)}…';
    for (final match in reg.allMatches(firstLine)) {
      if (match.start > last) {
        spans.add(TextSpan(
          text: firstLine.substring(last, match.start),
          style: TextStyle(color: m ? Colors.green : Colors.grey, fontSize: 11),
        ));
      }
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Container(
          margin: const EdgeInsets.only(left: 1, right: 1),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: catColor(cat).withOpacity(0.15),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: catColor(cat).withOpacity(0.4), width: 0.5),
          ),
          child: Text('{${match.group(1)}}',
            style: TextStyle(fontSize: 9, color: catColor(cat), fontFamily: 'JetBrainsMono', fontWeight: FontWeight.bold),
          ),
        ),
      ));
      last = match.end;
    }
    if (last < firstLine.length) {
      spans.add(TextSpan(
        text: firstLine.substring(last),
        style: TextStyle(color: m ? Colors.green : Colors.grey, fontSize: 11),
      ));
    }
    if (spans.isEmpty) {
      return Text(firstLine, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: m ? Colors.green : Colors.grey, fontSize: 11));
    }
    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(children: spans),
    );
  }

  Widget _buildDocs() {
    final m = isMatrixMode.value;
    if (docs.isEmpty) return const Center(child: Text('[ ФАЙЛІВ НЕМАЄ ]', style: TextStyle(color: Colors.white24)));
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 90),
      itemCount: docs.length,
      itemBuilder: (c, i) => Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        color: Colors.white.withOpacity(m ? 0.02 : 0.04),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: AppColors.border)),
        child: ListTile(
          leading: Icon(Icons.picture_as_pdf, color: m ? Colors.green : AppColors.accent),
          title: Text(docs[i].name, style: TextStyle(color: m ? Colors.greenAccent : AppColors.textPri)),
          onTap: () => _openPdfWindows(docs[i].path),
          trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 18), onPressed: () {
            showDialog(context: context, builder: (_) => AlertDialog(
              backgroundColor: AppColors.bgCard,
              title: const Text('Видалити документ?', style: TextStyle(fontSize: 15)),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Ні', style: TextStyle(color: AppColors.textSec))),
                ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () {
                    final docId = docs[i].id;
                    setState(() => docs.removeAt(i));
                    DatabaseHelper.instance.deleteDoc(docId);
                    Navigator.pop(context);
                  }, child: const Text('Так')),
              ],
            ));
          }),
        ),
      ),
    );
  }

  Widget _buildPromptList(String cat) {
    final m = isMatrixMode.value;
    final items = _filtered(cat);
    if (items.isEmpty) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(_searchQuery.isNotEmpty ? Icons.search_off : Icons.inbox_outlined, color: AppColors.textHint, size: 48),
      const SizedBox(height: 12),
      Text(_searchQuery.isNotEmpty ? 'Нічого не знайдено' : '[ ПУСТО ]', style: const TextStyle(color: Colors.white24)),
    ]));

    return ReorderableListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 90),
      itemCount: items.length,
      onReorder: _searchQuery.isNotEmpty ? (_, __) {} : (oldIdx, newIdx) {
        setState(() {
          if (newIdx > oldIdx) newIdx -= 1;
          final item = items.removeAt(oldIdx); items.insert(newIdx, item);
          prompts.removeWhere((p) => p.category == cat); prompts.addAll(items);
        });
        DatabaseHelper.instance.updatePromptOrder(
          items.map((p) => DbPrompt(id: p.id, title: p.title, content: p.content, category: p.category, isFavorite: p.isFavorite)).toList()
        );
      },
      itemBuilder: (ctx, i) {
        final p = items[i];
        return Padding(
          key: ValueKey(p.id),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: _kyivCard(m, p, cat, i, items),
        );
      },
    );
  }

  // Картка з glass-ефектом для Київ-режиму
  Widget _kyivCard(bool m, Prompt p, String cat, int i, List<Prompt> items) {
    final k = isKyivMode.value;
    final card = Card(
          key: ValueKey('card_${p.id}'),
          margin: EdgeInsets.zero,
          color: k
              ? Colors.white.withOpacity(0.06)
              : Colors.white.withOpacity(m ? 0.02 : (p.isFavorite ? 0.05 : 0.03)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: p.isFavorite
                  ? AppColors.uaYellow.withOpacity(0.4)
                  : k
                      ? Colors.white.withOpacity(0.12)
                      : catColor(cat).withOpacity(0.2),
            ),
          ),
          child: ListTile(
            leading: IconButton(
              icon: Icon(p.isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                  color: p.isFavorite ? (m ? Colors.green : AppColors.uaYellow) : Colors.white24),
              onPressed: () {
                setState(() => p.isFavorite = !p.isFavorite);
                DatabaseHelper.instance.updateFavorite(p.id, p.isFavorite);
                HapticFeedback.lightImpact();
              },
            ),
            title: Hero(
              tag: 'prompt_title_${p.id}',
              child: Material(
                color: Colors.transparent,
                child: Text(p.title, style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: m ? Colors.greenAccent : k ? Colors.white : AppColors.textPri,
                )),
              ),
            ),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Preview з підсвіткою {змінних}
              _buildPreview(p.content, cat),
              // Статистика використання та рейтинг по моделях
              if (p.useCount > 0 || p.ratingCount > 0) Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(spacing: 6, runSpacing: 2, children: [
                  if (p.useCount > 0) Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.play_arrow, size: 10, color: AppColors.textHint),
                    const SizedBox(width: 2),
                    Text('${p.useCount}', style: const TextStyle(fontSize: 9, color: AppColors.textHint)),
                  ]),
                  // Рейтинг по моделях
                  ...p.modelRatings.entries.where((e) => (e.value['count'] ?? 0) > 0).map((e) {
                    final avg = e.value['sum']! / e.value['count']!;
                    final color = avg >= 2.5 ? AppColors.uaYellow : avg >= 1.5 ? Colors.orange : Colors.redAccent;
                    // Скорочені назви моделей
                    final short = e.key.replaceAll('GPT-4o', 'GPT').replaceAll('Perplexity', 'PPLX').replaceAll('Без моделі', '?');
                    return Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.star_rounded, size: 9, color: color),
                      Text('$short ${avg.toStringAsFixed(1)}', style: TextStyle(fontSize: 8, color: color, fontFamily: 'JetBrainsMono')),
                    ]);
                  }),
                  // Якщо немає per-model але є загальний
                  if (p.modelRatings.isEmpty && p.ratingCount > 0) Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.star_rounded, size: 10, color: p.avgRating >= 2.5 ? AppColors.uaYellow : p.avgRating >= 1.5 ? Colors.orange : Colors.redAccent),
                    const SizedBox(width: 2),
                    Text('${p.avgRating.toStringAsFixed(1)}', style: TextStyle(fontSize: 9, color: p.avgRating >= 2.5 ? AppColors.uaYellow : p.avgRating >= 1.5 ? Colors.orange : Colors.redAccent)),
                  ]),
                ]),
              ),
              // Коментарі аналітика
              if (p.notes.isNotEmpty) Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(children: [
                  Icon(Icons.sticky_note_2_outlined, size: 10, color: AppColors.uaYellow.withOpacity(0.5)),
                  const SizedBox(width: 4),
                  Expanded(child: Text(p.notes, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 9, color: AppColors.uaYellow.withOpacity(0.5), fontStyle: FontStyle.italic))),
                ]),
              ),
            ]),
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.push(context, MaterialPageRoute(builder: (_) => GenScreen(p: p, onLog: _log)));
            },
            onLongPress: () {
              HapticFeedback.mediumImpact();
              showModalBottomSheet(
                context: context,
                backgroundColor: Colors.transparent,
                builder: (ctx) => Container(
                  margin: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: m ? Colors.black : AppColors.bgCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: m ? Colors.greenAccent.withOpacity(0.3) : AppColors.uaBlue.withOpacity(0.3)),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: AppColors.border)),
                      ),
                      child: Text(
                        p.title,
                        style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 0.5,
                          color: m ? Colors.greenAccent : AppColors.uaYellow,
                        ),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    ListTile(
                      leading: Icon(Icons.edit_outlined, color: m ? Colors.greenAccent : AppColors.accent, size: 20),
                      title: Text('РЕДАГУВАТИ', style: TextStyle(color: m ? Colors.greenAccent : AppColors.textPri, fontSize: 13, letterSpacing: 0.5)),
                      onTap: () { Navigator.pop(ctx); _addP(p: p); },
                    ),
                    ListTile(
                      leading: Icon(Icons.copy_all_outlined, color: m ? Colors.greenAccent : AppColors.uaYellow, size: 20),
                      title: Text('КЛОНУВАТИ (ФОРК)', style: TextStyle(color: m ? Colors.greenAccent : AppColors.uaYellow, fontSize: 13, letterSpacing: 0.5)),
                      onTap: () {
                        Navigator.pop(ctx);
                        final fork = Prompt(
                          id: _uid(),
                          title: '${p.title} (v2)',
                          content: p.content,
                          category: p.category,
                        );
                        setState(() => prompts.add(fork));
                        DatabaseHelper.instance.insertPrompt(DbPrompt(
                          id: fork.id, title: fork.title, content: fork.content,
                          category: fork.category, isFavorite: fork.isFavorite,
                        ), sortOrder: prompts.length);
                        _log('Форк: ${fork.title}');
                        HapticFeedback.mediumImpact();
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('Клоновано: ${fork.title}', style: const TextStyle(color: Colors.greenAccent)),
                          backgroundColor: AppColors.bgCard,
                        ));
                      },
                    ),
                    ListTile(
                      leading: Icon(Icons.compare_arrows, color: m ? Colors.greenAccent : AppColors.accent, size: 20),
                      title: Text('ПОРІВНЯТИ З...', style: TextStyle(color: m ? Colors.greenAccent : AppColors.accent, fontSize: 13, letterSpacing: 0.5)),
                      onTap: () {
                        Navigator.pop(ctx);
                        _showCompareSelector(p);
                      },
                    ),
                    ListTile(
                      leading: Icon(Icons.sticky_note_2_outlined, color: m ? Colors.greenAccent : const Color(0xFF80CBC4), size: 20),
                      title: Text('КОМЕНТАР', style: TextStyle(color: m ? Colors.greenAccent : const Color(0xFF80CBC4), fontSize: 13, letterSpacing: 0.5)),
                      subtitle: p.notes.isNotEmpty ? Text(p.notes, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: AppColors.textHint)) : null,
                      onTap: () {
                        Navigator.pop(ctx);
                        final notesCtrl = TextEditingController(text: p.notes);
                        showDialog(context: context, builder: (_) => AlertDialog(
                          backgroundColor: AppColors.bgCard,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.border)),
                          title: const Text('КОМЕНТАР АНАЛІТИКА', style: TextStyle(fontSize: 14, color: AppColors.uaYellow)),
                          content: TextField(controller: notesCtrl, maxLines: 5, style: const TextStyle(fontSize: 13, color: AppColors.textPri),
                            decoration: const InputDecoration(hintText: 'Досвід використання, поради, нотатки...', hintStyle: TextStyle(color: AppColors.textHint, fontSize: 12))),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context), child: const Text('СКАСУВАТИ', style: TextStyle(color: AppColors.textSec))),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: AppColors.uaBlue),
                              onPressed: () {
                                setState(() => p.notes = notesCtrl.text);
                                // Зберігаємо в БД через повне оновлення промпта
                                DatabaseHelper.instance.insertPrompt(DbPrompt(
                                  id: p.id, title: p.title, content: p.content,
                                  category: p.category, isFavorite: p.isFavorite,
                                  useCount: p.useCount, lastUsed: p.lastUsed,
                                  ratingSum: p.ratingSum, ratingCount: p.ratingCount,
                                ), sortOrder: prompts.indexOf(p));
                                Navigator.pop(context);
                                _log('Коментар оновлено: ${p.title}');
                              },
                              child: const Text('ЗБЕРЕГТИ'),
                            ),
                          ],
                        ));
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                      title: const Text('ВИДАЛИТИ', style: TextStyle(color: Colors.redAccent, fontSize: 13, letterSpacing: 0.5)),
                      onTap: () {
                        Navigator.pop(ctx);
                        showDialog(context: context, builder: (_) => AlertDialog(
                          backgroundColor: AppColors.bgCard,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: m ? Colors.green : AppColors.uaBlue, width: 0.5)),
                          title: Text('Видалити запис?', style: TextStyle(fontSize: 15, color: m ? Colors.greenAccent : AppColors.textPri)),
                          content: Text('\"${p.title}\" буде видалено назавжди.', style: TextStyle(fontSize: 13, color: AppColors.textSec)),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context), child: Text('СКАСУВАТИ', style: TextStyle(color: AppColors.textSec))),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                              onPressed: () {
                                Navigator.pop(context);
                                HapticFeedback.heavyImpact();
                                setState(() { p.title = '█████████'; p.content = '████████'; });
                                Future.delayed(const Duration(milliseconds: 400), () {
                                  if (!mounted) return;
                                  setState(() => prompts.remove(p));
                                  DatabaseHelper.instance.deletePrompt(p.id);
                                  _log('Видалено: ${p.title}');
                                });
                              },
                              child: const Text('ВИДАЛИТИ'),
                            ),
                          ],
                        ));
                      },
                    ),
                    if (p.useCount > 0) ListTile(
                      leading: Icon(Icons.star_outline, color: m ? Colors.greenAccent : AppColors.uaYellow, size: 20),
                      title: Text('ОЦІНИТИ', style: TextStyle(color: m ? Colors.greenAccent : AppColors.uaYellow, fontSize: 13, letterSpacing: 0.5)),
                      onTap: () {
                        Navigator.pop(ctx);
                        Navigator.push(context, MaterialPageRoute(builder: (_) => GenScreen(p: p, onLog: _log))).then((_) {
                          if (mounted) setState(() {});
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                  ]),
                ),
              );
            },
          ),
        );

    if (!k) return card;

    // Київ-режим — BackdropFilter blur
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: card,
      ),
    );
  }
}

// ─────────────────────────────────────────────
// МЕНЮ ІНСТРУМЕНТІВ — всі 9 збережено
// ─────────────────────────────────────────────
class ToolsMenu extends StatelessWidget {
  final Function(String) onLog;
  const ToolsMenu({super.key, required this.onLog});

  @override Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.only(top: 12, bottom: 90),
    children: [
      _t(context, 'DORKS',       'Google Конструктор (Новини, Документи)',      Icons.travel_explore,      DorksScreen(onLog: onLog)),
      _t(context, 'СКАНЕР',      'Екстракція (IP/Телефон/Email/Соцмережі)',     Icons.radar,               ScannerScreen(onLog: onLog)),
      _t(context, 'EXIF',        'Аналіз метаданих фотографій',                 Icons.image_search,        ExifScreen(onLog: onLog)),
      _t(context, 'ІПН',         'Дешифратор РНОКПП (дата/стать/вік)',          Icons.fingerprint,         IpnScreen(onLog: onLog)),
      _t(context, 'ФІНАНСИ',     'Перевірка карток (Алгоритм Луна)',            Icons.credit_card,         FinScreen(onLog: onLog)),
      _t(context, 'АВТО',        'Визначення регіону за номером',               Icons.directions_car,      AutoScreen(onLog: onLog)),
      _t(context, 'ТЕЛЕФОН',     'Країна, оператор, тип номера',                Icons.phone_outlined,       PhoneScreen(onLog: onLog)),
      _t(context, 'НІКНЕЙМИ',    'Генератор варіантів нікнеймів',               Icons.psychology,          NickScreen(onLog: onLog)),
      _t(context, 'ХРОНОЛОГІЯ',  'Таймлайн подій розслідування',                Icons.timeline,            TimeScreen(onLog: onLog)),
      _t(context, 'СЕЙФ',        'Захищений менеджер паролів',                  Icons.lock,                VaultScreen(onLog: onLog)),
    ],
  );

  Widget _t(BuildContext ctx, String t, String s, IconData i, Widget sc) => Card(
    color: Colors.white.withOpacity(0.03),
    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: AppColors.border)),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Container(width: 40, height: 40,
        decoration: BoxDecoration(color: AppColors.uaBlue.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
        child: Icon(i, color: AppColors.uaYellow, size: 20),
      ),
      title: Text(t, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.8)),
      subtitle: Text(s, style: const TextStyle(fontSize: 10, color: AppColors.textSec)),
      trailing: const Icon(Icons.chevron_right, color: AppColors.textHint),
      onTap: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => sc)),
    ),
  );
}

// ─────────────────────────────────────────────
// ГЕНЕРАТОР ПРОМПТІВ — з підсвіткою та методиками
// ─────────────────────────────────────────────
class GenScreen extends StatefulWidget {
  final Prompt p; final Function(String) onLog;
  const GenScreen({super.key, required this.p, required this.onLog});
  @override State<GenScreen> createState() => _GenScreenState();
}

class _GenScreenState extends State<GenScreen> {
  final Map<String, TextEditingController> _c = {};
  bool _comp = false;
  bool _compiling = false; // прогрес-анімація
  bool _editMode = false;  // режим редагування після компіляції
  final TextEditingController _editCtrl = TextEditingController();
  List<TextSpan> _spans = [];
  int _visLen = 0;
  Timer? _typingTimer;

  // Авто-підстановка: глобальний кеш значень змінних
  static final Map<String, String> _varCache = {};

  // ── РОЗШИРЕНИЙ СПИСОК МЕТОДИК ──
  final List<PromptEnhancer> _enhancers = [
    PromptEnhancer(
      name: 'CoT — Chain of Thought',
      desc: 'Покрокове мислення: модель пояснює хід міркувань перед відповіддю',
      pros: 'Висока точність на складних задачах, менше галюцинацій',
      cons: 'Значно збільшує довжину відповіді та витрату токенів',
      conflicts: 'Конфліктує з JSON Format (порушує структуру)',
      rec: 'Логічні задачі, аналіз, дедукція, математика',
      payload: 'Пояснюй свій хід думок крок за кроком (Step-by-step) перед тим як дати фінальну відповідь.',
    ),
    PromptEnhancer(
      name: 'ToT — Tree of Thoughts',
      desc: 'Дерево думок: генерує кілька гіпотез, оцінює і обирає найкращу',
      pros: 'Найкращий для неоднозначних даних, аналіз конкуруючих версій',
      cons: 'Дуже повільно, великий контекст, дорого по токенах',
      conflicts: 'Конфліктує з BLUF (протилежні підходи до структури)',
      rec: 'OSINT з мало даних, коли треба розглянути кілька версій',
      payload: 'Згенеруй 3 різні гіпотези щодо запиту. Для кожної: обґрунтування, слабкі місця, ймовірність. Потім обери та обґрунтуй найімовірнішу.',
    ),
    PromptEnhancer(
      name: 'Persona — OSINT Аналітик',
      desc: 'Рольова інструкція: модель виступає як старший аналітик',
      pros: 'Сухий, фаховий стиль без "води", підходить для звітів',
      cons: 'Може відмовляти на "чутливі" запити через роль',
      conflicts: 'Слабо конфліктує з CoT (можна комбінувати)',
      rec: 'Офіційні звіти, аналітичні записки, брифінги',
      payload: 'Дій як старший OSINT-аналітик з 10-річним досвідом. Відповідь має бути точною, сухою, без емоцій та загальних фраз. Факти і висновки — тільки на основі наданих даних.',
    ),
    PromptEnhancer(
      name: 'BLUF — Bottom Line Up Front',
      desc: 'Військовий формат: висновок першим, деталі після',
      pros: 'Економія часу, ідеально для керівництва та оперативних зведень',
      cons: 'Можна пропустити важливий контекст у деталях',
      conflicts: 'Конфліктує з ToT (там висновок — в кінці)',
      rec: 'Оперативні зведення, доповіді керівництву, терміновий аналіз',
      payload: 'Використовуй формат BLUF (Bottom Line Up Front): перший рядок — головний висновок в 1-2 реченні. Потім: деталі, обґрунтування, джерела.',
    ),
    PromptEnhancer(
      name: 'JSON Output',
      desc: 'Структурований вивід: результат тільки у валідному JSON',
      pros: 'Машиночитаємий формат, легко парсити і вставляти в бази',
      cons: 'Втрачається контекст, модель іноді додає текст поза JSON',
      conflicts: 'Конфліктує з CoT та ToT (ламає формат)',
      rec: 'Екстракція сутностей, парсинг, передача даних між системами',
      payload: 'Поверни результат ВИКЛЮЧНО у форматі валідного JSON. Без тексту, пояснень або markdown до чи після. Тільки JSON-об\'єкт.',
    ),
    PromptEnhancer(
      name: 'DSP — Decomposed Subtasks',
      desc: 'Декомпозиція: розбиває складне завдання на підзадачі',
      pros: 'Ефективний на многокрокових задачах, зменшує помилки',
      cons: 'Довга відповідь, може "загубитися" в підзадачах',
      conflicts: 'Добре поєднується з CoT; погано з JSON',
      rec: 'Складний OSINT-аналіз, розслідування, стратегічне планування',
      payload: 'Розбий це завдання на підзадачі. Для кожної підзадачі: сформулюй питання, дай відповідь, зроби мікровисновок. Фінальний висновок — після всіх підзадач.',
    ),
    PromptEnhancer(
      name: 'ReAct — Reason + Act',
      desc: 'Чергує міркування і "дії" (що б зробила модель далі)',
      pros: 'Добре імітує агентну поведінку, показує процес роботи',
      cons: 'Може галюцинувати "дії" яких не виконала',
      conflicts: 'Погано поєднується з BLUF та JSON',
      rec: 'Симуляція кроків розслідування, планування операцій',
      payload: 'Чергуй ДУМКА → ДІЯ → СПОСТЕРЕЖЕННЯ. Думка: що аналізую. Дія: що роблю. Спостереження: що отримав. Повторюй цикл до фінального висновку.',
    ),
    PromptEnhancer(
      name: 'Критик — Devil\'s Advocate',
      desc: 'Після відповіді модель сама критикує свої висновки',
      pros: 'Підвищує надійність, знаходить слабкі місця в аналізі',
      cons: 'Подвоює обсяг відповіді',
      conflicts: 'Конфліктує з BLUF (затягує структуру)',
      rec: 'Перевірка версій, оцінка ризиків, верифікація даних',
      payload: 'Після надання відповіді — зіграй роль критика: знайди 2-3 слабких місця у власних висновках, альтернативні пояснення і що може спростувати твій аналіз.',
    ),
    PromptEnhancer(
      name: 'Few-Shot — Приклади',
      desc: 'Надає моделі приклади формату відповіді перед основним запитом',
      pros: 'Стабільний формат виводу, модель точніше розуміє очікування',
      cons: 'Витрачає токени на приклади, треба готувати вручну',
      conflicts: 'Добре поєднується з Persona та JSON',
      rec: 'Коли потрібен чіткий повторюваний формат (таблиці, профілі)',
      payload: 'Приклад формату відповіді: [ПОЛЕ]: [ЗНАЧЕННЯ]. Дотримуйся цього формату для всіх результатів. Якщо дані відсутні — пиши "N/A".',
    ),
    PromptEnhancer(
      name: 'Confidence Score — Впевненість',
      desc: 'Модель додає оцінку достовірності до кожного твердження',
      pros: 'Чесність щодо невизначеності, ключово для OSINT',
      cons: 'Відсотки умовні, можуть вводити в оману',
      conflicts: 'Добре поєднується з майже усіма методиками',
      rec: 'Верифікація даних, оцінка джерел, звіти з невизначеністю',
      payload: 'До кожного ключового твердження або висновку додай оцінку достовірності: [HIGH / MEDIUM / LOW] та коротке пояснення чому саме так.',
    ),
  ];

  @override void initState() {
    super.initState();
    final r = RegExp(r'\{([^}]+)\}');
    for (var m in r.allMatches(widget.p.content)) {
      final key = m.group(1)!;
      _c[key] = TextEditingController(text: _varCache[key] ?? '');
    }
    if (_c.isEmpty) _compile();
  }

  @override void dispose() {
    _typingTimer?.cancel();
    _editCtrl.dispose();
    for (final c in _c.values) c.dispose();
    super.dispose();
  }

  Future<void> _compile() async {
    // Зберігаємо значення змінних у кеш для авто-підстановки
    for (final entry in _c.entries) {
      if (entry.value.text.isNotEmpty) _varCache[entry.key] = entry.value.text;
    }

    _spans.clear();
    String t = widget.p.content; int last = 0;
    final r = RegExp(r'\{([^}]+)\}');

    // Основний текст з підсвіткою: зелений = текст промпту, червоний = введені дані
    for (var m in r.allMatches(t)) {
      if (m.start > last) _spans.add(TextSpan(text: t.substring(last, m.start), style: const TextStyle(color: Colors.greenAccent)));
      final val = _c[m.group(1)!]?.text ?? '';
      _spans.add(TextSpan(
        text: val.isEmpty ? "{${m.group(1)}}" : val,
        style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
      ));
      last = m.end;
    }
    if (last < t.length) _spans.add(TextSpan(text: t.substring(last), style: const TextStyle(color: Colors.greenAccent)));

    // Активні методики — жовтим
    final sel = _enhancers.where((e) => e.isSelected).toList();
    if (sel.isNotEmpty) {
      _spans.add(const TextSpan(text: "\n\n### SYSTEM_INSTRUCTIONS:\n", style: TextStyle(color: Colors.yellow, fontWeight: FontWeight.bold)));
      for (var e in sel) _spans.add(TextSpan(text: "— ${e.payload}\n", style: const TextStyle(color: Colors.yellow)));
    }

    // Анімація компіляції: коротка затримка з progress bar
    setState(() { _compiling = true; _comp = false; _visLen = 0; });
    _typingTimer?.cancel();
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;

    setState(() { _compiling = false; _comp = true; });
    final total = _spans.fold(0, (s, x) => s + (x.text?.length ?? 0));
    _typingTimer = Timer.periodic(const Duration(milliseconds: 5), (tm) {
      if (!mounted) { tm.cancel(); return; }
      setState(() { _visLen += 15; if (_visLen >= total) tm.cancel(); });
    });
    widget.onLog("Компіляція: ${widget.p.title}");
    FocusScope.of(context).unfocus();

    // Трекінг використання
    widget.p.useCount++;
    widget.p.lastUsed = DateTime.now().toIso8601String();
    DatabaseHelper.instance.recordUsage(widget.p.id);
  }

  // Підрахунок токенів (~1 токен ≈ 4 символи для кирилиці, ~1 токен ≈ 4 байти для латиниці)
  int get _tokenEstimate {
    final text = _plainText;
    if (text.isEmpty) return 0;
    // Кирилиця: ~1.5 символ на токен; Латиниця: ~4 символи на токен; Мікс: ~2.5
    int cyrillic = 0, total = text.length;
    for (final c in text.runes) {
      if (c >= 0x0400 && c <= 0x04FF) cyrillic++;
    }
    final ratio = total > 0 ? cyrillic / total : 0;
    final charsPerToken = 1.5 + (1.0 - ratio) * 2.5; // від 1.5 (повна кирилиця) до 4.0 (повна латиниця)
    return (total / charsPerToken).ceil();
  }

  // Оцінка ефективності
  void _showRating() {
    final selectedModels = <String>{};
    showDialog(context: context, builder: (_) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
      backgroundColor: AppColors.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.uaBlue, width: 0.5)),
      title: const Text('ОЦІНКА РЕЗУЛЬТАТУ', style: TextStyle(fontSize: 15, color: AppColors.textPri)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Чи був результат ШІ корисним?', style: TextStyle(fontSize: 13, color: AppColors.textSec)),
        const SizedBox(height: 10),
        const Text('Тестовано на:', style: TextStyle(fontSize: 10, color: AppColors.textHint)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: ['GPT-4o', 'Claude', 'Gemini', 'Grok', 'Perplexity', 'Інша'].map((m) =>
          FilterChip(
            label: Text(m, style: TextStyle(fontSize: 10, color: selectedModels.contains(m) ? Colors.black : AppColors.textSec)),
            selected: selectedModels.contains(m),
            selectedColor: AppColors.uaYellow,
            backgroundColor: AppColors.bgDeep,
            side: BorderSide(color: selectedModels.contains(m) ? AppColors.uaYellow : AppColors.border),
            checkmarkColor: Colors.black,
            onSelected: (v) => setD(() { if (v) selectedModels.add(m); else selectedModels.remove(m); }),
          ),
        ).toList()),
      ]),
      actions: [
        TextButton(
          onPressed: () { _rate(1, selectedModels); Navigator.pop(context); },
          child: const Text('НІ', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
        ),
        TextButton(
          onPressed: () { _rate(2, selectedModels); Navigator.pop(context); },
          child: const Text('ЧАСТКОВО', style: TextStyle(color: AppColors.uaYellow, fontSize: 13)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
          onPressed: () { _rate(3, selectedModels); Navigator.pop(context); },
          child: const Text('ТАК', style: TextStyle(color: Colors.black)),
        ),
      ],
    )));
  }

  void _rate(int score, Set<String> models) {
    setState(() {
      widget.p.addRating(score, models);
    });
    DatabaseHelper.instance.recordRating(widget.p.id, score);
    final modelStr = models.isNotEmpty ? ' [${models.join(", ")}]' : '';
    widget.onLog("Оцінка: ${widget.p.title} → ${score == 3 ? 'ТАК' : score == 2 ? 'ЧАСТКОВО' : 'НІ'}$modelStr");
    HapticFeedback.lightImpact();
  }

  // Повертає видиму частину (typing effect)
  List<TextSpan> _visible() {
    final res = <TextSpan>[]; int c = 0;
    for (var x in _spans) {
      final len = x.text?.length ?? 0;
      if (c + len <= _visLen) { res.add(x); c += len; }
      else { res.add(TextSpan(text: x.text!.substring(0, _visLen - c), style: x.style)); break; }
    }
    return res;
  }

  String get _plainText => _editMode ? _editCtrl.text : _spans.map((x) => x.text ?? '').join();

  void _showEnhancers() {
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: AppColors.bgCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(builder: (_, setM) => Container(
        padding: const EdgeInsets.all(16),
        height: MediaQuery.of(context).size.height * 0.85,
        child: Column(children: [
          Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 12),
          const Text('⚡ ТАКТИЧНЕ ПІДСИЛЕННЯ', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.uaYellow, fontSize: 16, letterSpacing: 1)),
          const SizedBox(height: 4),
          const Text('Додає інструкції до промпту. Впливає на стиль і формат відповіді LLM.',
              style: TextStyle(fontSize: 10, color: AppColors.textSec), textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Expanded(child: ListView.builder(
            itemCount: _enhancers.length,
            itemBuilder: (_, i) {
              final e = _enhancers[i];
              return Card(
                color: e.isSelected ? AppColors.uaBlue.withOpacity(0.15) : Colors.white.withOpacity(0.03),
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: e.isSelected ? AppColors.uaYellow.withOpacity(0.4) : AppColors.border),
                ),
                child: CheckboxListTile(
                  value: e.isSelected,
                  activeColor: AppColors.uaYellow,
                  checkColor: Colors.black,
                  onChanged: (v) { setM(() => e.isSelected = v!); if (_comp) _compile(); },
                  title: Text(e.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPri)),
                  subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const SizedBox(height: 4),
                    Text(e.desc, style: const TextStyle(fontSize: 11, color: AppColors.textSec)),
                    const SizedBox(height: 6),
                    // Плюси
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('+ ', style: TextStyle(fontSize: 10, color: Colors.greenAccent)),
                      Expanded(child: Text(e.pros, style: const TextStyle(fontSize: 10, color: Colors.greenAccent))),
                    ]),
                    // Мінуси
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('− ', style: TextStyle(fontSize: 10, color: AppColors.danger)),
                      Expanded(child: Text(e.cons, style: const TextStyle(fontSize: 10, color: AppColors.danger))),
                    ]),
                    // Конфлікти
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('⚠ ', style: TextStyle(fontSize: 10, color: Colors.orangeAccent)),
                      Expanded(child: Text(e.conflicts, style: const TextStyle(fontSize: 10, color: Colors.orangeAccent))),
                    ]),
                    // Рекомендація
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('✓ ', style: TextStyle(fontSize: 10, color: AppColors.accent)),
                      Expanded(child: Text(e.rec, style: const TextStyle(fontSize: 10, color: AppColors.accent))),
                    ]),
                    const SizedBox(height: 4),
                  ]),
                  isThreeLine: true,
                ),
              );
            },
          )),
          const SizedBox(height: 8),
          ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('ЗАСТОСУВАТИ')),
        ]),
      )),
    );
  }

  @override Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF091630),
    appBar: AppBar(title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('ГЕНЕРАТОР ПРОМПТІВ', style: TextStyle(fontSize: 13, letterSpacing: 1.5)),
      Hero(
        tag: 'prompt_title_${widget.p.id}',
        child: Material(color: Colors.transparent,
          child: Text(widget.p.title, style: const TextStyle(fontSize: 10, color: AppColors.textSec), overflow: TextOverflow.ellipsis)),
      ),
    ])),
    body: Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).padding.bottom),
      child: Column(children: [
        // ── Поля параметрів ──
        if (!_comp && !_compiling) ...[
          Expanded(child: ListView(children: _c.keys.map((k) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextField(
              controller: _c[k],
              style: const TextStyle(color: AppColors.textPri),
              decoration: InputDecoration(
                labelText: k,
                // Підказка якщо є кешоване значення і поле порожнє
                hintText: _varCache.containsKey(k) && (_c[k]?.text.isEmpty ?? true) ? 'Попереднє: ${_varCache[k]}' : null,
                hintStyle: const TextStyle(fontSize: 11, color: AppColors.textHint),
              ),
            ),
          )).toList())),
          const SizedBox(height: 10),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.uaBlue),
            onPressed: _compile,
            child: const Text('КОМПІЛЮВАТИ ЗАПИТ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1)),
          ),
        ],
        // ── Прогрес компіляції ──
        if (_compiling) ...[
          const Spacer(),
          Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.memory, color: AppColors.uaYellow, size: 32),
            const SizedBox(height: 16),
            const Text('КОМПІЛЯЦІЯ ЗАПИТУ...', style: TextStyle(color: AppColors.uaYellow, fontSize: 13, letterSpacing: 1.5)),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: const LinearProgressIndicator(
                color: AppColors.uaYellow,
                backgroundColor: AppColors.border,
                minHeight: 3,
              ),
            ),
            const SizedBox(height: 8),
            Text('${widget.p.variables.length} змінних · ${_enhancers.where((e) => e.isSelected).length} методик',
              style: const TextStyle(fontSize: 10, color: AppColors.textHint)),
          ]),
          const Spacer(),
        ],
        // ── Результат ──
        if (_comp) ...[
          // Кнопка підсилення
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: _enhancers.any((e) => e.isSelected) ? AppColors.uaYellow : AppColors.border),
              minimumSize: const Size(double.infinity, 44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: Icon(Icons.flash_on, color: _enhancers.any((e) => e.isSelected) ? AppColors.uaYellow : Colors.white38, size: 18),
            label: Text(
              _enhancers.any((e) => e.isSelected)
                  ? '⚡ АКТИВНІ: ${_enhancers.where((e) => e.isSelected).map((e) => e.name.split(' ')[0]).join(', ')}'
                  : 'ТАКТИЧНЕ ПІДСИЛЕННЯ',
              style: TextStyle(
                color: _enhancers.any((e) => e.isSelected) ? AppColors.uaYellow : Colors.white38,
                fontSize: 12, letterSpacing: 0.8,
              ),
            ),
            onPressed: _showEnhancers,
          ),
          const SizedBox(height: 10),
          // Вікно результату / редактор
          Expanded(child: Container(
            width: double.infinity, padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _editMode ? AppColors.uaYellow.withOpacity(0.5) : _comp ? AppColors.success.withOpacity(0.3) : AppColors.border)),
            child: _editMode
                ? TextField(
                    controller: _editCtrl,
                    maxLines: null,
                    expands: true,
                    style: const TextStyle(color: Colors.greenAccent, fontSize: 13, fontFamily: 'JetBrainsMono'),
                    decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero),
                  )
                : SingleChildScrollView(child: RichText(text: TextSpan(children: _visible()))),
          )),
          const SizedBox(height: 10),
          // Кнопки дій
          Row(children: [
            if (_c.isNotEmpty) ...[
              Expanded(child: OutlinedButton(
                style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.border), minimumSize: const Size(0, 46), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                onPressed: () => setState(() { _comp = false; _editMode = false; }),
                child: const Icon(Icons.refresh, color: Colors.white54),
              )),
              const SizedBox(width: 8),
            ],
            // Кнопка редагування
            Expanded(child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: _editMode ? AppColors.uaYellow : AppColors.border),
                minimumSize: const Size(0, 46),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                if (!_editMode) {
                  _editCtrl.text = _plainText;
                }
                setState(() => _editMode = !_editMode);
              },
              child: Icon(_editMode ? Icons.check : Icons.edit, size: 18, color: _editMode ? AppColors.uaYellow : Colors.white54),
            )),
            const SizedBox(width: 8),
            Expanded(flex: 2, child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.uaBlue, minimumSize: const Size(0, 46), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              icon: const Icon(Icons.copy, size: 16, color: Colors.white),
              label: const Text('COPY', style: TextStyle(color: Colors.white, letterSpacing: 1)),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _plainText));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Текст скопійовано!'), backgroundColor: AppColors.uaBlue, duration: Duration(seconds: 1)));
              },
            )),
            const SizedBox(width: 8),
            Expanded(flex: 2, child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, minimumSize: const Size(0, 46), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              icon: const Icon(Icons.send, size: 16, color: Colors.white),
              label: const Text('В LLM', style: TextStyle(color: Colors.white, letterSpacing: 1)),
              onPressed: () { Clipboard.setData(ClipboardData(text: _plainText)); widget.onLog("Промпт: скопійовано в буфер"); },
            )),
          ]),
          // ── Токени + оцінка ──
          if (_comp) ...[
            const SizedBox(height: 10),
            Row(children: [
              // Лічильник токенів
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.token_outlined, size: 14, color: AppColors.textSec),
                  const SizedBox(width: 6),
                  Text('~$_tokenEstimate токенів', style: const TextStyle(fontSize: 11, color: AppColors.textSec, fontFamily: 'JetBrainsMono')),
                ]),
              ),
              const SizedBox(width: 8),
              // Кількість символів
              Text('${_plainText.length} символів', style: const TextStyle(fontSize: 10, color: AppColors.textHint)),
              const Spacer(),
              // Кнопка оцінки
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.uaYellow, width: 0.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                ),
                icon: Icon(
                  widget.p.ratingCount > 0 ? Icons.star_rounded : Icons.star_border_rounded,
                  size: 16, color: AppColors.uaYellow,
                ),
                label: Text(
                  widget.p.ratingCount > 0
                      ? '${widget.p.avgRating.toStringAsFixed(1)}/3'
                      : 'ОЦІНИТИ',
                  style: const TextStyle(fontSize: 11, color: AppColors.uaYellow),
                ),
                onPressed: _showRating,
              ),
            ]),
          ],
        ],
      ]),
    ),
  );
}

// ─────────────────────────────────────────────
// PDF ПЕРЕГЛЯДАЧ
// ─────────────────────────────────────────────
class DorksScreen extends StatefulWidget {
  final Function(String) onLog;
  const DorksScreen({super.key, required this.onLog});
  @override State<DorksScreen> createState() => _DorksScreenState();
}
class _DorksScreenState extends State<DorksScreen> {
  final _t = TextEditingController();
  List<Map<String, dynamic>> _d = []; // 't': title, 'd': desc, 'q': List<String>

  void _gen() {
    String s = _t.text.trim(); if (s.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _d = [
      {'t': 'ДОКУМЕНТИ',           'd': 'PDF, Word, Excel, CSV',              'q': ['site:$s filetype:pdf', 'site:$s filetype:docx', 'site:$s filetype:xlsx', 'site:$s filetype:csv']},
      {'t': 'ПРЕЗЕНТАЦІЇ',         'd': 'PowerPoint, Google Slides',          'q': ['site:$s filetype:pptx', 'site:$s filetype:ppt', 'site:$s filetype:odp']},
      {'t': 'НОВИНИ / ЗГАДКИ',     'd': 'Згадки в новинах та ЗМІ',           'q': ['"$s" inurl:news', '"$s" inurl:article', '"$s" inurl:press']},
      {'t': 'СУДОВІ РІШЕННЯ',      'd': 'Реєстр судових рішень',             'q': ['"$s" site:reyestr.court.gov.ua', '"$s" site:youcontrol.com.ua']},
      {'t': 'ВІДКРИТІ ДИРЕКТОРІЇ', 'd': 'Індекси файлів та папок',            'q': ['site:$s intitle:"index of"']},
      {'t': 'СОЦМЕРЕЖІ',          'd': 'LinkedIn, Facebook, X, Instagram',   'q': ['"$s" site:linkedin.com/in', '"$s" site:facebook.com', '"$s" site:instagram.com', '"$s" site:x.com']},
      {'t': 'TELEGRAM',            'd': 'Канали та пости',                    'q': ['"$s" site:t.me']},
      {'t': 'ВИТОКИ ДАНИХ',        'd': 'Paste-сервіси',                      'q': ['"$s" site:pastebin.com', '"$s" site:ghostbin.me', '"$s" site:dpaste.org']},
      {'t': 'ПІДДОМЕНИ',           'd': 'Тестові, dev, staging',              'q': ['site:*.$s -www -mail']},
      {'t': 'КОНФІГИ / БАЗИ',      'd': 'Конфігурації, дампи, логи',          'q': ['site:$s filetype:env', 'site:$s filetype:sql', 'site:$s filetype:log', 'site:$s filetype:conf']},
      {'t': 'ПАРОЛІ / КЛЮЧІ',      'd': 'Файли з credentials',               'q': ['site:$s filetype:yml "password"', 'site:$s filetype:json "api_key"', 'site:$s filetype:xml "secret"']},
      {'t': 'АДМІН-ПАНЕЛІ',        'd': 'Панелі керування',                   'q': ['site:$s inurl:admin', 'site:$s inurl:login', 'site:$s inurl:wp-admin', 'site:$s inurl:dashboard']},
      {'t': 'API ENDPOINTS',       'd': 'API, Swagger, GraphQL',              'q': ['site:$s inurl:api', 'site:$s inurl:swagger', 'site:$s inurl:graphql']},
      {'t': 'КАМЕРИ / IoT',        'd': 'IP-камери, відкриті пристрої',       'q': ['"$s" inurl:"/view/index.shtml"', '"$s" intitle:"IP Camera"', '"$s" intitle:"webcamXP"']},
      {'t': 'EMAIL / КОНТАКТИ',    'd': 'Публічні електронні адреси',          'q': ['"@$s"', 'site:$s "email"', 'site:$s "contact"']},
      {'t': 'GITHUB / КОД',        'd': 'Репозиторії та вихідний код',         'q': ['"$s" site:github.com', '"$s" site:gitlab.com', '"$s" site:bitbucket.org']},
    ]);
    widget.onLog("Dorks: згенеровано ${_d.length} категорій для $s");
  }

  void _copyOne(String q) {
    Clipboard.setData(ClipboardData(text: q));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Скопійовано!'), backgroundColor: AppColors.uaBlue, duration: Duration(seconds: 1)));
  }

  void _copyCategory(List<String> queries) {
    Clipboard.setData(ClipboardData(text: queries.join('\n')));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Скопійовано ${queries.length} запитів'), backgroundColor: AppColors.uaBlue, duration: Duration(seconds: 1)));
  }

  @override Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.bg,
    appBar: AppBar(title: const Text('КОНСТРУКТОР DORKS'),
      actions: [if (_d.isNotEmpty) TextButton(
        onPressed: () {
          final all = _d.expand((e) => (e['q'] as List<String>)).toList();
          Clipboard.setData(ClipboardData(text: all.join('\n')));
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Скопійовано всі ${all.length} запитів'), backgroundColor: AppColors.uaBlue));
        },
        child: const Text('COPY ALL', style: TextStyle(color: AppColors.uaYellow, fontSize: 12)),
      )]),
    body: Column(children: [
      Padding(padding: const EdgeInsets.all(16), child: TextField(controller: _t, style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 13), decoration: const InputDecoration(labelText: 'ЦІЛЬОВИЙ ДОМЕН АБО КЛЮЧОВЕ СЛОВО'))),
      ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: AppColors.uaBlue), onPressed: _gen, child: const Text('ЗГЕНЕРУВАТИ', style: TextStyle(color: Colors.white))),
      Expanded(child: _d.isEmpty
          ? const Center(child: Text('Введіть домен і натисніть ЗГЕНЕРУВАТИ', style: TextStyle(color: Colors.white24)))
          : ListView.builder(
              padding: const EdgeInsets.only(left: 8, right: 8, top: 8, bottom: 90),
              itemCount: _d.length,
              itemBuilder: (c, i) {
                final queries = _d[i]['q'] as List<String>;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.03),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    // Заголовок категорії
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 8, 0),
                      child: Row(children: [
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(_d[i]['t']!, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.greenAccent, fontSize: 12, letterSpacing: 0.5)),
                          Text(_d[i]['d']!, style: const TextStyle(fontSize: 10, color: AppColors.textSec)),
                        ])),
                        // Копіювати всю категорію
                        TextButton(
                          onPressed: () => _copyCategory(queries),
                          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                          child: Text('COPY ${queries.length}', style: const TextStyle(fontSize: 9, color: AppColors.uaYellow, letterSpacing: 0.5)),
                        ),
                      ]),
                    ),
                    const Divider(color: AppColors.border, height: 8),
                    // Окремі запити
                    ...queries.map((q) => InkWell(
                      onTap: () => _copyOne(q),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        child: Row(children: [
                          Expanded(child: Text(q, style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 11, color: AppColors.textPri))),
                          const Icon(Icons.copy, size: 14, color: AppColors.uaYellow),
                        ]),
                      ),
                    )),
                    const SizedBox(height: 4),
                  ]),
                );
              },
            ),
      ),
    ]),
  );
}

// ─────────────────────────────────────────────
// СКАНЕР — розширений (з підтримкою DOCX)
// ─────────────────────────────────────────────
class ScannerScreen extends StatefulWidget {
  final Function(String) onLog;
  const ScannerScreen({super.key, required this.onLog});
  @override State<ScannerScreen> createState() => _ScannerScreenState();
}
class _ScannerScreenState extends State<ScannerScreen> with SingleTickerProviderStateMixin {
  final _c = TextEditingController();
  List<Map<String, String>> _r = [];
  late AnimationController _anim;
  bool _scanning = false;

  static const _typeConf = {
    'IP':         (icon: Icons.dns_outlined,          color: Color(0xFF6FA8DC), label: 'IP-адреси',              route: ''),
    'ТЕЛЕФОН':    (icon: Icons.phone_outlined,         color: Color(0xFFE8A05A), label: 'Телефони',               route: 'phone'),
    'EMAIL':      (icon: Icons.alternate_email,        color: Color(0xFF80D8B0), label: 'Електронні адреси',      route: 'nick'),
    'СОЦМЕРЕЖА':  (icon: Icons.share_outlined,         color: Color(0xFFA78BFA), label: 'Соцмережі / посилання',  route: ''),
    'URL':        (icon: Icons.link,                   color: Color(0xFF90CAF9), label: 'URL-адреси',             route: ''),
    'GPS':        (icon: Icons.location_on_outlined,   color: Color(0xFF4ADE80), label: 'GPS координати',         route: ''),
    'HASH':       (icon: Icons.tag,                    color: Color(0xFFFF6B6B), label: 'Хеші (MD5/SHA)',         route: ''),
    'ІПН':        (icon: Icons.fingerprint,            color: Color(0xFFCE93D8), label: 'ІПН (РНОКПП)',          route: 'ipn'),
    'ЄДРПОУ':     (icon: Icons.business,               color: Color(0xFFFFCC80), label: 'Коди ЄДРПОУ',           route: ''),
    'IBAN':       (icon: Icons.account_balance,        color: Color(0xFF80DEEA), label: 'IBAN рахунки',           route: ''),
    'НОМЕР_АВТО': (icon: Icons.directions_car,         color: Color(0xFFA5D6A7), label: 'Номерні знаки',         route: 'auto'),
    'CRYPTO':     (icon: Icons.currency_bitcoin,       color: Color(0xFFFFB74D), label: 'Криптоадреси',           route: ''),
    'ДАТА':       (icon: Icons.calendar_today,         color: Color(0xFF9FA8DA), label: 'Дати',                   route: ''),
  };

  @override void initState() { super.initState(); _anim = AnimationController(vsync: this, duration: const Duration(seconds: 2)); }
  @override void dispose() { _anim.dispose(); _c.dispose(); super.dispose(); }

  void _loadFile() async {
    FilePickerResult? r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['txt', 'docx']);
    if (r == null) return;
    final file = File(r.files.single.path!); String txt = "";
    if (r.files.single.extension == 'docx') {
      final arc = ZipDecoder().decodeBytes(await file.readAsBytes());
      for (var f in arc) if (f.name == 'word/document.xml') {
        final xml = utf8.decode(f.content as List<int>);
        txt = xml.replaceAll(RegExp(r'</w:t>'), ' ').replaceAll(RegExp(r'</w:p>'), '\n')
            .replaceAll(RegExp(r'<[^>]*>'), '').replaceAll(RegExp(r'[ \t]+'), ' ')
            .replaceAll(RegExp(r'\n '), '\n').trim();
      }
    } else { txt = await file.readAsString(); }
    setState(() => _c.text = txt);
  }

  void _scan() async {
    FocusScope.of(context).unfocus();
    setState(() { _scanning = true; _r.clear(); }); _anim.repeat();
    await Future.delayed(const Duration(milliseconds: 500));
    final t = _c.text;
    final results = <Map<String, String>>[];

    // IP
    RegExp(r'\b(?:(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\b').allMatches(t).forEach((m) => results.add({'v': m.group(0)!, 't': 'IP'}));
    // Телефони
    RegExp(r'(?:\+380|\+7|\+375|\+48|\+44|\+1|8)[\s\-\(\)]?\d{2,3}[\s\-\(\)]?\d{3}[\s\-]?\d{2}[\s\-]?\d{2}').allMatches(t).forEach((m) => results.add({'v': m.group(0)!, 't': 'ТЕЛЕФОН'}));
    // Email
    RegExp(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}').allMatches(t).forEach((m) => results.add({'v': m.group(0)!, 't': 'EMAIL'}));
    // Соцмережі
    RegExp(r'(?:https?:\/\/)?(?:www\.)?(?:t\.me|instagram\.com|facebook\.com|vk\.com|x\.com|twitter\.com|tiktok\.com)\/[a-zA-Z0-9_.\-]+').allMatches(t).forEach((m) => results.add({'v': m.group(0)!, 't': 'СОЦМЕРЕЖА'}));
    // URL загальні (не соцмережі)
    RegExp(r'https?:\/\/[a-zA-Z0-9\-\.]+\.[a-zA-Z]{2,}(?:\/[^\s]*)?').allMatches(t).where((m) {
      final v = m.group(0)!;
      return !results.any((r) => r['v'] == v); // не дублювати соцмережі
    }).forEach((m) => results.add({'v': m.group(0)!, 't': 'URL'}));
    // GPS
    RegExp(r'[-+]?(?:[1-8]?\d\.\d{3,}|90\.0+)[,\s]+[-+]?(?:(?:1[0-7]\d|[1-9]?\d)\.\d{3,}|180\.0+)').allMatches(t).forEach((m) => results.add({'v': m.group(0)!, 't': 'GPS'}));
    // Хеші
    RegExp(r'\b[0-9a-fA-F]{32}\b|\b[0-9a-fA-F]{40}\b|\b[0-9a-fA-F]{64}\b').allMatches(t).forEach((m) => results.add({'v': m.group(0)!, 't': 'HASH'}));
    // ІПН (10 цифр, не частина більшого числа)
    RegExp(r'\b\d{10}\b').allMatches(t).where((m) {
      final v = m.group(0)!;
      try { final days = int.parse(v.substring(0, 5)); return days > 0 && days < 60000; } catch(_) { return false; }
    }).forEach((m) => results.add({'v': m.group(0)!, 't': 'ІПН'}));
    // ЄДРПОУ (8 цифр)
    RegExp(r'\b\d{8}\b').allMatches(t).where((m) {
      final v = m.group(0)!;
      return !results.any((r) => r['v']!.contains(v)); // не частина ІПН
    }).forEach((m) => results.add({'v': m.group(0)!, 't': 'ЄДРПОУ'}));
    // IBAN (UA + 27 цифр)
    RegExp(r'\bUA\d{27}\b').allMatches(t).forEach((m) => results.add({'v': m.group(0)!, 't': 'IBAN'}));
    // Номерні знаки (AA1234BB паттерн)
    RegExp(r'\b[А-ЯA-Z]{2}\d{4}[А-ЯA-Z]{2}\b').allMatches(t).forEach((m) => results.add({'v': m.group(0)!, 't': 'НОМЕР_АВТО'}));
    // Криптоадреси (Bitcoin, Ethereum)
    RegExp(r'\b(?:1|3|bc1)[a-zA-HJ-NP-Z0-9]{25,62}\b').allMatches(t).forEach((m) => results.add({'v': m.group(0)!, 't': 'CRYPTO'}));
    RegExp(r'\b0x[0-9a-fA-F]{40}\b').allMatches(t).forEach((m) => results.add({'v': m.group(0)!, 't': 'CRYPTO'}));
    // Дати (DD.MM.YYYY або YYYY-MM-DD)
    RegExp(r'\b\d{2}\.\d{2}\.\d{4}\b').allMatches(t).forEach((m) => results.add({'v': m.group(0)!, 't': 'ДАТА'}));
    RegExp(r'\b\d{4}-\d{2}-\d{2}\b').allMatches(t).forEach((m) => results.add({'v': m.group(0)!, 't': 'ДАТА'}));

    _anim.stop();
    if (!mounted) return;
    setState(() { _r = results; _scanning = false; });
    widget.onLog("Сканер: знайдено ${_r.length} об'єктів");
  }

  bool _isEnemy(String v) => v.contains('.ru') || v.contains('+7') || v.contains('vk.com') || v.contains('mail.ru') || v.contains('.by');

  // Маршрутизація до інструментів
  void _routeTo(String type, String value) {
    switch (type) {
      case 'ТЕЛЕФОН':
        Navigator.push(context, MaterialPageRoute(builder: (_) => PhoneScreen(onLog: widget.onLog)));
        break;
      case 'ІПН':
        Navigator.push(context, MaterialPageRoute(builder: (_) => IpnScreen(onLog: widget.onLog)));
        break;
      case 'EMAIL':
        Navigator.push(context, MaterialPageRoute(builder: (_) => NickScreen(onLog: widget.onLog)));
        break;
      case 'НОМЕР_АВТО':
        Navigator.push(context, MaterialPageRoute(builder: (_) => AutoScreen(onLog: widget.onLog)));
        break;
      default:
        Clipboard.setData(ClipboardData(text: value));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Скопійовано: $value'), backgroundColor: AppColors.uaBlue, duration: const Duration(seconds: 1)));
    }
  }

  @override Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.bg,
    appBar: AppBar(
      title: const Text('РАДАР-СКАНЕР'),
      actions: [
        IconButton(icon: const Icon(Icons.file_open, color: AppColors.accent), onPressed: _loadFile, tooltip: 'Завантажити файл'),
        if (_r.isNotEmpty) TextButton(
          onPressed: () { Clipboard.setData(ClipboardData(text: _r.map((e) => e['v']).join('\n'))); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Скопійовано все'), backgroundColor: AppColors.uaBlue)); },
          child: const Text('COPY ALL', style: TextStyle(color: AppColors.uaYellow, fontSize: 12)),
        ),
      ],
    ),
    body: Column(children: [
      Stack(children: [
        Padding(padding: const EdgeInsets.all(16), child: TextField(controller: _c, maxLines: 5, style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 12), decoration: const InputDecoration(labelText: 'ВВЕДІТЬ АБО ЗАВАНТАЖТЕ ТЕКСТ'))),
        if (_scanning) AnimatedBuilder(
          animation: _anim,
          builder: (_, __) => Positioned(top: 20 + (_anim.value * 120), left: 16, right: 16, child: Container(height: 2, color: Colors.red, decoration: const BoxDecoration(boxShadow: [BoxShadow(color: Colors.red, blurRadius: 10)]))),
        ),
      ]),
      ElevatedButton(onPressed: _scan, child: const Text('СКАНУВАТИ', style: TextStyle(color: Colors.white, letterSpacing: 1))),
      // ── Зведення ──
      if (_r.isNotEmpty) Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(children: [
          Text('${_r.length}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.uaYellow)),
          const SizedBox(width: 8),
          Expanded(child: Wrap(spacing: 6, runSpacing: 4, children: (() {
            final counts = <String, int>{};
            for (var item in _r) counts[item['t']!] = (counts[item['t']!] ?? 0) + 1;
            final enemyCount = _r.where((r) => _isEnemy(r['v']!)).length;
            return [
              ...counts.entries.map((e) {
                final conf = _typeConf[e.key];
                final color = conf?.color ?? AppColors.accent;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                  child: Text('${e.value} ${e.key}', style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.bold)),
                );
              }),
              if (enemyCount > 0) Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.red.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                child: Text('$enemyCount ворожих', style: const TextStyle(fontSize: 9, color: Colors.redAccent, fontWeight: FontWeight.bold)),
              ),
            ];
          })())),
        ]),
      ),
      Expanded(child: _r.isEmpty
          ? const Center(child: Text('Введіть текст і натисніть СКАНУВАТИ', style: TextStyle(color: Colors.white24)))
          : _buildResults(),
      ),
    ]),
  );

  Widget _buildResults() {
    final grouped = <String, List<String>>{};
    for (var item in _r) { grouped.putIfAbsent(item['t']!, () => []).add(item['v']!); }
    return ListView(padding: const EdgeInsets.only(left: 8, right: 8, top: 8, bottom: 90), children: grouped.entries.map((entry) {
      final conf = _typeConf[entry.key];
      final icon = conf?.icon ?? Icons.tag;
      final color = conf?.color ?? AppColors.accent;
      final label = conf?.label ?? entry.key;
      final hasRoute = conf?.route.isNotEmpty ?? false;
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.02), borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
        child: Column(children: [
          Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), child: Row(children: [
            Container(width: 32, height: 32, decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(7)), child: Icon(icon, color: color, size: 17)),
            const SizedBox(width: 10),
            Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSec, letterSpacing: 0.5)),
            const Spacer(),
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(4)), child: Text('${entry.value.length}', style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold))),
          ])),
          const Divider(color: AppColors.border, height: 0),
          ...entry.value.map((v) => InkWell(
            onTap: () { Clipboard.setData(ClipboardData(text: v)); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Скопійовано: $v'), backgroundColor: AppColors.uaBlue, duration: const Duration(seconds: 1))); },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: _isEnemy(v) ? Colors.red.withOpacity(0.08) : null),
              child: Row(children: [
                if (_isEnemy(v)) const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.warning_amber, color: Colors.redAccent, size: 14)),
                Expanded(child: Text(v, style: TextStyle(fontFamily: 'JetBrainsMono', fontSize: 12, color: _isEnemy(v) ? Colors.redAccent : AppColors.textPri))),
                if (hasRoute) GestureDetector(
                  onTap: () => _routeTo(entry.key, v),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    margin: const EdgeInsets.only(left: 6),
                    decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                    child: Text('\u2192 ${conf!.route.toUpperCase()}', style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.bold)),
                  ),
                ),
                if (!hasRoute) const Text('copy', style: TextStyle(fontSize: 10, color: AppColors.uaYellow, letterSpacing: 0.5)),
              ]),
            ),
          )),
          InkWell(
            onTap: () { Clipboard.setData(ClipboardData(text: entry.value.join('\n'))); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Скопійовано ${label.toLowerCase()}'), backgroundColor: AppColors.uaBlue, duration: const Duration(seconds: 1))); },
            child: Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 8), decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))), child: const Text('+ copy all', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: AppColors.accent, letterSpacing: 0.5))),
          ),
        ]),
      );
    }).toList());
  }
}

// ─────────────────────────────────────────────
// EXIF АНАЛІЗАТОР (розширений)
// ─────────────────────────────────────────────
class ExifScreen extends StatefulWidget {
  final Function(String) onLog;
  const ExifScreen({super.key, required this.onLog});
  @override State<ExifScreen> createState() => _ExifScreenState();
}
class _ExifScreenState extends State<ExifScreen> {
  Map<String, String> _d = {};
  bool _loading = false;
  String? _gpsLat, _gpsLon;
  String? _dateTime;
  String? _software;
  String? _camera;
  String? _fileName;

  void _p() async {
    try {
      // FileType.custom замість FileType.image — уникає Photo Picker на Android 13+
      // який повертає копію без EXIF
      FilePickerResult? r = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'tiff', 'tif', 'webp', 'heic', 'heif', 'raw', 'cr2', 'nef', 'arw'],
      );
      if (r == null || r.files.single.path == null) return;
      if (!mounted) return;
      setState(() { _loading = true; _d.clear(); _gpsLat = null; _gpsLon = null; _dateTime = null; _software = null; _camera = null; });
      _fileName = r.files.single.name;
      final bytes = await File(r.files.single.path!).readAsBytes();
      final t = await readExifFromBytes(bytes);
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (t.isEmpty) {
          _d = {'Статус': 'Метадані відсутні або очищені (можливо, фото з месенджера або скріншот)'};
        } else {
          _d = {for (var e in t.entries) e.key: e.value.toString()};
          // Витягуємо ключові поля
          _extractHighlights(t);
        }
      });
      widget.onLog("EXIF: проаналізовано ${r.files.single.name} — ${t.length} тегів");
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _d = {'Помилка': e.toString()}; });
    }
  }

  void _extractHighlights(Map<String, dynamic> t) {
    // GPS
    final latRef = t['GPS GPSLatitudeRef']?.toString() ?? '';
    final lonRef = t['GPS GPSLongitudeRef']?.toString() ?? '';
    final lat = t['GPS GPSLatitude']?.toString();
    final lon = t['GPS GPSLongitude']?.toString();
    if (lat != null && lon != null) {
      _gpsLat = '${latRef == 'S' ? '-' : ''}${_dmsToDecimal(lat)}';
      _gpsLon = '${lonRef == 'W' ? '-' : ''}${_dmsToDecimal(lon)}';
    }
    // Дата
    _dateTime = t['EXIF DateTimeOriginal']?.toString()
             ?? t['Image DateTime']?.toString()
             ?? t['EXIF DateTimeDigitized']?.toString();
    // Софт
    _software = t['Image Software']?.toString();
    // Камера
    final make  = t['Image Make']?.toString() ?? '';
    final model = t['Image Model']?.toString() ?? '';
    if (make.isNotEmpty || model.isNotEmpty) {
      _camera = '$make $model'.trim();
    }
  }

  String _dmsToDecimal(String dms) {
    try {
      // Формат: "[50, 27, 1191/100]" або "50/1, 27/1, 1191/100"
      final clean = dms.replaceAll('[', '').replaceAll(']', '').trim();
      final parts = clean.split(',').map((s) => s.trim()).toList();
      if (parts.length < 3) return dms;
      double _frac(String s) {
        if (s.contains('/')) {
          final p = s.split('/');
          return double.parse(p[0]) / double.parse(p[1]);
        }
        return double.parse(s);
      }
      final d = _frac(parts[0]);
      final m = _frac(parts[1]);
      final s = _frac(parts[2]);
      return (d + m / 60 + s / 3600).toStringAsFixed(6);
    } catch (_) {
      return dms;
    }
  }

  Widget _highlightCard(IconData icon, String label, String value, {Color color = AppColors.accent, String? actionLabel, VoidCallback? onAction}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 10, color: color, letterSpacing: 0.5)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPri)),
        ])),
        if (onAction != null)
          TextButton(onPressed: onAction, child: Text(actionLabel ?? '', style: TextStyle(color: color, fontSize: 11))),
      ]),
    );
  }

  @override Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.bg,
    appBar: AppBar(
      title: const Text('EXIF АНАЛІЗАТОР'),
      actions: [
        if (_d.isNotEmpty) IconButton(
          icon: const Icon(Icons.copy_all, color: AppColors.uaYellow, size: 20),
          tooltip: 'Копіювати все',
          onPressed: () {
            final text = _d.entries.map((e) => '${e.key}: ${e.value}').join('\n');
            Clipboard.setData(ClipboardData(text: text));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Скопійовано всі метадані'), backgroundColor: AppColors.uaBlue, duration: Duration(seconds: 1)));
          },
        ),
      ],
    ),
    body: Column(children: [
      Padding(padding: const EdgeInsets.all(16), child: ElevatedButton.icon(
        icon: const Icon(Icons.image_search, size: 18), label: const Text('ОБРАТИ ФОТО'),
        style: ElevatedButton.styleFrom(backgroundColor: AppColors.uaBlue, minimumSize: const Size(double.infinity, 48)),
        onPressed: _p,
      )),
      Expanded(child: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.uaYellow))
          : _d.isEmpty
              ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.image_outlined, color: AppColors.textHint, size: 48),
                  SizedBox(height: 12),
                  Text('ЧЕКАЮ НА ФАЙЛ...', style: TextStyle(color: Colors.white24)),
                  SizedBox(height: 4),
                  Text('JPG, PNG, TIFF, HEIC, RAW', style: TextStyle(color: AppColors.textHint, fontSize: 10)),
                ]))
              : ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    // Назва файлу
                    if (_fileName != null) Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(_fileName!, style: const TextStyle(fontSize: 12, color: AppColors.textSec, fontFamily: 'JetBrainsMono')),
                    ),
                    // ── Ключові поля зверху ──
                    if (_gpsLat != null && _gpsLon != null)
                      _highlightCard(Icons.location_on, 'GPS КООРДИНАТИ', '$_gpsLat, $_gpsLon',
                        color: AppColors.success,
                        actionLabel: 'КАРТА',
                        onAction: () {
                          Clipboard.setData(ClipboardData(text: '$_gpsLat, $_gpsLon'));
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Координати скопійовано'), backgroundColor: AppColors.uaBlue, duration: Duration(seconds: 1)));
                        },
                      ),
                    if (_dateTime != null)
                      _highlightCard(Icons.calendar_today, 'ДАТА ЗЙОМКИ', _dateTime!, color: AppColors.uaYellow),
                    if (_camera != null)
                      _highlightCard(Icons.camera_alt, 'КАМЕРА', _camera!),
                    if (_software != null)
                      _highlightCard(Icons.build_outlined, 'ПРОГРАМНЕ ЗАБЕЗПЕЧЕННЯ', _software!,
                        color: _software!.toLowerCase().contains('photoshop') || _software!.toLowerCase().contains('gimp')
                            ? AppColors.danger : AppColors.accent,
                      ),
                    if (_gpsLat == null && _dateTime == null && _camera == null && _software == null && _d.length > 1)
                      _highlightCard(Icons.info_outline, 'УВАГА', 'Ключові OSINT-поля (GPS, дата, камера) відсутні', color: AppColors.danger),
                    // ── Всі інші теги ──
                    if (_d.length > 1) ...[
                      const Padding(padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('ВСІ МЕТАДАНІ', style: TextStyle(fontSize: 11, color: AppColors.textSec, letterSpacing: 1)),
                      ),
                      ..._d.entries.map((e) => Card(
                        color: Colors.white.withOpacity(0.03),
                        margin: const EdgeInsets.only(bottom: 4),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: AppColors.border)),
                        child: ListTile(dense: true,
                          title: Text(e.key, style: const TextStyle(fontSize: 11, color: AppColors.accent)),
                          subtitle: Text(e.value, style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                          trailing: const Icon(Icons.copy_outlined, size: 14, color: AppColors.textHint),
                          onTap: () { Clipboard.setData(ClipboardData(text: '${e.key}: ${e.value}')); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Скопійовано!'), backgroundColor: AppColors.uaBlue, duration: Duration(seconds: 1))); },
                        ),
                      )),
                    ] else ...[
                      ..._d.entries.map((e) => _highlightCard(Icons.info_outline, e.key, e.value, color: AppColors.danger)),
                    ],
                    const SizedBox(height: 20),
                  ],
                ),
      ),
    ]),
  );
}

// ─────────────────────────────────────────────
// ІПН ДЕШИФРАТОР
// ─────────────────────────────────────────────
class IpnScreen extends StatefulWidget {
  final Function(String) onLog;
  const IpnScreen({super.key, required this.onLog});
  @override State<IpnScreen> createState() => _IpnScreenState();
}
class _IpnScreenState extends State<IpnScreen> with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _c = TextEditingController();
  final _dateCtrl = TextEditingController();
  String _gender = 'Чоловіча';
  Map<String, String>? _r;
  String? _validationMsg;
  List<String>? _reverseResult;

  @override void initState() { super.initState(); _tabs = TabController(length: 2, vsync: this); }
  @override void dispose() { _tabs.dispose(); _c.dispose(); _dateCtrl.dispose(); super.dispose(); }

  // Ваги для контрольної цифри
  static const _w1 = [-1, 5, 7, 9, 4, 6, 10, 5, 7];
  static const _w2 = [-7, 1, 3, 5, 0, 2, 6, 1, 3]; // fallback

  bool _validateChecksum(String s) {
    if (s.length != 10) return false;
    final digits = s.split('').map((c) => int.tryParse(c) ?? 0).toList();
    int sum = 0;
    for (int i = 0; i < 9; i++) sum += digits[i] * _w1[i];
    int check = sum % 11;
    if (check == 10) {
      sum = 0;
      for (int i = 0; i < 9; i++) sum += digits[i] * _w2[i];
      check = sum % 11;
      if (check == 10) check = 0;
    }
    return check == digits[9];
  }

  void _decode() {
    String s = _c.text.trim();
    if (s.length != 10 || int.tryParse(s) == null) {
      setState(() { _r = null; _validationMsg = 'Введіть рівно 10 цифр'; });
      return;
    }
    try {
      final days = int.parse(s.substring(0, 5));
      DateTime d = DateTime(1899, 12, 31).add(Duration(days: days));
      final now = DateTime.now();
      int age = now.year - d.year;
      if (now.month < d.month || (now.month == d.month && now.day < d.day)) age--;
      final isMale = int.parse(s[8]) % 2 != 0;
      final isValid = _validateChecksum(s);

      // Знак зодіаку
      String zodiac = _getZodiac(d.month, d.day);

      // Покоління
      String gen = '';
      if (d.year >= 1997) gen = 'Покоління Z';
      else if (d.year >= 1981) gen = 'Покоління Y (мілленіали)';
      else if (d.year >= 1965) gen = 'Покоління X';
      else if (d.year >= 1946) gen = 'Бумери';
      else gen = 'Тихе покоління';

      setState(() {
        _validationMsg = isValid ? '✅ Контрольна цифра вірна' : '⚠ Контрольна цифра НЕ збігається — можливо фейк';
        _r = {
          'ДАТА НАРОДЖЕННЯ': "${d.day.toString().padLeft(2,'0')}.${d.month.toString().padLeft(2,'0')}.${d.year}",
          'ПОВНИХ РОКІВ': "$age",
          'СТАТЬ': isMale ? 'Чоловіча' : 'Жіноча',
          'ЗНАК ЗОДІАКУ': zodiac,
          'ПОКОЛІННЯ': gen,
          'РІК НАРОДЖЕННЯ': '${d.year}',
        };
      });
      widget.onLog("ІПН: дешифровано (${isValid ? 'VALID' : 'INVALID'})");
    } catch(_) {
      setState(() { _r = null; _validationMsg = 'Помилка декодування'; });
    }
  }

  String _getZodiac(int month, int day) {
    if ((month == 3 && day >= 21) || (month == 4 && day <= 19)) return '♈ Овен';
    if ((month == 4 && day >= 20) || (month == 5 && day <= 20)) return '♉ Тілець';
    if ((month == 5 && day >= 21) || (month == 6 && day <= 20)) return '♊ Близнюки';
    if ((month == 6 && day >= 21) || (month == 7 && day <= 22)) return '♋ Рак';
    if ((month == 7 && day >= 23) || (month == 8 && day <= 22)) return '♌ Лев';
    if ((month == 8 && day >= 23) || (month == 9 && day <= 22)) return '♍ Діва';
    if ((month == 9 && day >= 23) || (month == 10 && day <= 22)) return '♎ Терези';
    if ((month == 10 && day >= 23) || (month == 11 && day <= 21)) return '♏ Скорпіон';
    if ((month == 11 && day >= 22) || (month == 12 && day <= 21)) return '♐ Стрілець';
    if ((month == 12 && day >= 22) || (month == 1 && day <= 19)) return '♑ Козеріг';
    if ((month == 1 && day >= 20) || (month == 2 && day <= 18)) return '♒ Водолій';
    return '♓ Риби';
  }

  void _reverseCalc() {
    final dateStr = _dateCtrl.text.trim();
    final parts = dateStr.split('.');
    if (parts.length != 3) { setState(() => _reverseResult = ['Невірний формат. Використовуйте ДД.ММ.РРРР']); return; }
    try {
      final d = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
      final base = DateTime(1899, 12, 31);
      final days = d.difference(base).inDays;
      final daysStr = days.toString().padLeft(5, '0');
      final genderDigits = _gender == 'Чоловіча' ? [1,3,5,7,9] : [0,2,4,6,8];

      // Генеруємо кілька варіантів з валідною контрольною цифрою
      final variants = <String>[];
      for (final g9 in genderDigits) {
        for (int mid = 0; mid < 10 && variants.length < 5; mid++) {
          for (int mid2 = 0; mid2 < 10 && variants.length < 5; mid2++) {
            for (int mid3 = 0; mid3 < 10 && variants.length < 5; mid3++) {
              final candidate = '$daysStr$mid$mid2$mid3${g9}0'; // 10 цифр з тимчасовою контрольною
              // Розрахувати правильну контрольну цифру
              final digits = candidate.split('').map((c) => int.parse(c)).toList();
              int sum = 0;
              for (int i = 0; i < 9; i++) sum += digits[i] * _w1[i];
              int check = sum % 11;
              if (check == 10) {
                sum = 0;
                for (int i = 0; i < 9; i++) sum += digits[i] * _w2[i];
                check = sum % 11;
                if (check == 10) check = 0;
              }
              final valid = '$daysStr$mid$mid2$mid3$g9$check';
              if (!variants.contains(valid)) variants.add(valid);
              if (variants.length >= 8) break;
            }
            if (variants.length >= 8) break;
          }
          if (variants.length >= 8) break;
        }
        if (variants.length >= 8) break;
      }
      setState(() => _reverseResult = variants);
      widget.onLog("ІПН зворотній: ${variants.length} варіантів для $dateStr");
    } catch(_) {
      setState(() => _reverseResult = ['Помилка розрахунку']);
    }
  }

  @override Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.bg,
    appBar: AppBar(
      title: const Text('ДЕШИФРАТОР ІПН'),
      bottom: TabBar(controller: _tabs, labelColor: AppColors.uaYellow, unselectedLabelColor: AppColors.textSec, indicatorColor: AppColors.uaYellow,
        tabs: const [Tab(text: 'ДЕШИФРУВАТИ'), Tab(text: 'ЗВОРОТНІЙ')]),
    ),
    body: TabBarView(controller: _tabs, children: [
      // ── Вкладка 1: Дешифрування ──
      SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(controller: _c, keyboardType: TextInputType.number, maxLength: 10,
            style: const TextStyle(color: AppColors.textPri, fontSize: 20, letterSpacing: 3, fontFamily: 'JetBrainsMono'),
            decoration: const InputDecoration(labelText: 'ВВЕДІТЬ 10 ЦИФР РНОКПП', counterStyle: TextStyle(color: AppColors.textHint))),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            icon: const Icon(Icons.fingerprint, size: 18),
            label: const Text('ДЕШИФРУВАТИ', style: TextStyle(color: Colors.white, letterSpacing: 1)),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.uaBlue, minimumSize: const Size(double.infinity, 46)),
            onPressed: _decode,
          ),
          if (_validationMsg != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity, padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _validationMsg!.startsWith('✅') ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _validationMsg!.startsWith('✅') ? Colors.green.withOpacity(0.3) : Colors.red.withOpacity(0.3)),
              ),
              child: Text(_validationMsg!, style: TextStyle(fontSize: 12, color: _validationMsg!.startsWith('✅') ? Colors.greenAccent : Colors.redAccent)),
            ),
          ],
          const SizedBox(height: 16),
          if (_r != null) ..._r!.entries.map((e) => InkWell(
            onTap: () { Clipboard.setData(ClipboardData(text: e.value)); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Скопійовано!'), backgroundColor: AppColors.uaBlue, duration: Duration(seconds: 1))); },
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.03), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
              child: Row(children: [
                SizedBox(width: 120, child: Text(e.key, style: const TextStyle(color: AppColors.textSec, fontSize: 10, letterSpacing: 0.5))),
                Expanded(child: Text(e.value, style: const TextStyle(color: Colors.greenAccent, fontSize: 16, fontWeight: FontWeight.bold))),
                const Icon(Icons.copy, size: 12, color: AppColors.textHint),
              ]),
            ),
          )),
        ]),
      ),

      // ── Вкладка 2: Зворотній ──
      SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Введіть дату народження та стать — отримаєте можливі варіанти ІПН з валідною контрольною цифрою.',
            style: TextStyle(fontSize: 11, color: AppColors.textSec)),
          const SizedBox(height: 12),
          TextField(controller: _dateCtrl, style: const TextStyle(color: AppColors.textPri),
            decoration: const InputDecoration(labelText: 'ДАТА НАРОДЖЕННЯ (ДД.ММ.РРРР)', hintText: '12.05.1980')),
          const SizedBox(height: 10),
          Row(children: [
            const Text('СТАТЬ: ', style: TextStyle(color: AppColors.textSec, fontSize: 12)),
            const SizedBox(width: 10),
            ChoiceChip(label: const Text('Чоловіча'), selected: _gender == 'Чоловіча', selectedColor: AppColors.uaYellow,
              onSelected: (_) => setState(() => _gender = 'Чоловіча')),
            const SizedBox(width: 8),
            ChoiceChip(label: const Text('Жіноча'), selected: _gender == 'Жіноча', selectedColor: AppColors.uaYellow,
              onSelected: (_) => setState(() => _gender = 'Жіноча')),
          ]),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            icon: const Icon(Icons.search, size: 18),
            label: const Text('РОЗРАХУВАТИ', style: TextStyle(color: Colors.white, letterSpacing: 1)),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.uaBlue, minimumSize: const Size(double.infinity, 46)),
            onPressed: _reverseCalc,
          ),
          const SizedBox(height: 16),
          if (_reverseResult != null) ...[
            Text('Можливі варіанти ІПН (${_reverseResult!.length}):', style: const TextStyle(fontSize: 11, color: AppColors.textSec)),
            const SizedBox(height: 8),
            ..._reverseResult!.map((v) => InkWell(
              onTap: () { Clipboard.setData(ClipboardData(text: v)); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Скопійовано!'), backgroundColor: AppColors.uaBlue, duration: Duration(seconds: 1))); },
              child: Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.03), borderRadius: BorderRadius.circular(6), border: Border.all(color: AppColors.border)),
                child: Row(children: [
                  Expanded(child: Text(v, style: const TextStyle(color: Colors.greenAccent, fontFamily: 'JetBrainsMono', fontSize: 16, letterSpacing: 2))),
                  const Icon(Icons.copy, size: 14, color: AppColors.textHint),
                ]),
              ),
            )),
          ],
        ]),
      ),
    ]),
  );
}

// ─────────────────────────────────────────────
// ВАЛІДАТОР КАРТОК (Алгоритм Луна)
// ─────────────────────────────────────────────
class FinScreen extends StatefulWidget {
  final Function(String) onLog;
  const FinScreen({super.key, required this.onLog});
  @override State<FinScreen> createState() => _FinScreenState();
}
class _FinScreenState extends State<FinScreen> {
  final _c = TextEditingController(); String _r = ""; String _system = ""; String _cardType = "";
  void _check() {
    String cc = _c.text.replaceAll(RegExp(r'[\s\-\.]'), ''); if (cc.isEmpty || cc.length < 8) return;
    // Алгоритм Луна
    int s = 0; bool a = false;
    for (int i = cc.length - 1; i >= 0; i--) {
      int n = int.tryParse(cc[i]) ?? 0;
      if (a) { n *= 2; if (n > 9) n -= 9; }
      s += n; a = !a;
    }
    final valid = s % 10 == 0;
    // Визначення платіжної системи
    String sys = 'Невідома', type = '';
    if (cc.startsWith('4')) { sys = 'Visa'; type = cc.length == 16 ? 'Credit/Debit' : cc.length == 13 ? 'Electron' : ''; }
    else if (cc.startsWith('5') && int.parse(cc[1]) >= 1 && int.parse(cc[1]) <= 5) { sys = 'Mastercard'; type = 'Credit/Debit'; }
    else if (cc.startsWith('2') && int.parse(cc.substring(0, 4)) >= 2221 && int.parse(cc.substring(0, 4)) <= 2720) { sys = 'Mastercard'; type = 'Credit/Debit (2-серія)'; }
    else if (cc.startsWith('34') || cc.startsWith('37')) { sys = 'American Express'; type = 'Charge Card'; }
    else if (cc.startsWith('62')) { sys = 'UnionPay'; type = 'Credit/Debit'; }
    else if (cc.startsWith('2200') || cc.startsWith('2201') || cc.startsWith('2202') || cc.startsWith('2203') || cc.startsWith('2204')) { sys = 'МІР (РФ)'; type = '🚨 РОСІЙСЬКА КАРТКА'; }
    else if (cc.startsWith('3528') || (cc.startsWith('35') && int.parse(cc.substring(2, 4)) >= 28 && int.parse(cc.substring(2, 4)) <= 89)) { sys = 'JCB'; type = 'Credit'; }
    else if (cc.startsWith('6011') || cc.startsWith('65')) { sys = 'Discover'; type = 'Credit'; }
    else if (cc.startsWith('9')) { sys = 'ПРОСТІР (UA)'; type = 'Національна платіжна система'; }
    setState(() {
      _r = valid ? "✅ ВАЛІДНА (Луна: OK)" : "❌ НЕВАЛІДНА (Луна: FAIL)";
      _system = sys;
      _cardType = type;
    });
    widget.onLog("Фінанси: $sys ${valid ? 'VALID' : 'INVALID'} — BIN: ${cc.substring(0, math.min(6, cc.length))}");
  }
  @override Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.bg,
    appBar: AppBar(title: const Text('АНАЛІЗАТОР КАРТОК')),
    body: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextField(controller: _c, style: const TextStyle(color: AppColors.textPri, fontFamily: 'JetBrainsMono', letterSpacing: 2, fontSize: 18), keyboardType: TextInputType.number, maxLength: 19,
        decoration: const InputDecoration(labelText: 'НОМЕР КАРТКИ', hintText: '4149 XXXX XXXX XXXX', counterStyle: TextStyle(color: AppColors.textHint))),
      const SizedBox(height: 10),
      ElevatedButton.icon(
        icon: const Icon(Icons.credit_score, size: 18),
        label: const Text('ПЕРЕВІРИТИ', style: TextStyle(color: Colors.white, letterSpacing: 1)),
        style: ElevatedButton.styleFrom(backgroundColor: AppColors.uaBlue, minimumSize: const Size(double.infinity, 46)),
        onPressed: _check,
      ),
      const SizedBox(height: 20),
      if (_r.isNotEmpty) ...[
        Text(_r, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _r.contains('ВАЛІДНА') ? Colors.greenAccent : Colors.redAccent)),
        const SizedBox(height: 16),
        if (_system.isNotEmpty) Container(
          width: double.infinity, padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _system.contains('МІР') ? Colors.red.withOpacity(0.1) : Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _system.contains('МІР') ? Colors.redAccent.withOpacity(0.5) : AppColors.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.credit_card, color: AppColors.accent, size: 18),
              const SizedBox(width: 8),
              Text(_system, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _system.contains('МІР') ? Colors.redAccent : AppColors.textPri)),
            ]),
            if (_cardType.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(_cardType, style: TextStyle(fontSize: 12, color: _cardType.contains('🚨') ? Colors.redAccent : AppColors.textSec)),
            ],
            const SizedBox(height: 8),
            Text('BIN: ${_c.text.replaceAll(RegExp(r"[\\s\\-]"), "").substring(0, math.min(6, _c.text.replaceAll(RegExp(r"[\\s\\-]"), "").length))}',
              style: const TextStyle(fontSize: 11, color: AppColors.textHint, fontFamily: 'JetBrainsMono')),
          ]),
        ),
      ],
      const Spacer(),
      const Text('Підтримує: Visa, Mastercard, AmEx, UnionPay, JCB, Discover, МІР, ПРОСТІР',
        style: TextStyle(fontSize: 9, color: AppColors.textHint), textAlign: TextAlign.center),
    ])),
  );
}

// ─────────────────────────────────────────────
// АВТО НОМЕРИ + VIN ДЕКОДЕР
// ─────────────────────────────────────────────
class AutoScreen extends StatefulWidget {
  final Function(String) onLog;
  const AutoScreen({super.key, required this.onLog});
  @override State<AutoScreen> createState() => _AutoScreenState();
}

class _AutoResult {
  final String region, flag, note;
  const _AutoResult({required this.region, required this.flag, this.note = ''});
}

class _VinResult {
  final String country, make, year, plant, note;
  const _VinResult({required this.country, required this.make, required this.year, required this.plant, this.note = ''});
}

class _AutoScreenState extends State<AutoScreen> with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _plateCtrl = TextEditingController();
  final _vinCtrl   = TextEditingController();
  _AutoResult? _plateResult;
  _VinResult?  _vinResult;
  String       _vinError = '';

  // ── База регіонів (розширена) ──
  static const Map<String, List<String>> _reg = {
    // [регіон, прапор, примітка]
    'AA': ['м. Київ',              '🇺🇦', ''],
    'KA': ['м. Київ',              '🇺🇦', ''],
    'TT': ['м. Київ (таксі/спец)','🇺🇦', ''],
    'AB': ['Вінницька обл.',       '🇺🇦', 'Вінниця'],
    'KB': ['Вінницька обл.',       '🇺🇦', ''],
    'AC': ['Волинська обл.',       '🇺🇦', 'Луцьк'],
    'AE': ['Дніпропетровська обл.','🇺🇦', 'Дніпро'],
    'KE': ['Дніпропетровська обл.','🇺🇦', ''],
    'AH': ['Донецька обл.',        '🇺🇦', '⚠ Частково окупована'],
    'KH': ['Донецька обл.',        '🇺🇦', ''],
    'AM': ['Житомирська обл.',     '🇺🇦', 'Житомир'],
    'AO': ['Закарпатська обл.',    '🇺🇦', 'Ужгород'],
    'AP': ['Запорізька обл.',      '🇺🇦', 'Запоріжжя ⚠'],
    'AT': ['Івано-Франківська обл.','🇺🇦','Івано-Франківськ'],
    'AI': ['Київська обл.',        '🇺🇦', ''],
    'KI': ['Київська обл.',        '🇺🇦', ''],
    'BA': ['Кіровоградська обл.',  '🇺🇦', 'Кропивницький'],
    'BB': ['Луганська обл.',       '🇺🇦', '⚠ Частково окупована'],
    'BC': ['Львівська обл.',       '🇺🇦', 'Львів'],
    'HC': ['Львівська обл.',       '🇺🇦', ''],
    'BE': ['Миколаївська обл.',    '🇺🇦', 'Миколаїв'],
    'BH': ['Одеська обл.',         '🇺🇦', 'Одеса'],
    'HH': ['Одеська обл.',         '🇺🇦', ''],
    'BI': ['Полтавська обл.',      '🇺🇦', 'Полтава'],
    'BK': ['Рівненська обл.',      '🇺🇦', 'Рівне'],
    'BM': ['Сумська обл.',         '🇺🇦', 'Суми'],
    'BO': ['Тернопільська обл.',   '🇺🇦', 'Тернопіль'],
    'AX': ['Харківська обл.',      '🇺🇦', 'Харків'],
    'KX': ['Харківська обл.',      '🇺🇦', ''],
    'BT': ['Херсонська обл.',      '🇺🇦', '⚠ Частково окупована'],
    'BX': ['Хмельницька обл.',     '🇺🇦', 'Хмельницький'],
    'CA': ['Черкаська обл.',       '🇺🇦', 'Черкаси'],
    'CB': ['Чернігівська обл.',    '🇺🇦', 'Чернігів'],
    'CE': ['Чернівецька обл.',     '🇺🇦', 'Чернівці'],
    'AK': ['АР Крим',              '🇺🇦', '⚠ ТИМЧАСОВО ОКУПОВАНИЙ'],
    'CH': ['м. Севастополь',       '🇺🇦', '⚠ ТИМЧАСОВО ОКУПОВАНИЙ'],
    // Старий формат (3 літери + цифри)
    'КИЇ': ['м. Київ (старий)',    '🇺🇦', ''],
  };

  // ── WMI база для VIN (120+ записів) ──
  static const Map<String, List<String>> _wmi = {
    // ── Німеччина ──
    'WBA': ['Німеччина', 'BMW'], 'WBS': ['Німеччина', 'BMW M'], 'WBY': ['Німеччина', 'BMW i'],
    'WDD': ['Німеччина', 'Mercedes-Benz'], 'WDC': ['Німеччина', 'Mercedes-Benz (SUV)'], 'WMX': ['Німеччина', 'Mercedes-AMG'],
    'WAU': ['Німеччина', 'Audi'], 'WUA': ['Німеччина', 'Audi Sport'],
    'WVW': ['Німеччина', 'Volkswagen'], 'WV1': ['Німеччина', 'VW комерційні'], 'WV2': ['Німеччина', 'VW Bus'], 'WV3': ['Німеччина', 'VW Truck'],
    'WF0': ['Німеччина', 'Ford DE'], 'WF1': ['Німеччина', 'Ford DE (вантаж.)'],
    'WP0': ['Німеччина', 'Porsche'], 'WP1': ['Німеччина', 'Porsche SUV'],
    'W0L': ['Німеччина', 'Opel'], 'W0V': ['Німеччина', 'Opel (комерц.)'],
    'WMA': ['Німеччина', 'MAN Truck'], 'WDB': ['Німеччина', 'Mercedes (вантаж.)'],
    // ── Велика Британія ──
    'SAJ': ['Велика Британія', 'Jaguar'], 'SAL': ['Велика Британія', 'Land Rover'],
    'SCA': ['Велика Британія', 'Rolls-Royce'], 'SCB': ['Велика Британія', 'Bentley'],
    'SCE': ['Велика Британія', 'DeLorean'], 'SCC': ['Велика Британія', 'Lotus'],
    'SDB': ['Велика Британія', 'Peugeot UK'], 'SFD': ['Велика Британія', 'Alexander Dennis'],
    'SAR': ['Велика Британія', 'Rover'], 'SBM': ['Велика Британія', 'McLaren'],
    'TRU': ['Велика Британія', 'Audi UK'],
    // ── Франція ──
    'VF1': ['Франція', 'Renault'], 'VF2': ['Франція', 'Renault Truck'],
    'VF3': ['Франція', 'Peugeot'], 'VF7': ['Франція', 'Citroën'],
    'VF8': ['Франція', 'Matra/Alpine'], 'VNE': ['Франція', 'Renault Dacia'],
    // ── Іспанія / Італія ──
    'VSS': ['Іспанія', 'SEAT'], 'VS6': ['Іспанія', 'Ford ES'], 'VS7': ['Іспанія', 'Citroën ES'],
    'ZAR': ['Італія', 'Alfa Romeo'], 'ZFF': ['Італія', 'Ferrari'], 'ZHW': ['Італія', 'Lamborghini'],
    'ZLA': ['Італія', 'Lancia'], 'ZAM': ['Італія', 'Maserati'], 'ZDM': ['Італія', 'Ducati'],
    'ZAP': ['Італія', 'Piaggio'], 'ZFA': ['Італія', 'Fiat'], 'ZFC': ['Італія', 'Fiat (комерц.)'],
    // ── Чехія / Польща / Румунія ──
    'TMA': ['Чехія', 'Hyundai CZ'], 'TMB': ['Чехія', 'Škoda'],
    'SUP': ['Польща', 'Solaris Bus'], 'SU9': ['Польща', 'Solbus'],
    'UU1': ['Румунія', 'Dacia'], 'UU6': ['Румунія', 'Dacia (нова)'],
    // ── Туреччина ──
    'NMT': ['Туреччина', 'Toyota TR'], 'NM0': ['Туреччина', 'Ford TR'], 'NM4': ['Туреччина', 'Tofas/Fiat TR'],
    // ── США ──
    '1HG': ['США', 'Honda NA'], '1G1': ['США', 'Chevrolet'], '1G4': ['США', 'Buick'], '1G6': ['США', 'Cadillac'],
    '1GC': ['США', 'Chevrolet Truck'], '1GT': ['США', 'GMC Truck'],
    '1FT': ['США', 'Ford Truck'], '1FA': ['США', 'Ford Auto'], '1FM': ['США', 'Ford SUV'],
    '1LN': ['США', 'Lincoln'], '1ME': ['США', 'Mercury'],
    '1N4': ['США', 'Nissan NA'], '1N6': ['США', 'Nissan Truck NA'],
    '1C3': ['США', 'Chrysler'], '1C4': ['США', 'Jeep'], '1C6': ['США', 'RAM'],
    '2T1': ['США', 'Toyota NA'], '2T3': ['США', 'Toyota SUV NA'],
    '4T1': ['США', 'Toyota (4)'], '5YJ': ['США', 'Tesla'], '5Y2': ['США', 'Tesla (нова)'],
    '7SA': ['США', 'Tesla (7)'],
    // ── Канада / Мексика ──
    '2HG': ['Канада', 'Honda CA'], '2HK': ['Канада', 'Honda CR-V CA'], '2HJ': ['Канада', 'Honda Truck CA'],
    '3VW': ['Мексика', 'Volkswagen MX'], '3FA': ['Мексика', 'Ford MX'], '3N1': ['Мексика', 'Nissan MX'],
    // ── Японія ──
    'JHM': ['Японія', 'Honda JP'], 'JHL': ['Японія', 'Honda SUV JP'],
    'JTD': ['Японія', 'Toyota'], 'JTE': ['Японія', 'Toyota SUV'], 'JTJ': ['Японія', 'Lexus'],
    'JN1': ['Японія', 'Nissan'], 'JN8': ['Японія', 'Nissan SUV'],
    'JMB': ['Японія', 'Mitsubishi'], 'JMY': ['Японія', 'Mitsubishi (нова)'],
    'JS1': ['Японія', 'Suzuki'], 'JS2': ['Японія', 'Suzuki Auto'],
    'JMA': ['Японія', 'Mazda JP'], 'JM1': ['Японія', 'Mazda'], 'JM3': ['Японія', 'Mazda SUV'],
    'JF1': ['Японія', 'Subaru'], 'JF2': ['Японія', 'Subaru SUV'],
    'JYA': ['Японія', 'Yamaha'], 'JKA': ['Японія', 'Kawasaki'],
    // ── Корея ──
    'KMH': ['Південна Корея', 'Hyundai'], 'KMF': ['Південна Корея', 'Hyundai (нова)'], '5NP': ['Південна Корея', 'Hyundai NA'],
    'KNA': ['Південна Корея', 'Kia'], 'KND': ['Південна Корея', 'Kia SUV'], 'KNM': ['Південна Корея', 'Renault Samsung'],
    'KPT': ['Південна Корея', 'SsangYong'],
    // ── Росія (⚠) ──
    'XTA': ['Росія ⚠', 'ВАЗ/Lada'], 'XTT': ['Росія ⚠', 'ГАЗ'], 'X7L': ['Росія ⚠', 'КАМАЗ'],
    'Y6D': ['Росія ⚠', 'УАЗ'], 'X7M': ['Росія ⚠', 'ЛіАЗ'], 'XTH': ['Росія ⚠', 'ГАЗ (нова)'],
    'Z94': ['Росія ⚠', 'Hyundai RU'], 'XWE': ['Росія ⚠', 'ЗАЗ→AvtoVAZ'],
    // ── Білорусь (⚠) ──
    'Y3M': ['Білорусь ⚠', 'МАЗ'], 'Y4M': ['Білорусь ⚠', 'БелАЗ'],
    // ── Китай ──
    'LB1': ['Китай', 'BYD'], 'LB2': ['Китай', 'Geely'],
    'LFV': ['Китай', 'VW CN'], 'LHG': ['Китай', 'Honda CN'], 'LSG': ['Китай', 'GM CN'],
    'LVS': ['Китай', 'Volvo CN'], 'LJD': ['Китай', 'Dongfeng'],
    'LGX': ['Китай', 'BYD (нова)'], 'LPA': ['Китай', 'Changan'],
    'LDC': ['Китай', 'Dongfeng Truck'], 'LS5': ['Китай', 'Chery'],
    'LVR': ['Китай', 'Changan (нова)'], 'LBV': ['Китай', 'BMW CN'],
    // ── Індія ──
    'MA1': ['Індія', 'Mahindra'], 'MA3': ['Індія', 'Suzuki IN'], 'MAJ': ['Індія', 'Ford IN'],
    'MAK': ['Індія', 'Honda IN'], 'MAL': ['Індія', 'Hyundai IN'], 'MBJ': ['Індія', 'Toyota IN'],
    'MC2': ['Індія', 'Tata'],
    // ── Швеція / Інші ──
    'YV1': ['Швеція', 'Volvo'], 'YV4': ['Швеція', 'Volvo (нова)'], 'YS3': ['Швеція', 'Saab'],
    'AAV': ['ПАР', 'VW ZA'], 'AHT': ['ПАР', 'Toyota ZA'],
    'PE1': ['Філіппіни', 'Mitsubishi PH'],
    'MRH': ['Таїланд', 'Honda TH'], 'MR0': ['Таїланд', 'Toyota TH'],
    '6T1': ['Австралія', 'Toyota AU'], '6G1': ['Австралія', 'Holden'],
    '9BW': ['Бразилія', 'VW BR'], '9BG': ['Бразилія', 'Chevrolet BR'],
  };

  // Рік виготовлення по 10-му символу VIN
  static const Map<String, String> _vinYear = {
    'A':'2010','B':'2011','C':'2012','D':'2013','E':'2014','F':'2015',
    'G':'2016','H':'2017','J':'2018','K':'2019','L':'2020','M':'2021',
    'N':'2022','P':'2023','R':'2024','S':'2025','T':'2026',
    'W':'1998','X':'1999','Y':'2000','1':'2001','2':'2002','3':'2003',
    '4':'2004','5':'2005','6':'2006','7':'2007','8':'2008','9':'2009',
  };

  // Транслітерація UA→LAT
  String _normalizePlate(String s) {
    const ua2lat = {'А':'A','В':'B','Е':'E','І':'I','К':'K','М':'M',
                    'Н':'H','О':'O','Р':'P','С':'C','Т':'T','Х':'X'};
    return s.split('').map((c) => ua2lat[c] ?? c).join();
  }

  void _checkPlate() {
    FocusScope.of(context).unfocus();
    final raw = _plateCtrl.text.trim().toUpperCase();
    final s   = _normalizePlate(raw);
    if (s.length < 2) return;
    final key = s.substring(0, 2);
    final data = _reg[key];
    setState(() {
      if (data != null) {
        _plateResult = _AutoResult(region: data[0], flag: data[1], note: data[2]);
      } else {
        _plateResult = const _AutoResult(region: 'Невідомий регіон або новий формат', flag: '❓');
      }
    });
    HapticFeedback.lightImpact();
    widget.onLog("Авто: $raw → ${_plateResult?.region ?? '?'}");
  }

  void _checkVin() {
    FocusScope.of(context).unfocus();
    final vin = _vinCtrl.text.trim().toUpperCase();
    if (vin.length != 17) {
      setState(() { _vinResult = null; _vinError = 'VIN має містити рівно 17 символів'; });
      return;
    }
    // Валідація контрольного символу (позиція 9)
    const vals = {'A':1,'B':2,'C':3,'D':4,'E':5,'F':6,'G':7,'H':8,
                  'J':1,'K':2,'L':3,'M':4,'N':5,'P':7,'R':9,'S':2,
                  'T':3,'U':4,'V':5,'W':6,'X':7,'Y':8,'Z':9,
                  '0':0,'1':1,'2':2,'3':3,'4':4,'5':5,'6':6,'7':7,'8':8,'9':9};
    const weights = [8,7,6,5,4,3,2,10,0,9,8,7,6,5,4,3,2];
    int sum = 0;
    bool valid = true;
    for (int i = 0; i < 17; i++) {
      final v = vals[vin[i]];
      if (v == null) { valid = false; break; }
      sum += v * weights[i];
    }
    final check = sum % 11;
    final checkChar = check == 10 ? 'X' : check.toString();
    final isValid = !valid ? false : (vin[8] == checkChar);

    final wmi     = vin.substring(0, 3);
    final wmiData = _wmi[wmi] ?? _wmi[vin.substring(0, 2)];
    final yearChar = vin.length > 9 ? vin[9] : '';
    final year     = _vinYear[yearChar] ?? 'невідомий';

    setState(() {
      _vinError = '';
      _vinResult = _VinResult(
        country: wmiData?[0] ?? 'Невідома країна',
        make:    wmiData?[1] ?? 'Невідомий виробник (WMI: $wmi)',
        year:    year,
        plant:   vin.substring(0, 3),
        note:    isValid ? '✅ Контрольна сума вірна' : '⚠ Можлива підробка VIN',
      );
    });
    HapticFeedback.lightImpact();
    widget.onLog("VIN: $vin → ${_vinResult?.make} $year");
  }

  @override void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }
  @override void dispose() { _tabs.dispose(); _plateCtrl.dispose(); _vinCtrl.dispose(); super.dispose(); }

  @override Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.bg,
    appBar: AppBar(
      title: const Text('АВТО АНАЛІЗАТОР'),
      bottom: TabBar(
        controller: _tabs,
        labelColor: AppColors.uaYellow,
        unselectedLabelColor: AppColors.textSec,
        indicatorColor: AppColors.uaYellow,
        tabs: const [Tab(text: 'НОМЕРНИЙ ЗНАК'), Tab(text: 'VIN-КОД')],
      ),
    ),
    body: TabBarView(controller: _tabs, children: [
      // ── Вкладка 1: Номерний знак ──
      Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          controller: _plateCtrl,
          style: const TextStyle(color: AppColors.textPri, letterSpacing: 3, fontSize: 20, fontFamily: 'JetBrainsMono'),
          textCapitalization: TextCapitalization.characters,
          onSubmitted: (_) => _checkPlate(),
          decoration: const InputDecoration(
            labelText: 'НОМЕРНИЙ ЗНАК',
            hintText: 'АА1234ВВ або AA1234BB',
            prefixIcon: Icon(Icons.directions_car, color: AppColors.accent),
          ),
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          icon: const Icon(Icons.search, size: 18),
          label: const Text('ВИЗНАЧИТИ РЕГІОН', style: TextStyle(letterSpacing: 1)),
          onPressed: _checkPlate,
        ),
        const SizedBox(height: 24),
        if (_plateResult != null) _plateResultCard(_plateResult!),
        const Spacer(),
        const Text('Підтримує старий (АА 1234 ВВ) і новий формат',
            style: TextStyle(fontSize: 10, color: AppColors.textHint)),
      ])),

      // ── Вкладка 2: VIN ──
      Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          controller: _vinCtrl,
          style: const TextStyle(color: AppColors.textPri, letterSpacing: 2, fontSize: 14, fontFamily: 'JetBrainsMono'),
          textCapitalization: TextCapitalization.characters,
          maxLength: 17,
          onSubmitted: (_) => _checkVin(),
          decoration: const InputDecoration(
            labelText: 'VIN-КОД (17 символів)',
            hintText: 'WBA3A5G59DNP26082',
            prefixIcon: Icon(Icons.pin, color: AppColors.accent),
            counterStyle: TextStyle(color: AppColors.textHint),
          ),
        ),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          icon: const Icon(Icons.manage_search, size: 18),
          label: const Text('ДЕКОДУВАТИ VIN', style: TextStyle(letterSpacing: 1)),
          onPressed: _checkVin,
        ),
        const SizedBox(height: 16),
        if (_vinError.isNotEmpty) Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.red.withOpacity(0.3)),
          ),
          child: Text(_vinError, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
        ),
        if (_vinResult != null) _vinResultCard(_vinResult!),
      ])),
    ]),
  );

  Widget _plateResultCard(_AutoResult r) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.04),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: r.note.contains('ОКУП') || r.note.contains('окупов')
          ? Colors.red.withOpacity(0.5) : AppColors.uaBlue.withOpacity(0.4)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(r.flag, style: const TextStyle(fontSize: 28)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('РЕГІОН РЕЄСТРАЦІЇ', style: TextStyle(fontSize: 9, color: AppColors.textSec, letterSpacing: 1)),
          const SizedBox(height: 4),
          Text(r.region, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.greenAccent)),
        ])),
      ]),
      if (r.note.isNotEmpty) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: r.note.contains('⚠') ? Colors.orange.withOpacity(0.1) : Colors.green.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(r.note, style: TextStyle(
            fontSize: 12,
            color: r.note.contains('⚠') ? Colors.orangeAccent : Colors.greenAccent,
          )),
        ),
      ],
    ]),
  );

  Widget _vinResultCard(_VinResult r) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.04),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: r.make.contains('⚠')
          ? Colors.red.withOpacity(0.5) : AppColors.uaBlue.withOpacity(0.4)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _vinRow(Icons.directions_car,    'ВИРОБНИК',   r.make),
      const SizedBox(height: 10),
      _vinRow(Icons.public,            'КРАЇНА',     r.country),
      const SizedBox(height: 10),
      _vinRow(Icons.calendar_today,    'РІК ВИПУСКУ',r.year),
      const SizedBox(height: 10),
      _vinRow(Icons.qr_code,           'WMI КОД',    r.plant),
      if (r.note.isNotEmpty) ...[
        const Divider(color: AppColors.border, height: 20),
        Text(r.note, style: TextStyle(
          fontSize: 12, fontWeight: FontWeight.bold,
          color: r.note.startsWith('✅') ? Colors.greenAccent : Colors.orangeAccent,
        )),
      ],
    ]),
  );

  Widget _vinRow(IconData icon, String label, String value) => Row(children: [
    Container(width: 30, height: 30,
      decoration: BoxDecoration(color: AppColors.uaBlue.withOpacity(0.12), borderRadius: BorderRadius.circular(7)),
      child: Icon(icon, size: 15, color: AppColors.accent)),
    const SizedBox(width: 10),
    SizedBox(width: 100, child: Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSec, letterSpacing: 0.5))),
    Expanded(child: Text(value, style: TextStyle(
      fontSize: 13, fontWeight: FontWeight.w500,
      color: value.contains('⚠') ? Colors.orangeAccent : AppColors.textPri,
    ))),
  ]);
}

// ─────────────────────────────────────────────
// АНАЛІЗАТОР ТЕЛЕФОННИХ НОМЕРІВ
// ─────────────────────────────────────────────
class PhoneScreen extends StatefulWidget {
  final Function(String) onLog;
  const PhoneScreen({super.key, required this.onLog});
  @override State<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneResult {
  final String country, flag, operator, type, region, warning;
  final bool isDangerous;
  const _PhoneResult({
    required this.country, required this.flag, required this.operator,
    required this.type,    required this.region, required this.warning,
    required this.isDangerous,
  });
}

class _PhoneScreenState extends State<PhoneScreen> {
  final _c = TextEditingController();
  _PhoneResult? _result;
  Map<String, List<dynamic>> _db = {};
  bool _dbLoaded = false;

  @override void initState() { super.initState(); _loadDb(); }

  void _loadDb() async {
    try {
      final jsonStr = await rootBundle.loadString('assets/phone_db.json');
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final prefixes = data['prefixes'] as Map<String, dynamic>;
      final db = <String, List<dynamic>>{};
      for (final entry in prefixes.entries) {
        db[entry.key] = (entry.value as List<dynamic>);
      }
      if (!mounted) return;
      setState(() { _db = db; _dbLoaded = true; });
    } catch (e) {
      // Fallback — мінімальна вбудована база
      if (!mounted) return;
      setState(() {
        _db = {
          '+380': ['Україна', '🇺🇦', 'Невідомий оператор', 'Мобільний', '', '', 0],
          '+7':   ['Росія/Казахстан', '🇷🇺', 'Невідомий оператор', 'Мобільний', '', '🚨 РОСІЯ або Казахстан', 1],
        };
        _dbLoaded = true;
      });
    }
  }
  // ── Нормалізація вводу ──────────────────────
  String _normalize(String raw) {
    // Залишаємо тільки цифри і +
    String s = raw.replaceAll(RegExp(r'[\s\-\(\)\.—]'), '');
    // 0XX → +380XX (без коду)
    if (s.startsWith('0') && !s.startsWith('00')) s = '+380$s';
    // 380XX → +380XX
    if (s.startsWith('380')) s = '+$s';
    // 8 0XX → +380XX (рос. формат)
    if (s.startsWith('80')) s = '+3${s.substring(1)}';
    if (!s.startsWith('+')) s = '+$s';
    return s;
  }

  // ── Пошук по базі ───────────────────────────
  _PhoneResult? _lookup(String normalized) {
    // Спробуємо від найдовшого префіксу до найкоротшого
    // Максимальна довжина ключа у базі ~ 10 символів (+380 512)
    for (int len = 10; len >= 2; len--) {
      if (normalized.length < len) continue;
      final key = normalized.substring(0, len);
      if (_db.containsKey(key)) {
        final v = _db[key]!;
        return _PhoneResult(
          country:     v[0] as String,
          flag:        v[1] as String,
          operator:    v[2] as String,
          type:        v[3] as String,
          region:      v[4] as String,
          warning:     v[5] as String,
          isDangerous: (v[6] as int) == 1,
        );
      }
    }
    return null;
  }

  void _analyze() {
    FocusScope.of(context).unfocus();
    final raw = _c.text.trim();
    if (raw.isEmpty) return;
    final normalized = _normalize(raw);
    final result = _lookup(normalized);
    setState(() => _result = result);
    if (result != null) {
      widget.onLog('ТЕЛЕФОН: ${result.country} / ${result.operator} — $raw');
    } else {
      widget.onLog('ТЕЛЕФОН: номер не розпізнано — $raw');
    }
  }

  @override void dispose() { _c.dispose(); super.dispose(); }

  @override Widget build(BuildContext context) {
    final r = _result;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('АНАЛІЗ НОМЕРА')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // ── Поле вводу ──
          Row(children: [
            Expanded(child: TextField(
              controller: _c,
              keyboardType: TextInputType.phone,
              style: const TextStyle(
                color: AppColors.textPri,
                fontFamily: 'JetBrainsMono',
                fontSize: 18,
                letterSpacing: 2,
              ),
              decoration: const InputDecoration(
                labelText: 'НОМЕР ТЕЛЕФОНУ',
                hintText: '+380 67 123 4567',
                prefixIcon: Icon(Icons.phone_outlined, color: AppColors.accent, size: 20),
              ),
              onSubmitted: (_) => _analyze(),
            )),
            const SizedBox(width: 10),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.uaBlue,
                minimumSize: const Size(60, 56),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _analyze,
              child: const Icon(Icons.search, color: Colors.white),
            ),
          ]),

          const SizedBox(height: 8),
          const Text(
            'Підтримує формати: +380671234567 · 0671234567 · 380671234567',
            style: TextStyle(fontSize: 10, color: AppColors.textHint),
          ),

          const SizedBox(height: 20),

          // ── Результат ──
          if (r == null && _c.text.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('НЕ РОЗПІЗНАНО', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                SizedBox(height: 4),
                Text('Номер не знайдено в базі префіксів.\nПеревірте формат або додайте +код_країни.',
                    style: TextStyle(color: AppColors.textSec, fontSize: 11)),
              ]),
            ),

          if (r != null) ...[
            // Блок небезпеки
            if (r.isDangerous)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
                ),
                child: Row(children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Text(r.warning,
                      style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 13))),
                ]),
              ),

            // Основний блок результату
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(r.isDangerous ? 0.02 : 0.04),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: r.isDangerous
                      ? Colors.red.withOpacity(0.3)
                      : AppColors.uaBlue.withOpacity(0.4),
                ),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Прапор + Країна
                Row(children: [
                  Text(r.flag, style: const TextStyle(fontSize: 32)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(r.country, style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPri,
                    )),
                    if (r.region.isNotEmpty)
                      Text(r.region, style: const TextStyle(fontSize: 12, color: AppColors.textSec)),
                  ])),
                ]),

                const SizedBox(height: 16),
                const Divider(color: AppColors.border, height: 1),
                const SizedBox(height: 14),

                // Рядки деталей
                _row(Icons.cell_tower_outlined,     'ОПЕРАТОР', r.operator),
                const SizedBox(height: 10),
                _row(Icons.phone_android_outlined,  'ТИП',      r.type),
                const SizedBox(height: 10),
                _row(Icons.tag,                     'ВВЕДЕНО',  _normalize(_c.text)),
              ]),
            ),

            const SizedBox(height: 12),

            // Кнопки дій
            Row(children: [
              Expanded(child: OutlinedButton.icon(
                icon: const Icon(Icons.copy, size: 16, color: AppColors.textSec),
                label: const Text('COPY', style: TextStyle(color: AppColors.textSec, letterSpacing: 0.8)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.border),
                  minimumSize: const Size(0, 46),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  final text = '${r.flag} ${r.country}\nОператор: ${r.operator}\nТип: ${r.type}${r.region.isNotEmpty ? '\nРегіон: ${r.region}' : ''}${r.warning.isNotEmpty ? '\n${r.warning}' : ''}';
                  Clipboard.setData(ClipboardData(text: text));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Скопійовано результат'), backgroundColor: AppColors.uaBlue,
                    duration: Duration(seconds: 1),
                  ));
                },
              )),
              const SizedBox(width: 10),
              Expanded(child: ElevatedButton.icon(
                icon: const Icon(Icons.share, size: 16),
                label: const Text('SHARE', style: TextStyle(letterSpacing: 0.8)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.uaYellow,
                  foregroundColor: Colors.black,
                  minimumSize: const Size(0, 46),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  final text = 'Аналіз номера ${_c.text}:\n${r.flag} ${r.country}\nОператор: ${r.operator}\nТип: ${r.type}${r.warning.isNotEmpty ? '\n${r.warning}' : ''}';
                  Clipboard.setData(ClipboardData(text: text));
                },
              )),
            ]),
          ],

          const Spacer(),

          // Підказка внизу
          Center(child: Text(
            'База: Україна (25 префіксів) · Росія (50+) · Білорусь · Польща · 30+ країн',
            style: const TextStyle(fontSize: 9, color: AppColors.textHint),
            textAlign: TextAlign.center,
          )),
          const SizedBox(height: 8),
        ]),
      ),
      );

  }

  Widget _row(IconData icon, String label, String value) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 15, color: AppColors.accent),
      const SizedBox(width: 8),
      SizedBox(width: 80, child: Text(label,
          style: const TextStyle(fontSize: 11, color: AppColors.textSec, letterSpacing: 0.5))),
      Expanded(child: Text(value,
          style: const TextStyle(fontSize: 13, color: AppColors.textPri, fontWeight: FontWeight.w500))),
    ],
  );
}

// ─────────────────────────────────────────────
// ГЕНЕРАТОР НІКНЕЙМІВ
// ─────────────────────────────────────────────
class NickScreen extends StatefulWidget {
  final Function(String) onLog;
  const NickScreen({super.key, required this.onLog});
  @override State<NickScreen> createState() => _NickScreenState();
}
class _NickScreenState extends State<NickScreen> {
  final _c = TextEditingController();
  List<Map<String, String>> _r = []; // {'nick': ..., 'cat': ...}

  // ── Транслітерація UA → LAT ──
  static const _ua2lat = {
    'а':'a','б':'b','в':'v','г':'h','ґ':'g','д':'d','е':'e','є':'ye',
    'ж':'zh','з':'z','и':'y','і':'i','ї':'yi','й':'y','к':'k','л':'l',
    'м':'m','н':'n','о':'o','п':'p','р':'r','с':'s','т':'t','у':'u',
    'ф':'f','х':'kh','ц':'ts','ч':'ch','ш':'sh','щ':'shch','ь':'',
    'ю':'yu','я':'ya',
  };

  // ── Leet-speak ──
  static const _leet = {'a':'4','e':'3','i':'1','o':'0','s':'5','t':'7','l':'1','g':'9'};

  String _translit(String s) => s.split('').map((c) => _ua2lat[c] ?? c).join();

  String _leetSpeak(String s) => s.split('').map((c) => _leet[c] ?? c).join();

  void _gen() {
    final raw = _c.text.trim(); if (raw.isEmpty) return;
    FocusScope.of(context).unfocus();

    final base = raw.toLowerCase().replaceAll(' ', '_');
    final lat = _translit(base).replaceAll('__', '_');
    final noDot = lat.replaceAll('.', '');
    final leet = _leetSpeak(noDot);

    // Якщо є пробіл — розбиваємо на ім'я/прізвище
    final parts = raw.trim().toLowerCase().split(RegExp(r'\s+'));
    final hasTwoParts = parts.length >= 2;
    final first = hasTwoParts ? _translit(parts[0]) : '';
    final last = hasTwoParts ? _translit(parts[1]) : '';

    final nicks = <Map<String, String>>[];

    void add(String cat, String nick) {
      if (nick.isNotEmpty && !nicks.any((n) => n['nick'] == nick)) {
        nicks.add({'nick': nick, 'cat': cat});
      }
    }

    // Базові
    add('БАЗОВІ', noDot);
    add('БАЗОВІ', '${noDot}_osint');
    add('БАЗОВІ', 'the_$noDot');
    add('БАЗОВІ', 'real_$noDot');
    add('БАЗОВІ', '${noDot}2025');
    add('БАЗОВІ', '${noDot}2026');
    add('БАЗОВІ', '$noDot.ua');
    add('БАЗОВІ', 'sec_$noDot');
    add('БАЗОВІ', 'ua_$noDot');
    add('БАЗОВІ', '${noDot}_analyst');

    // Пермутації ім'я/прізвище
    if (hasTwoParts) {
      add('ПЕРМУТАЦІЇ', '$first$last');
      add('ПЕРМУТАЦІЇ', '$last$first');
      add('ПЕРМУТАЦІЇ', '${first}_$last');
      add('ПЕРМУТАЦІЇ', '${last}_$first');
      add('ПЕРМУТАЦІЇ', '${first}.${last}');
      add('ПЕРМУТАЦІЇ', '${first[0]}$last');
      add('ПЕРМУТАЦІЇ', '${first[0]}.$last');
      add('ПЕРМУТАЦІЇ', '$first${last[0]}');
      add('ПЕРМУТАЦІЇ', '${first[0]}${last[0]}');
    }

    // Leet-speak
    add('LEET', leet);
    add('LEET', '${leet}_osint');
    add('LEET', 'x_$leet');

    // Email варіанти
    final emailBase = hasTwoParts ? '$first.$last' : noDot;
    add('EMAIL', '$emailBase@gmail.com');
    add('EMAIL', '$emailBase@proton.me');
    add('EMAIL', '$emailBase@ukr.net');
    add('EMAIL', '$emailBase@outlook.com');
    if (hasTwoParts) {
      add('EMAIL', '${first[0]}$last@gmail.com');
      add('EMAIL', '$first$last@gmail.com');
    }

    // Посилання на платформи
    add('ПЛАТФОРМИ', 'https://t.me/$noDot');
    add('ПЛАТФОРМИ', 'https://instagram.com/$noDot');
    add('ПЛАТФОРМИ', 'https://facebook.com/$noDot');
    add('ПЛАТФОРМИ', 'https://x.com/$noDot');
    add('ПЛАТФОРМИ', 'https://linkedin.com/in/$noDot');
    add('ПЛАТФОРМИ', 'https://github.com/$noDot');

    setState(() => _r = nicks);
    widget.onLog("Нікнейми: ${nicks.length} варіантів для '$raw'");
  }

  @override Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.bg,
    appBar: AppBar(title: const Text('ГЕНЕРАТОР НІКІВ'),
      actions: [if (_r.isNotEmpty) TextButton(onPressed: () { Clipboard.setData(ClipboardData(text: _r.map((n) => n['nick']).join('\n'))); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Скопійовано всі варіанти'), backgroundColor: AppColors.uaBlue)); }, child: const Text('COPY ALL', style: TextStyle(color: AppColors.uaYellow, fontSize: 12)))],
    ),
    body: Column(children: [
      Padding(padding: const EdgeInsets.all(16), child: TextField(controller: _c, style: const TextStyle(color: AppColors.textPri), decoration: const InputDecoration(labelText: 'ПРІЗВИЩЕ ІМ\'Я або НІКНЕЙМ', hintText: 'Шевченко Тарас'))),
      ElevatedButton(onPressed: _gen, child: const Text('ЗГЕНЕРУВАТИ ВАРІАНТИ', style: TextStyle(color: Colors.white))),
      if (_r.isNotEmpty) Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('${_r.length} ВАРІАНТІВ', style: const TextStyle(fontSize: 11, color: AppColors.textSec, letterSpacing: 0.5)),
          Text('тап для копіювання', style: const TextStyle(fontSize: 10, color: AppColors.textHint)),
        ]),
      ),
      Expanded(child: _r.isEmpty
          ? const Center(child: Text('Введіть прізвище або нік', style: TextStyle(color: Colors.white24)))
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: _r.length,
              itemBuilder: (c, i) {
                final isNewCat = i == 0 || _r[i]['cat'] != _r[i - 1]['cat'];
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (isNewCat) Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 4, left: 4),
                    child: Text(_r[i]['cat']!, style: const TextStyle(fontSize: 10, color: AppColors.uaYellow, letterSpacing: 1, fontWeight: FontWeight.bold)),
                  ),
                  Card(
                    color: Colors.white.withOpacity(0.03),
                    margin: const EdgeInsets.only(bottom: 4),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: AppColors.border)),
                    child: ListTile(dense: true,
                      title: Text(_r[i]['nick']!, style: TextStyle(
                        color: _r[i]['cat'] == 'ПЛАТФОРМИ' ? AppColors.accent : Colors.greenAccent,
                        fontWeight: FontWeight.bold, fontFamily: 'JetBrainsMono', fontSize: 13,
                      )),
                      trailing: IconButton(icon: const Icon(Icons.copy, size: 16, color: AppColors.uaYellow), onPressed: () { Clipboard.setData(ClipboardData(text: _r[i]['nick']!)); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Скопійовано!'), backgroundColor: AppColors.uaBlue, duration: Duration(seconds: 1))); }),
                    ),
                  ),
                ]);
              },
            ),
      ),
    ]),
  );
}

// ─────────────────────────────────────────────
// ХРОНОЛОГІЯ ПОДІЙ
// ─────────────────────────────────────────────
class TimeScreen extends StatefulWidget {
  final Function(String) onLog;
  const TimeScreen({super.key, required this.onLog});
  @override State<TimeScreen> createState() => _TimeScreenState();
}
class _TimeScreenState extends State<TimeScreen> {
  List<Map<String, String>> _events = [];
  @override void initState() { super.initState(); _load(); }
  void _load() async {
    final events = await DatabaseHelper.instance.getTimeline();
    if (!mounted) return;
    setState(() => _events = events.map((e) => {'id': e.id, 'd': e.date, 't': e.description}).toList());
  }

  void _add() {
    final dC = TextEditingController(text: "${DateTime.now().day.toString().padLeft(2,'0')}.${DateTime.now().month.toString().padLeft(2,'0')}.${DateTime.now().year}");
    final tC = TextEditingController();
    showDialog(context: context, builder: (c) => AlertDialog(
      backgroundColor: AppColors.bgCard,
      title: const Text('НОВА ПОДІЯ', style: TextStyle(color: AppColors.textPri)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: dC, style: const TextStyle(color: AppColors.textPri), decoration: const InputDecoration(labelText: 'Дата')),
        const SizedBox(height: 10),
        TextField(controller: tC, maxLines: 3, style: const TextStyle(color: AppColors.textPri), decoration: const InputDecoration(labelText: 'Опис події')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('СКАСУВАТИ', style: TextStyle(color: AppColors.textSec))),
        ElevatedButton(onPressed: () async {
          final newId = '${DateTime.now().millisecondsSinceEpoch}';
          final ev = DbTimelineEvent(id: newId, date: dC.text, description: tC.text);
          await DatabaseHelper.instance.insertTimelineEvent(ev);
          setState(() => _events.add({'id': newId, 'd': dC.text, 't': tC.text}));
          Navigator.pop(c); widget.onLog("Таймлайн: додано подію");
        }, child: const Text('ДОДАТИ', style: TextStyle(color: Colors.white))),
      ],
    ));
  }
  @override Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.bg,
    appBar: AppBar(title: const Text('ХРОНОЛОГІЯ')),
    body: _events.isEmpty
        ? const Center(child: Text('ПОДІЙ НЕМАЄ', style: TextStyle(color: Colors.white24)))
        : ListView.builder(
            padding: const EdgeInsets.only(bottom: 90),
            itemCount: _events.length,
            itemBuilder: (c, i) => Card(
              color: Colors.white.withOpacity(0.03),
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: AppColors.border)),
              child: ListTile(
                leading: const Icon(Icons.circle, size: 10, color: AppColors.uaBlue),
                title: Text(_events[i]['d']!, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.accent)),
                subtitle: Text(_events[i]['t']!, style: const TextStyle(color: AppColors.textSec)),
                trailing: IconButton(icon: const Icon(Icons.delete, size: 16, color: Colors.red), onPressed: () {
                  final id = _events[i]['id'] ?? '';
                  setState(() => _events.removeAt(i));
                  if (id.isNotEmpty) DatabaseHelper.instance.deleteTimelineEvent(id);
                }),
              ),
            ),
          ),
    floatingActionButton: FloatingActionButton(
      backgroundColor: AppColors.uaBlue,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: AppColors.uaYellow, width: 1.5)),
      onPressed: _add,
      child: const Icon(Icons.add, color: Colors.white),
    ),
  );
}

// ─────────────────────────────────────────────
// СЕЙФ З ПАРОЛЕМ
// ─────────────────────────────────────────────
class VaultScreen extends StatefulWidget {
  final Function(String) onLog;
  const VaultScreen({super.key, required this.onLog});
  @override State<VaultScreen> createState() => _VaultScreenState();
}
class _VaultScreenState extends State<VaultScreen> {
  bool _unlocked = false, _isFirst = true, _loaded = false;
  String _savedMpEncrypted = "";
  final _mp = TextEditingController();
  List<Map<String, String>> _vault = [];
  int _revealedIndex = -1; // індекс записа з показаним паролем
  static const _secureStorage = FlutterSecureStorage();
  static const _mpKey = 'vault_master_pass_enc';

  @override void initState() { super.initState(); _load(); }

  void _load() async {
    final mp      = await _secureStorage.read(key: _mpKey);
    final entries = await DatabaseHelper.instance.getVault();
    if (!mounted) return;
    setState(() {
      if (mp != null && mp.isNotEmpty) { _isFirst = false; _savedMpEncrypted = mp; }
      _vault  = entries;
      _loaded = true;
    });
  }



  void _setPass() async {
    if (_mp.text.length < 4) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Мінімум 4 символи!'), backgroundColor: Colors.red)); return; }
    final encrypted = await CryptoHelper.instance.encrypt(_mp.text);
    await _secureStorage.write(key: _mpKey, value: encrypted);
    setState(() { _savedMpEncrypted = encrypted; _isFirst = false; _unlocked = true; });
    widget.onLog("Сейф: встановлено майстер-пароль");
  }

  void _checkPass() async {
    try {
      final decrypted = await CryptoHelper.instance.decrypt(_savedMpEncrypted);
      if (_mp.text == decrypted) { setState(() => _unlocked = true); widget.onLog("Сейф: успішний вхід"); }
      else { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('НЕВІРНИЙ ПАРОЛЬ!'), backgroundColor: Colors.red)); }
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ПОМИЛКА ДЕШИФРУВАННЯ!'), backgroundColor: Colors.red));
    }
  }

  void _addEntry() {
    final rC = TextEditingController(), lC = TextEditingController(), pC = TextEditingController();
    showDialog(context: context, builder: (c) => AlertDialog(
      backgroundColor: AppColors.bgCard,
      title: const Text('НОВИЙ ЗАПИС', style: TextStyle(color: AppColors.textPri)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: rC, style: const TextStyle(color: AppColors.textPri), decoration: const InputDecoration(labelText: 'Ресурс (Сайт/Додаток)')),
        const SizedBox(height: 8),
        TextField(controller: lC, style: const TextStyle(color: AppColors.textPri), decoration: const InputDecoration(labelText: 'Логін / Email')),
        const SizedBox(height: 8),
        TextField(controller: pC, obscureText: true, style: const TextStyle(color: AppColors.textPri), decoration: const InputDecoration(labelText: 'Пароль')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('СКАСУВАТИ', style: TextStyle(color: AppColors.textSec))),
        ElevatedButton(onPressed: () async {
          final newId = '${DateTime.now().millisecondsSinceEpoch}';
          await DatabaseHelper.instance.insertVaultEntry(newId, rC.text, lC.text, pC.text);
          setState(() => _vault.add({'id': newId, 'r': rC.text, 'l': lC.text, 'p': pC.text}));
          Navigator.pop(c); widget.onLog("Сейф: додано запис");
        }, child: const Text('ЗБЕРЕГТИ', style: TextStyle(color: Colors.white))),
      ],
    ));
  }

  @override Widget build(BuildContext context) {
    if (!_loaded) return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('СЕЙФ')),
      body: const Center(child: CircularProgressIndicator(color: AppColors.uaYellow)),
    );
    if (_isFirst) return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('СЕЙФ [НАЛАШТУВАННЯ]')),
      body: Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.security, size: 64, color: Colors.blueAccent),
        const SizedBox(height: 20),
        const Text('Створіть майстер-пароль. Він не підлягає відновленню!', textAlign: TextAlign.center, style: TextStyle(color: Colors.redAccent)),
        const SizedBox(height: 20),
        TextField(controller: _mp, obscureText: true, style: const TextStyle(color: AppColors.textPri), decoration: const InputDecoration(labelText: 'ПРИДУМАЙТЕ ПАРОЛЬ')),
        const SizedBox(height: 20),
        ElevatedButton(onPressed: _setPass, child: const Text('СТВОРИТИ СЕЙФ', style: TextStyle(color: Colors.white))),
      ]))),
    );
    if (!_unlocked) return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('СЕЙФ [ЗАБЛОКОВАНО]')),
      body: Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.lock, size: 64, color: AppColors.uaYellow),
        const SizedBox(height: 20),
        TextField(controller: _mp, obscureText: true, style: const TextStyle(color: AppColors.textPri), decoration: const InputDecoration(labelText: 'МАЙСТЕР-ПАРОЛЬ'), onSubmitted: (_) => _checkPass()),
        const SizedBox(height: 20),
        ElevatedButton(onPressed: _checkPass, child: const Text('ВІДЧИНИТИ', style: TextStyle(color: Colors.white))),
      ]))),
    );
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('СЕЙФ [ВІДКРИТО]'), actions: [
        IconButton(icon: const Icon(Icons.lock_open, color: Colors.red), onPressed: () => setState(() { _unlocked = false; _mp.clear(); })),
      ]),
      body: _vault.isEmpty
          ? const Center(child: Text('СЕЙФ ПУСТИЙ', style: TextStyle(color: Colors.white24)))
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 90),
              itemCount: _vault.length,
              itemBuilder: (c, i) => Card(
                color: Colors.white.withOpacity(0.04),
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: AppColors.border)),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  // Показ пароля — зверху картки
                  if (_revealedIndex == i) Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.uaYellow.withOpacity(0.1),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                      border: Border(bottom: BorderSide(color: AppColors.uaYellow.withOpacity(0.3))),
                    ),
                    child: Row(children: [
                      const Icon(Icons.visibility, size: 14, color: AppColors.uaYellow),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_vault[i]['p']!, style: const TextStyle(
                        fontSize: 14, fontFamily: 'JetBrainsMono', fontWeight: FontWeight.bold,
                        color: AppColors.uaYellow, letterSpacing: 1,
                      ))),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 16, color: AppColors.uaYellow),
                        constraints: const BoxConstraints(), padding: EdgeInsets.zero,
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _vault[i]['p']!));
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Пароль скопійовано'), backgroundColor: AppColors.uaBlue, duration: Duration(seconds: 1)));
                        },
                      ),
                    ]),
                  ),
                  // Основний рядок
                  ListTile(
                    leading: Container(width: 36, height: 36, decoration: BoxDecoration(color: AppColors.uaYellow.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.security, color: AppColors.uaYellow, size: 18)),
                    title: Text(_vault[i]['r']!, style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                    subtitle: Text(_vault[i]['l']!, style: const TextStyle(fontSize: 11, color: AppColors.textSec)),
                    trailing: SizedBox(
                      width: 100,
                      child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                        GestureDetector(
                          onTapDown: (_) => setState(() => _revealedIndex = i),
                          onTapUp: (_) => setState(() => _revealedIndex = -1),
                          onTapCancel: () => setState(() => _revealedIndex = -1),
                          child: Container(
                            width: 32, height: 32,
                            decoration: BoxDecoration(
                              color: _revealedIndex == i ? AppColors.uaYellow.withOpacity(0.2) : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Icon(
                              _revealedIndex == i ? Icons.visibility : Icons.visibility_off,
                              size: 18, color: _revealedIndex == i ? AppColors.uaYellow : AppColors.textHint,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                          constraints: const BoxConstraints(),
                          padding: EdgeInsets.zero,
                          tooltip: 'Видалити',
                          onPressed: () {
                            showDialog(context: context, builder: (_) => AlertDialog(
                              backgroundColor: AppColors.bgCard,
                              title: const Text('Видалити запис?', style: TextStyle(fontSize: 15)),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Ні', style: TextStyle(color: AppColors.textSec))),
                                ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () {
                                  final id = _vault[i]['id'] ?? '';
                                  setState(() => _vault.removeAt(i));
                                  if (id.isNotEmpty) DatabaseHelper.instance.deleteVaultEntry(id);
                                  Navigator.pop(context);
                                }, child: const Text('Так')),
                              ],
                            ));
                          },
                        ),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.uaBlue,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: AppColors.uaYellow, width: 1.5)),
        onPressed: _addEntry,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

// ─────────────────────────────────────────────
class DiffScreen extends StatelessWidget {
  final Prompt a, b;
  const DiffScreen({super.key, required this.a, required this.b});

  @override Widget build(BuildContext context) {
    final diff = _computeDiff(a.content, b.content);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('ПОРІВНЯННЯ', style: TextStyle(fontSize: 14, letterSpacing: 1)),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_all, color: AppColors.uaYellow, size: 20),
            tooltip: 'Копіювати diff',
            onPressed: () {
              final text = 'A: ${a.title}\nB: ${b.title}\n\n${diff.map((d) => "${d.type == _DiffType.same ? " " : d.type == _DiffType.added ? "+" : "-"} ${d.text}").join("\n")}';
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Diff скопійовано'), backgroundColor: AppColors.uaBlue, duration: Duration(seconds: 1)));
            },
          ),
        ],
      ),
      body: Column(children: [
        // Заголовки
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: Colors.white.withOpacity(0.02),
          child: Row(children: [
            const Icon(Icons.remove_circle_outline, size: 14, color: Colors.redAccent),
            const SizedBox(width: 6),
            Expanded(child: Text(a.title, style: const TextStyle(fontSize: 11, color: Colors.redAccent, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 12),
            const Icon(Icons.add_circle_outline, size: 14, color: AppColors.success),
            const SizedBox(width: 6),
            Expanded(child: Text(b.title, style: const TextStyle(fontSize: 11, color: AppColors.success, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
        ),
        const Divider(color: AppColors.border, height: 0),
        // Статистика
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            _statChip('Спільне', diff.where((d) => d.type == _DiffType.same).length, AppColors.textSec),
            const SizedBox(width: 8),
            _statChip('Видалено', diff.where((d) => d.type == _DiffType.removed).length, Colors.redAccent),
            const SizedBox(width: 8),
            _statChip('Додано', diff.where((d) => d.type == _DiffType.added).length, AppColors.success),
          ]),
        ),
        const Divider(color: AppColors.border, height: 0),
        // Diff view
        Expanded(child: ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: diff.length,
          itemBuilder: (_, i) {
            final d = diff[i];
            Color bg, textColor;
            String prefix;
            switch (d.type) {
              case _DiffType.same:
                bg = Colors.transparent;
                textColor = AppColors.textSec;
                prefix = '  ';
                break;
              case _DiffType.removed:
                bg = Colors.red.withOpacity(0.08);
                textColor = Colors.redAccent;
                prefix = '− ';
                break;
              case _DiffType.added:
                bg = Colors.green.withOpacity(0.08);
                textColor = AppColors.success;
                prefix = '+ ';
                break;
            }
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              margin: const EdgeInsets.only(bottom: 1),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                '$prefix${d.text}',
                style: TextStyle(
                  fontSize: 12, color: textColor, fontFamily: 'JetBrainsMono',
                  decoration: d.type == _DiffType.removed ? TextDecoration.lineThrough : null,
                ),
              ),
            );
          },
        )),
      ]),
    );
  }

  Widget _statChip(String label, int count, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text('$label: $count', style: TextStyle(fontSize: 10, color: color, fontFamily: 'JetBrainsMono')),
  );

  /// Порядковий diff на рівні рядків (LCS-based)
  static List<_DiffLine> _computeDiff(String textA, String textB) {
    final linesA = textA.split('\n');
    final linesB = textB.split('\n');
    final result = <_DiffLine>[];

    // LCS таблиця
    final m = linesA.length, n = linesB.length;
    final dp = List.generate(m + 1, (_) => List.filled(n + 1, 0));
    for (int i = 1; i <= m; i++) {
      for (int j = 1; j <= n; j++) {
        if (linesA[i - 1].trim() == linesB[j - 1].trim()) {
          dp[i][j] = dp[i - 1][j - 1] + 1;
        } else {
          dp[i][j] = dp[i - 1][j] > dp[i][j - 1] ? dp[i - 1][j] : dp[i][j - 1];
        }
      }
    }

    // Backtrack
    int i = m, j = n;
    final temp = <_DiffLine>[];
    while (i > 0 && j > 0) {
      if (linesA[i - 1].trim() == linesB[j - 1].trim()) {
        temp.add(_DiffLine(linesA[i - 1], _DiffType.same));
        i--; j--;
      } else if (dp[i - 1][j] >= dp[i][j - 1]) {
        temp.add(_DiffLine(linesA[i - 1], _DiffType.removed));
        i--;
      } else {
        temp.add(_DiffLine(linesB[j - 1], _DiffType.added));
        j--;
      }
    }
    while (i > 0) { temp.add(_DiffLine(linesA[--i], _DiffType.removed)); }
    while (j > 0) { temp.add(_DiffLine(linesB[--j], _DiffType.added)); }

    return temp.reversed.toList();
  }
}

enum _DiffType { same, removed, added }

class _DiffLine {
  final String text;
  final _DiffType type;
  const _DiffLine(this.text, this.type);
}
