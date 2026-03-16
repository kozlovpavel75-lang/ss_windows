import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:exif/exif.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:math';

// ─────────────────────────────────────────────
// ТОЧКА ВХОДУ
// ─────────────────────────────────────────────
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarColor: Colors.transparent),
  );
  runApp(const PromptApp());
}

// ─────────────────────────────────────────────
// КОНСТАНТИ КОЛЬОРІВ (єдине місце)
// ─────────────────────────────────────────────
class AppColors {
  static const bg         = Color(0xFF040E22);
  static const bgCard     = Color(0xFF0A152F);
  static const bgDeep     = Color(0xFF040B16);
  static const uaBlue     = Color(0xFF0057B7);
  static const uaYellow   = Color(0xFFE8D98C);
  static const accent     = Color(0xFF6FA8DC);
  static const textPrimary   = Color(0xFFEEEEEE);
  static const textSecondary = Color(0x99FFFFFF);
  static const textHint      = Color(0x40FFFFFF);
  static const border     = Color(0x14FFFFFF);
  static const borderAccent  = Color(0x40E8D98C);
  static const success    = Color(0xFF4ADE80);
  static const danger     = Color(0xFFFF6B6B);
}

// ─────────────────────────────────────────────
// МОДЕЛІ ДАНИХ
// ─────────────────────────────────────────────
class Prompt {
  String id, title, content, category;
  bool isFavorite;
  DateTime createdAt;

  Prompt({
    required this.id,
    required this.title,
    required this.content,
    required this.category,
    this.isFavorite = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id, 'title': title, 'content': content,
    'category': category, 'isFavorite': isFavorite,
    'createdAt': createdAt.toIso8601String(),
  };

  factory Prompt.fromJson(Map<String, dynamic> j) => Prompt(
    id: j['id'], title: j['title'], content: j['content'],
    category: j['category'], isFavorite: j['isFavorite'] ?? false,
    createdAt: j['createdAt'] != null ? DateTime.tryParse(j['createdAt']) : null,
  );

  // Повертає список змінних {param} з контенту
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

// ─────────────────────────────────────────────
// КОРЕНЕВИЙ ВІДЖЕТ
// ─────────────────────────────────────────────
class PromptApp extends StatelessWidget {
  const PromptApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.bg,
        fontFamily: 'sans-serif',
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          titleTextStyle: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w500,
            fontSize: 16,
            letterSpacing: 1.5,
          ),
        ),
        tabBarTheme: const TabBarThemeData(
          labelColor: AppColors.uaYellow,
          unselectedLabelColor: AppColors.textSecondary,
          indicator: UnderlineTabIndicator(
            borderSide: BorderSide(color: AppColors.uaYellow, width: 2),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.bgCard,
          labelStyle: const TextStyle(color: AppColors.textSecondary),
          hintStyle: const TextStyle(color: AppColors.textHint),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.uaBlue),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.uaBlue,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            minimumSize: const Size(double.infinity, 50),
          ),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: AppColors.bgCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppColors.uaBlue, width: 0.5),
          ),
        ),
      ),
      // Анімація переходів між екранами
      navigatorObservers: [],
      onGenerateRoute: (settings) {
        final page = settings.arguments as Widget? ?? const SizedBox();
        return PageRouteBuilder(
          settings: settings,
          pageBuilder: (_, __, ___) => page,
          transitionsBuilder: (_, anim, __, child) => FadeTransition(
            opacity: CurvedAnimation(parent: anim, curve: Curves.easeInOut),
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.03, 0),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
              child: child,
            ),
          ),
          transitionDuration: const Duration(milliseconds: 220),
        );
      },
      home: const SplashScreen(),
    );
  }
}

// ─────────────────────────────────────────────
// SPLASH SCREEN
// ─────────────────────────────────────────────
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _ctrl.forward();
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const MainScreen(),
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: FadeTransition(
        opacity: _fade,
        child: SizedBox.expand(
          child: Image.asset(
            'assets/splash.png',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const Center(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('🔱', style: TextStyle(fontSize: 64)),
                SizedBox(height: 16),
                Text('UKR_OSINT', style: TextStyle(
                  color: AppColors.uaYellow, fontSize: 22,
                  letterSpacing: 4, fontWeight: FontWeight.w500,
                )),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// ГОЛОВНИЙ ЕКРАН
// ─────────────────────────────────────────────
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Prompt> prompts = [];
  List<PDFDoc> docs = [];
  List<String> auditLogs = [];
  int _secretCounter = 0;

  // Пошук
  bool _searchActive = false;
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();

  static const List<String> categories = [
    'ФО', 'ЮО', 'ГЕОІНТ', 'МОНІТОРИНГ', 'ІНСТРУМЕНТИ', 'ДОКУМЕНТИ'
  ];
  static const List<IconData> categoryIcons = [
    Icons.person_outline, Icons.business_outlined, Icons.map_outlined,
    Icons.monitor_outlined, Icons.build_outlined, Icons.folder_outlined,
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: categories.length, vsync: this);
    _tabController.addListener(() { if (mounted) setState(() {}); });
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Логування ──
  void _logAction(String action) {
    if (!mounted) return;
    final now = DateTime.now();
    final ts = "${now.day.toString().padLeft(2,'0')}.${now.month.toString().padLeft(2,'0')} "
               "${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}";
    setState(() {
      auditLogs.insert(0, "[$ts] $action");
      if (auditLogs.length > 100) auditLogs.removeLast();
    });
    _save();
  }

  // ── Завантаження даних ──
  void _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final pStr = prefs.getString('prompts_data');
    final dStr = prefs.getString('docs_data');
    final logs = prefs.getStringList('audit_logs');
    if (!mounted) return;
    setState(() {
      if (pStr != null) {
        try { prompts = (json.decode(pStr) as List).map((i) => Prompt.fromJson(i)).toList(); }
        catch (_) { prompts = []; }
      }
      if (dStr != null) {
        try { docs = (json.decode(dStr) as List).map((i) => PDFDoc.fromJson(i)).toList(); }
        catch (_) { docs = []; }
      }
      if (logs != null) auditLogs = logs;
      if (prompts.isEmpty) {
        prompts = [
          Prompt(
            id: _uid(),
            title: 'Аналіз фізичної особи',
            category: 'ФО',
            isFavorite: true,
            content: 'Ти - аналітик OSINT. Проведи пошук:\n'
                     'ПІБ — {ПІБ}\nДата народження — {дата_народження}\n'
                     'Надай звіт по відкритих джерелах.',
          ),
        ];
        _logAction("Створено базовий профіль");
      }
    });
  }

  // ── Збереження ──
  void _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('prompts_data', json.encode(prompts.map((p) => p.toJson()).toList()));
    await prefs.setString('docs_data',    json.encode(docs.map((d) => d.toJson()).toList()));
    await prefs.setStringList('audit_logs', auditLogs.take(100).toList());
  }

  // ── Унікальний ID ──
  String _uid() =>
      '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999).toString().padLeft(4,'0')}';

  // ── Імпорт TXT ──
  void _importFromTxt() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: ['txt'],
    );
    if (result?.files.single.path == null) return;
    try {
      final content = await File(result!.files.single.path!).readAsString();
      final List<Prompt> imported = [];
      for (var block in content.split('===')) {
        if (block.trim().isEmpty) continue;
        String cat = 'МОНІТОРИНГ', title = '', text = '';
        bool isText = false;
        for (var line in block.trim().split('\n')) {
          final lineLow = line.toLowerCase().trim();
          if (lineLow.startsWith('категорія:')) {
            final raw = lineLow.replaceFirst('категорія:', '').trim();
            if (raw == 'фо' || raw.contains('фіз')) cat = 'ФО';
            else if (raw == 'юо' || raw.contains('юр')) cat = 'ЮО';
            else if (raw.contains('гео')) cat = 'ГЕОІНТ';
            else if (raw.contains('мон')) cat = 'МОНІТОРИНГ';
          } else if (lineLow.startsWith('назва:')) {
            title = line.replaceFirst(RegExp(r'Назва:', caseSensitive: false), '').trim();
          } else if (lineLow.startsWith('текст:')) {
            text = line.replaceFirst(RegExp(r'Текст:', caseSensitive: false), '').trim();
            isText = true;
          } else if (isText) {
            text += '\n$line';
          }
        }
        if (title.isNotEmpty && text.isNotEmpty) {
          imported.add(Prompt(id: _uid(), title: title, content: text.trim(), category: cat));
        }
      }
      if (!mounted) return;
      setState(() => prompts.addAll(imported));
      _logAction("Імпортовано TXT (${imported.length} записів)");
      _save();
    } catch (e) {
      _logAction("ERR: Помилка імпорту — $e");
    }
  }

  // ── Додати / редагувати промпт ──
  void _addOrEditPrompt({Prompt? p}) {
    final tCtrl = TextEditingController(text: p?.title ?? '');
    final cCtrl = TextEditingController(text: p?.content ?? '');
    final editableCats = ['ФО', 'ЮО', 'ГЕОІНТ', 'МОНІТОРИНГ'];
    String selectedCat = (p?.category != null && editableCats.contains(p!.category))
        ? p.category
        : editableCats[_tabController.index.clamp(0, editableCats.length - 1)];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setD) => AlertDialog(
          title: Text(
            p == null ? 'НОВИЙ ЗАПИС' : 'РЕДАГУВАННЯ',
            style: const TextStyle(
              fontWeight: FontWeight.w500, letterSpacing: 1.5, fontSize: 15,
              color: AppColors.textPrimary,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                value: selectedCat,
                dropdownColor: AppColors.bgCard,
                items: editableCats.map((c) => DropdownMenuItem(
                  value: c,
                  child: Text(c, style: const TextStyle(fontFamily: 'monospace')),
                )).toList(),
                onChanged: (v) => setD(() => selectedCat = v!),
                decoration: const InputDecoration(labelText: 'КЛАСИФІКАЦІЯ'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: tCtrl,
                decoration: const InputDecoration(labelText: 'НАЗВА'),
                style: const TextStyle(color: AppColors.textPrimary),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: cCtrl,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'ЗМІСТ  {змінні в фігурних дужках}',
                  alignLabelWithHint: true,
                ),
                style: const TextStyle(
                  fontFamily: 'monospace', fontSize: 13,
                  color: AppColors.textPrimary,
                ),
              ),
            ]),
          ),
          actions: [
            if (p != null)
              TextButton(
                onPressed: () => _confirmDelete(ctx, p),
                child: const Text('ВИДАЛИТИ', style: TextStyle(color: AppColors.danger)),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('СКАСУВАТИ', style: TextStyle(color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () {
                if (tCtrl.text.trim().isEmpty) return;
                setState(() {
                  if (p == null) {
                    prompts.add(Prompt(
                      id: _uid(), title: tCtrl.text.trim(),
                      content: cCtrl.text.trim(), category: selectedCat,
                    ));
                    _logAction("Створено: ${tCtrl.text.trim()}");
                  } else {
                    p.title = tCtrl.text.trim();
                    p.content = cCtrl.text.trim();
                    p.category = selectedCat;
                    _logAction("Оновлено: ${tCtrl.text.trim()}");
                  }
                });
                _save();
                Navigator.pop(ctx);
              },
              child: const Text('ЗАПИСАТИ'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext ctx, Prompt p) {
    Navigator.pop(ctx);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('ВИДАЛЕННЯ', style: TextStyle(color: AppColors.danger)),
        content: Text('Видалити "${p.title}"?',
            style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('СКАСУВАТИ', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () {
              setState(() => prompts.remove(p));
              _logAction("Видалено: ${p.title}");
              _save();
              Navigator.pop(context);
            },
            child: const Text('ВИДАЛИТИ'),
          ),
        ],
      ),
    );
  }

  // ── Імпорт PDF ──
  void _pickPDF() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: ['pdf'],
    );
    if (r?.files.single.path == null) return;
    final dir = await getApplicationDocumentsDirectory();
    final name = r!.files.single.name;
    final newPath = '${dir.path}/${DateTime.now().millisecondsSinceEpoch}_$name';
    await File(r.files.single.path!).copy(newPath);
    if (!mounted) return;
    setState(() => docs.add(PDFDoc(id: _uid(), name: name, path: newPath)));
    _logAction("Додано документ: $name");
    _save();
  }

  // ── SYS.INFO (пасхалка) ──
  void _showSysInfo() {
    _secretCounter = 0;
    final stats = <String, int>{'ФО': 0, 'ЮО': 0, 'ГЕОІНТ': 0, 'МОНІТОРИНГ': 0};
    for (var p in prompts) {
      if (stats.containsKey(p.category)) stats[p.category] = stats[p.category]! + 1;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          GestureDetector(
            onTap: () {
              _secretCounter++;
              if (_secretCounter >= 5) {
                Navigator.pop(ctx);
                _logAction("SYS: Операція БАВОВНА активована!");
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => CottonGame(onLog: _logAction)));
              }
            },
            child: const Icon(Icons.analytics, color: AppColors.uaYellow),
          ),
          const SizedBox(width: 10),
          const Text('SYS.INFO', style: TextStyle(
            fontFamily: 'monospace', fontWeight: FontWeight.w500, fontSize: 15,
          )),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          _infoRow('TOTAL RECORDS', prompts.length.toString()),
          _infoRow('SECURE DOCS',   docs.length.toString()),
          const Divider(color: AppColors.border, height: 20),
          _infoRow('ФО',         stats['ФО'].toString()),
          _infoRow('ЮО',         stats['ЮО'].toString()),
          _infoRow('ГЕОІНТ',     stats['ГЕОІНТ'].toString()),
          _infoRow('МОНІТОРИНГ', stats['МОНІТОРИНГ'].toString()),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CLOSE', style: TextStyle(color: AppColors.uaYellow)),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(
        color: AppColors.textSecondary, fontFamily: 'monospace', fontSize: 13,
      )),
      Text(value, style: const TextStyle(
        color: AppColors.accent, fontFamily: 'monospace',
        fontWeight: FontWeight.w500, fontSize: 16,
      )),
    ]),
  );

  // ── Аудит-лог ──
  void _showAuditLog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.terminal, color: AppColors.textSecondary),
          SizedBox(width: 10),
          Text('AUDIT_LOG', style: TextStyle(fontFamily: 'monospace', fontSize: 15)),
        ]),
        content: SizedBox(
          width: double.maxFinite, height: 300,
          child: auditLogs.isEmpty
              ? const Center(child: Text('NO RECORDS',
                  style: TextStyle(color: AppColors.textHint)))
              : ListView.builder(
                  itemCount: auditLogs.length,
                  itemBuilder: (_, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(auditLogs[i], style: const TextStyle(
                      color: AppColors.success, fontFamily: 'monospace', fontSize: 11,
                    )),
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() { auditLogs.clear(); _save(); });
              Navigator.pop(ctx);
            },
            child: const Text('CLEAR', style: TextStyle(color: AppColors.danger)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CLOSE', style: TextStyle(color: AppColors.textSecondary)),
          ),
        ],
      ),
    );
  }

  // ── Список промптів з пошуком ──
  List<Prompt> _filteredPrompts(String category) {
    var items = prompts.where((p) => p.category == category).toList();
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      items = items.where((p) =>
        p.title.toLowerCase().contains(q) ||
        p.content.toLowerCase().contains(q)
      ).toList();
    }
    items.sort((a, b) => (b.isFavorite ? 1 : 0).compareTo(a.isFavorite ? 1 : 0));
    return items;
  }

  // ── APPBAR ──
  PreferredSizeWidget _buildAppBar() {
    if (_searchActive) {
      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textSecondary),
          onPressed: () {
            setState(() {
              _searchActive = false;
              _searchQuery = '';
              _searchCtrl.clear();
            });
          },
        ),
        title: TextField(
          controller: _searchCtrl,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
          decoration: const InputDecoration(
            hintText: 'Пошук по записах...',
            hintStyle: TextStyle(color: AppColors.textHint),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
          ),
          onChanged: (v) => setState(() => _searchQuery = v),
        ),
        bottom: _buildTabBar(),
      );
    }

    return AppBar(
      title: Row(mainAxisSize: MainAxisSize.min, children: [
        const Text('🔱', style: TextStyle(fontSize: 20)),
        const SizedBox(width: 8),
        const Text('UKR_OSINT', style: TextStyle(
          fontWeight: FontWeight.w500, letterSpacing: 2.5, fontSize: 17,
          color: AppColors.uaYellow,
        )),
      ]),
      actions: [
        IconButton(
          icon: const Icon(Icons.search, color: AppColors.textSecondary, size: 22),
          onPressed: () => setState(() => _searchActive = true),
          tooltip: 'Пошук',
        ),
        IconButton(
          icon: const Icon(Icons.analytics_outlined, color: AppColors.uaYellow, size: 22),
          onPressed: _showSysInfo,
          tooltip: 'SYS.INFO',
        ),
        IconButton(
          icon: const Icon(Icons.receipt_long, color: AppColors.textSecondary, size: 22),
          onPressed: _showAuditLog,
          tooltip: 'Аудит-лог',
        ),
        IconButton(
          icon: const Icon(Icons.download_outlined, color: AppColors.accent, size: 22),
          onPressed: _importFromTxt,
          tooltip: 'Імпорт TXT',
        ),
      ],
      bottom: _buildTabBar(),
    );
  }

  TabBar _buildTabBar() => TabBar(
    controller: _tabController,
    isScrollable: true,
    tabAlignment: TabAlignment.start,
    tabs: List.generate(categories.length, (i) => Tab(
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(categoryIcons[i], size: 14),
        const SizedBox(width: 5),
        Text(categories[i], style: const TextStyle(fontSize: 12, letterSpacing: 0.5)),
      ]),
    )),
  );

  // ── БУДІВЛЯ СПИСКУ ──
  Widget _buildPromptList(String cat) {
    final items = _filteredPrompts(cat);

    if (items.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(
            _searchQuery.isNotEmpty ? Icons.search_off : Icons.inbox_outlined,
            color: AppColors.textHint, size: 48,
          ),
          const SizedBox(height: 12),
          Text(
            _searchQuery.isNotEmpty ? 'Нічого не знайдено' : 'Поки що порожньо',
            style: const TextStyle(color: AppColors.textHint, fontSize: 14),
          ),
          if (_searchQuery.isEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              'Натисніть + щоб додати запис',
              style: TextStyle(color: AppColors.textHint, fontSize: 12),
            ),
          ]
        ]),
      );
    }

    return ReorderableListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 90),
      itemCount: items.length,
      onReorder: _searchQuery.isNotEmpty
          ? (_, __) {} // Не реордеримо під час пошуку
          : (oldIdx, newIdx) {
              setState(() {
                if (newIdx > oldIdx) newIdx -= 1;
                final item = items.removeAt(oldIdx);
                items.insert(newIdx, item);
                prompts.removeWhere((p) => p.category == cat);
                prompts.addAll(items);
              });
              _save();
            },
      itemBuilder: (ctx, i) {
        final p = items[i];
        return _PromptCard(
          key: ValueKey(p.id),
          prompt: p,
          onTap: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => GenScreen(p: p, onLog: _logAction),
          )),
          onLongPress: () => _addOrEditPrompt(p: p),
          onFavorite: () { setState(() => p.isFavorite = !p.isFavorite); _save(); },
        );
      },
    );
  }

  // ── ДОКУМЕНТИ ──
  Widget _buildDocList() {
    if (docs.isEmpty) {
      return const Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.folder_open, color: AppColors.textHint, size: 48),
          SizedBox(height: 12),
          Text('Документів немає', style: TextStyle(color: AppColors.textHint, fontSize: 14)),
          SizedBox(height: 8),
          Text('Натисніть + щоб додати PDF', style: TextStyle(color: AppColors.textHint, fontSize: 12)),
        ],
      ));
    }
    return ListView.builder(
      itemCount: docs.length,
      padding: const EdgeInsets.only(top: 8, bottom: 90),
      itemBuilder: (ctx, i) => Card(
        color: Colors.white.withValues(alpha: 0.03),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: AppColors.border),
        ),
        child: ListTile(
          leading: Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: AppColors.uaBlue.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.picture_as_pdf, color: AppColors.accent, size: 22),
          ),
          title: Text(docs[i].name,
              style: const TextStyle(fontSize: 13, color: AppColors.textPrimary)),
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => PDFViewerScreen(doc: docs[i]))),
          trailing: IconButton(
            icon: const Icon(Icons.close, color: AppColors.textHint, size: 18),
            onPressed: () => showDialog(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('Видалити документ?',
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 15)),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Ні', style: TextStyle(color: AppColors.textSecondary)),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
                    onPressed: () {
                      setState(() => docs.removeAt(i));
                      _logAction("Видалено документ: ${docs[i].name}");
                      _save();
                      Navigator.pop(context);
                    },
                    child: const Text('Видалити'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── ДЕКОРАТИВНА ЛІНІЯ (українська символіка) ──
  Widget _buildUaStripe() => Container(
    height: 2,
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: [AppColors.uaBlue, AppColors.uaBlue, AppColors.uaYellow, AppColors.uaYellow],
        stops: [0, 0.5, 0.5, 1],
      ),
    ),
  );

  // ── FAB ──
  Widget? _buildFab() {
    final idx = _tabController.index;
    if (idx == categories.indexOf('ІНСТРУМЕНТИ')) return null;
    return FloatingActionButton(
      backgroundColor: AppColors.uaBlue,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.uaYellow, width: 1.5),
      ),
      onPressed: () {
        if (idx == categories.indexOf('ДОКУМЕНТИ')) {
          _pickPDF();
        } else {
          _addOrEditPrompt();
        }
      },
      child: Icon(
        idx == categories.indexOf('ДОКУМЕНТИ') ? Icons.note_add : Icons.add,
        color: Colors.white,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(),
      floatingActionButton: _buildFab(),
      body: Column(children: [
        Expanded(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppColors.bgDeep, Color(0xFF091630), AppColors.bg],
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Column(children: [
                _buildUaStripe(),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: categories.map((cat) {
                      if (cat == 'ДОКУМЕНТИ')   return _buildDocList();
                      if (cat == 'ІНСТРУМЕНТИ') return ToolsMenuScreen(onLog: _logAction);
                      return _buildPromptList(cat);
                    }).toList(),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
// КАРТКА ПРОМПТУ
// ─────────────────────────────────────────────
class _PromptCard extends StatelessWidget {
  final Prompt prompt;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onFavorite;

  const _PromptCard({
    super.key,
    required this.prompt,
    required this.onTap,
    required this.onLongPress,
    required this.onFavorite,
  });

  String _fmtDate(DateTime d) =>
      "${d.day.toString().padLeft(2,'0')}.${d.month.toString().padLeft(2,'0')}";

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white.withValues(alpha: prompt.isFavorite ? 0.04 : 0.02),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: prompt.isFavorite
              ? AppColors.uaYellow.withValues(alpha: 0.3)
              : AppColors.border,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              // Категорійний пілюль
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.uaBlue.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.uaBlue.withValues(alpha: 0.4)),
                ),
                child: Text(prompt.category,
                    style: const TextStyle(
                      fontSize: 9, letterSpacing: 0.8, color: AppColors.accent,
                    )),
              ),
              const SizedBox(width: 8),
              Text(_fmtDate(prompt.createdAt),
                  style: const TextStyle(fontSize: 10, color: AppColors.textHint)),
              const Spacer(),
              GestureDetector(
                onTap: onFavorite,
                child: Icon(
                  prompt.isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                  color: prompt.isFavorite ? AppColors.uaYellow : AppColors.textHint,
                  size: 20,
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Text(prompt.title,
                style: const TextStyle(
                  fontWeight: FontWeight.w500, fontSize: 14,
                  color: AppColors.textPrimary,
                )),
            const SizedBox(height: 4),
            Text(
              prompt.content,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textHint, fontFamily: 'monospace', fontSize: 11,
              ),
            ),
            // Теги змінних
            if (prompt.variables.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 4, runSpacing: 4,
                children: prompt.variables.take(4).map((v) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text('{$v}',
                      style: const TextStyle(
                        fontSize: 9, color: AppColors.textSecondary, fontFamily: 'monospace',
                      )),
                )).toList(),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// МЕНЮ ІНСТРУМЕНТІВ
// ─────────────────────────────────────────────
class ToolsMenuScreen extends StatelessWidget {
  final Function(String) onLog;
  const ToolsMenuScreen({super.key, required this.onLog});

  @override
  Widget build(BuildContext context) {
    final tools = [
      _ToolItem('СКАНЕР', 'Екстракція артефактів з тексту', Icons.radar,
          ScannerScreen(onLog: onLog)),
      _ToolItem('EXIF', 'Аналіз метаданих зображень', Icons.image_search,
          ExifScreen(onLog: onLog)),
      _ToolItem('DORKS', 'Google Dorks конструктор', Icons.travel_explore,
          DorksScreen(onLog: onLog)),
    ];

    return ListView(
      padding: const EdgeInsets.only(top: 16, bottom: 90),
      children: tools.map((t) => Card(
        color: Colors.white.withValues(alpha: 0.02),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: AppColors.border),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: AppColors.uaBlue.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(t.icon, color: AppColors.uaYellow, size: 22),
          ),
          title: Text(t.title,
              style: const TextStyle(
                fontWeight: FontWeight.w500, letterSpacing: 0.8, fontSize: 14,
              )),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(t.subtitle,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ),
          trailing: const Icon(Icons.chevron_right, color: AppColors.textHint),
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => t.screen)),
        ),
      )).toList(),
    );
  }
}

class _ToolItem {
  final String title, subtitle;
  final IconData icon;
  final Widget screen;
  _ToolItem(this.title, this.subtitle, this.icon, this.screen);
}

// ─────────────────────────────────────────────
// СКАНЕР — розширений
// ─────────────────────────────────────────────
class ScannerScreen extends StatefulWidget {
  final Function(String) onLog;
  const ScannerScreen({super.key, required this.onLog});
  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final _ctrl = TextEditingController();
  Map<String, List<String>> _results = {};
  bool _scanning = false;
  String _matrixChar = '';
  Timer? _matrixTimer;

  // Іконка та колір для кожного типу артефакту
  static const _typeConfig = {
    'IP':       (_ScanType(Icons.dns_outlined,        Color(0xFF6FA8DC), 'IP-адреси')),
    'EMAIL':    (_ScanType(Icons.alternate_email,     Color(0xFF80D8B0), 'Електронні адреси')),
    'PHONE':    (_ScanType(Icons.phone_outlined,      Color(0xFFE8A05A), 'Телефони')),
    'URL':      (_ScanType(Icons.link,                Color(0xFFA78BFA), 'Посилання')),
    'GPS':      (_ScanType(Icons.location_on_outlined,Color(0xFF4ADE80), 'Координати GPS')),
    'HASH':     (_ScanType(Icons.tag,                 Color(0xFFFF6B6B), 'Хеші')),
    'CARD':     (_ScanType(Icons.credit_card_outlined,Color(0xFFFFD700), 'Картки/рахунки')),
  };

  @override
  void dispose() {
    _matrixTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    FocusScope.of(context).unfocus();
    setState(() { _scanning = true; _results.clear(); });

    // Анімація "матриця"
    _matrixTimer = Timer.periodic(const Duration(milliseconds: 60), (_) {
      if (mounted) setState(() {
        const chars = '01XYZ#@!?';
        _matrixChar = chars[Random().nextInt(chars.length)];
      });
    });

    await Future.delayed(const Duration(milliseconds: 1200));
    final text = _ctrl.text;

    final found = <String, List<String>>{};

    void extract(String key, RegExp re) {
      final matches = re.allMatches(text).map((m) => m.group(0)!).toSet().toList();
      if (matches.isNotEmpty) found[key] = matches;
    }

    extract('IP',    RegExp(r'\b(?:(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\b'));
    extract('EMAIL', RegExp(r'[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}'));
    extract('PHONE', RegExp(r'(?:\+?38|8)?[\s\-]?\(?0\d{2}\)?[\s\-]?\d{3}[\s\-]?\d{2}[\s\-]?\d{2}|(?:\+\d{1,3}[\s\-]?)?\(?\d{2,4}\)?[\s\-]?\d{3,4}[\s\-]?\d{3,4}'));
    extract('URL',   RegExp(r'https?://[^\s<>"{}|\\^`\[\]]+'));
    extract('GPS',   RegExp(r'[-+]?(?:[1-8]?\d(?:\.\d+)?|90(?:\.0+)?)[,\s]+[-+]?(?:180(?:\.0+)?|(?:(?:1[0-7]\d)|(?:[1-9]?\d))(?:\.\d+)?)'));
    extract('HASH',  RegExp(r'\b[0-9a-fA-F]{32}\b|\b[0-9a-fA-F]{40}\b|\b[0-9a-fA-F]{64}\b'));
    extract('CARD',  RegExp(r'\b(?:UA\d{25}|\d{4}[\s\-]\d{4}[\s\-]\d{4}[\s\-]\d{4})\b'));

    _matrixTimer?.cancel();
    if (!mounted) return;
    setState(() { _scanning = false; _results = found; });
    final total = found.values.fold(0, (s, v) => s + v.length);
    widget.onLog("СКАНЕР: знайдено $total артефактів у ${found.length} категоріях");
  }

  void _copyAll() {
    final all = _results.entries
        .map((e) => '=== ${e.key} ===\n${e.value.join('\n')}')
        .join('\n\n');
    Clipboard.setData(ClipboardData(text: all));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Скопійовано всі артефакти'),
        backgroundColor: AppColors.uaBlue,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('СКАНЕР'),
        actions: [
          if (_results.isNotEmpty)
            TextButton.icon(
              onPressed: _copyAll,
              icon: const Icon(Icons.copy_all, size: 16, color: AppColors.uaYellow),
              label: const Text('COPY ALL',
                  style: TextStyle(color: AppColors.uaYellow, fontSize: 12)),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          TextField(
            controller: _ctrl,
            maxLines: 5,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: AppColors.textPrimary),
            decoration: const InputDecoration(
              hintText: 'Вставте текст для аналізу...',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            icon: const Icon(Icons.radar, size: 18),
            label: const Text('ЕКСТРАКЦІЯ АРТЕФАКТІВ',
                style: TextStyle(letterSpacing: 1, fontWeight: FontWeight.w500)),
            onPressed: _scan,
          ),
          const SizedBox(height: 16),
          Expanded(child: _scanning
              ? Center(child: Column(
                  mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(_matrixChar,
                        style: const TextStyle(
                          color: AppColors.success, fontSize: 42,
                          fontFamily: 'monospace', fontWeight: FontWeight.bold,
                        )),
                    const SizedBox(height: 12),
                    const Text('SCANNING...',
                        style: TextStyle(color: AppColors.textHint,
                            fontFamily: 'monospace', fontSize: 13)),
                  ],
                ))
              : _results.isEmpty
                  ? const Center(child: Text(
                      'Введіть текст і запустіть аналіз',
                      style: TextStyle(color: AppColors.textHint, fontSize: 13),
                    ))
                  : ListView(
                      children: _results.entries.map((entry) {
                        final cfg = _typeConfig[entry.key];
                        final icon  = cfg?.icon  ?? Icons.tag;
                        final color = cfg?.color ?? AppColors.accent;
                        final label = cfg?.label ?? entry.key;
                        return _ScanSection(
                          icon: icon, color: color, label: label,
                          items: entry.value,
                        );
                      }).toList(),
                    ),
          ),
        ]),
      ),
    );
  }
}

class _ScanType {
  final IconData icon;
  final Color color;
  final String label;
  const _ScanType(this.icon, this.color, this.label);
}

class _ScanSection extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final List<String> items;

  const _ScanSection({
    required this.icon, required this.color,
    required this.label, required this.items,
  });

  void _copyItem(BuildContext ctx, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
      content: Text('Скопійовано: $text'),
      backgroundColor: AppColors.uaBlue,
      duration: const Duration(seconds: 1),
    ));
  }

  void _copySection(BuildContext ctx) {
    Clipboard.setData(ClipboardData(text: items.join('\n')));
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
      content: Text('Скопійовано $label (${items.length})'),
      backgroundColor: AppColors.uaBlue,
      duration: const Duration(seconds: 1),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(children: [
        // Заголовок секції
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(icon, color: color, size: 17),
            ),
            const SizedBox(width: 10),
            Text(label,
                style: const TextStyle(
                  fontSize: 12, letterSpacing: 0.5,
                  color: AppColors.textSecondary,
                )),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('${items.length}',
                  style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500)),
            ),
          ]),
        ),
        const Divider(color: AppColors.border, height: 0),
        // Результати
        ...items.map((v) => InkWell(
          onTap: () => _copyItem(context, v),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(children: [
              Expanded(
                child: Text(v,
                    style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 12,
                      color: AppColors.textPrimary,
                    )),
              ),
              const Text('copy',
                  style: TextStyle(
                    fontSize: 10, color: AppColors.uaYellow,
                    letterSpacing: 0.5,
                  )),
            ]),
          ),
        )),
        // Копіювати секцію
        InkWell(
          onTap: () => _copySection(context),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: const Text(
              '+ copy all',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11, color: AppColors.accent, letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
// EXIF АНАЛІЗАТОР
// ─────────────────────────────────────────────
class ExifScreen extends StatefulWidget {
  final Function(String) onLog;
  const ExifScreen({super.key, required this.onLog});
  @override
  State<ExifScreen> createState() => _ExifScreenState();
}

class _ExifScreenState extends State<ExifScreen> {
  Map<String, IfdTag> _data = {};
  bool _loading = false;
  String? _fileName;

  void _pick() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image);
    if (r?.files.single.path == null) return;
    setState(() { _loading = true; _fileName = r!.files.single.name; });
    try {
      final bytes = await File(r!.files.single.path!).readAsBytes();
      final tags  = await readExifFromBytes(bytes);
      if (!mounted) return;
      setState(() { _data = tags; _loading = false; });
      widget.onLog("EXIF: ${r.files.single.name} — ${tags.length} тегів");
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; });
      widget.onLog("EXIF ERR: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('EXIF АНАЛІЗАТОР')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton.icon(
            icon: const Icon(Icons.image_search, size: 18),
            label: Text(_fileName != null ? _fileName! : 'ОБРАТИ ЗОБРАЖЕННЯ',
                overflow: TextOverflow.ellipsis),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.uaBlue),
            onPressed: _pick,
          ),
        ),
        Expanded(child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.uaYellow))
            : _data.isEmpty
                ? const Center(child: Text('Оберіть зображення для аналізу',
                    style: TextStyle(color: AppColors.textHint)))
                : ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: _data.entries.map((e) => Card(
                      color: Colors.white.withValues(alpha: 0.02),
                      margin: const EdgeInsets.only(bottom: 4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: const BorderSide(color: AppColors.border),
                      ),
                      child: ListTile(
                        dense: true,
                        title: Text(e.key,
                            style: const TextStyle(
                              fontSize: 12, color: AppColors.accent,
                              fontFamily: 'monospace',
                            )),
                        subtitle: Text(e.value.toString(),
                            style: const TextStyle(
                              fontSize: 11, color: AppColors.textSecondary,
                            )),
                        onTap: () => Clipboard.setData(
                            ClipboardData(text: '${e.key}: ${e.value}')),
                      ),
                    )).toList(),
                  ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
// GOOGLE DORKS
// ─────────────────────────────────────────────
class DorksScreen extends StatefulWidget {
  final Function(String) onLog;
  const DorksScreen({super.key, required this.onLog});
  @override
  State<DorksScreen> createState() => _DorksScreenState();
}

class _DorksScreenState extends State<DorksScreen> {
  final _ctrl = TextEditingController();
  List<_DorkItem> _dorks = [];

  static const _templates = [
    _DorkTemplate('Файли (PDF, SQL, DB)', Icons.insert_drive_file, [
      'site:{d} ext:pdf', 'site:{d} ext:sql OR ext:db OR ext:bak',
      'site:{d} ext:xlsx OR ext:csv', 'site:{d} ext:env OR ext:config',
    ]),
    _DorkTemplate('Панелі адміністратора', Icons.admin_panel_settings, [
      'site:{d} inurl:admin', 'site:{d} inurl:login OR inurl:signin',
      'site:{d} inurl:wp-admin', 'site:{d} inurl:dashboard',
    ]),
    _DorkTemplate('Відкриті директорії', Icons.folder_open, [
      'site:{d} intitle:"index of"',
      'site:{d} intitle:"index of" parent directory',
      'site:{d} intitle:"directory listing"',
    ]),
    _DorkTemplate('Витоки даних', Icons.leak_add, [
      'site:{d} "password" ext:txt', 'site:{d} "api_key" OR "secret_key"',
      'site:{d} intext:"@gmail.com" ext:txt',
      'site:{d} "DB_PASSWORD" OR "DB_USER"',
    ]),
    _DorkTemplate('Камери / IoT', Icons.videocam_outlined, [
      'site:{d} inurl:"/view/index.shtml"',
      'site:{d} inurl:":8080"', 'site:{d} intitle:"webcam"',
    ]),
    _DorkTemplate('Соцмережі та сліди', Icons.manage_search, [
      'site:linkedin.com "{d}"', 'site:facebook.com "{d}"',
      'site:github.com "{d}"', '"@{d}" email',
    ]),
  ];

  void _generate() {
    final t = _ctrl.text.trim();
    if (t.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _dorks = _templates.expand((tmpl) =>
        tmpl.patterns.map((p) => _DorkItem(
          query: p.replaceAll('{d}', t),
          category: tmpl.label,
          icon: tmpl.icon,
        ))
      ).toList();
    });
    widget.onLog("DORKS: згенеровано ${_dorks.length} для $t");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('GOOGLE DORKS'),
        actions: [
          if (_dorks.isNotEmpty)
            TextButton(
              onPressed: () {
                final all = _dorks.map((d) => d.query).join('\n');
                Clipboard.setData(ClipboardData(text: all));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Скопійовано всі dorks'),
                  backgroundColor: AppColors.uaBlue,
                ));
              },
              child: const Text('COPY ALL',
                  style: TextStyle(color: AppColors.uaYellow, fontSize: 12)),
            ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'Домен або ціль',
                  hintText: 'example.com',
                  prefixIcon: Icon(Icons.travel_explore, size: 18, color: AppColors.accent),
                ),
                onSubmitted: (_) => _generate(),
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(0, 56),
                padding: const EdgeInsets.symmetric(horizontal: 18),
              ),
              onPressed: _generate,
              child: const Text('GO'),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        Expanded(child: _dorks.isEmpty
            ? const Center(child: Text('Введіть домен і натисніть GO',
                style: TextStyle(color: AppColors.textHint)))
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                itemCount: _dorks.length,
                itemBuilder: (ctx, i) {
                  final d = _dorks[i];
                  final showHeader = i == 0 || _dorks[i-1].category != d.category;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (showHeader) Padding(
                        padding: const EdgeInsets.only(top: 14, bottom: 6, left: 4),
                        child: Row(children: [
                          Icon(d.icon, size: 14, color: AppColors.uaYellow),
                          const SizedBox(width: 6),
                          Text(d.category,
                              style: const TextStyle(
                                fontSize: 11, color: AppColors.uaYellow,
                                letterSpacing: 0.8,
                              )),
                        ]),
                      ),
                      Card(
                        color: Colors.white.withValues(alpha: 0.02),
                        margin: const EdgeInsets.only(bottom: 4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: const BorderSide(color: AppColors.border),
                        ),
                        child: ListTile(
                          dense: true,
                          title: Text(d.query,
                              style: const TextStyle(
                                fontFamily: 'monospace', fontSize: 11,
                                color: AppColors.textPrimary,
                              )),
                          trailing: const Icon(Icons.copy_outlined,
                              size: 15, color: AppColors.textHint),
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: d.query));
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(d.query, style: const TextStyle(fontSize: 11)),
                              backgroundColor: AppColors.uaBlue,
                              duration: const Duration(seconds: 1),
                            ));
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
        ),
      ]),
    );
  }
}

class _DorkTemplate {
  final String label;
  final IconData icon;
  final List<String> patterns;
  const _DorkTemplate(this.label, this.icon, this.patterns);
}

class _DorkItem {
  final String query, category;
  final IconData icon;
  const _DorkItem({required this.query, required this.category, required this.icon});
}

// ─────────────────────────────────────────────
// PDF ПЕРЕГЛЯДАЧ
// ─────────────────────────────────────────────
class PDFViewerScreen extends StatelessWidget {
  final PDFDoc doc;
  const PDFViewerScreen({super.key, required this.doc});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: Text(doc.name, overflow: TextOverflow.ellipsis)),
      body: PDFView(filePath: doc.path),
    );
  }
}

// ─────────────────────────────────────────────
// ГЕНЕРАТОР ПРОМПТІВ
// ─────────────────────────────────────────────
class GenScreen extends StatefulWidget {
  final Prompt p;
  final Function(String) onLog;
  const GenScreen({super.key, required this.p, required this.onLog});
  @override
  State<GenScreen> createState() => _GenScreenState();
}

class _GenScreenState extends State<GenScreen> {
  final Map<String, TextEditingController> _ctrls = {};
  String _result = '';
  bool _compiled = false;

  @override
  void initState() {
    super.initState();
    _result = widget.p.content;
    for (final v in widget.p.variables) {
      _ctrls[v] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) { c.dispose(); }
    super.dispose();
  }

  void _compile() {
    String t = widget.p.content;
    _ctrls.forEach((k, v) => t = t.replaceAll('{$k}', v.text.isEmpty ? '{$k}' : v.text));
    setState(() { _result = t; _compiled = true; });
    widget.onLog("Генерація: ${widget.p.title}");
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final hasVars = _ctrls.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFF091630),
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('ГЕНЕРАТОР', style: TextStyle(fontSize: 14, letterSpacing: 1.5)),
          Text(widget.p.title,
              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
              overflow: TextOverflow.ellipsis),
        ]),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (hasVars) ...[
            const Text('ПАРАМЕТРИ',
                style: TextStyle(
                  fontSize: 10, letterSpacing: 1.5,
                  color: AppColors.uaYellow,
                )),
            const SizedBox(height: 10),
            ..._ctrls.keys.map((k) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(
                controller: _ctrls[k],
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  labelText: k,
                  prefixText: '{  ',
                  prefixStyle: const TextStyle(color: AppColors.textHint, fontFamily: 'monospace'),
                ),
              ),
            )),
            const SizedBox(height: 6),
            ElevatedButton.icon(
              icon: const Icon(Icons.bolt, size: 17),
              label: const Text('КОМПІЛЮВАТИ',
                  style: TextStyle(letterSpacing: 1)),
              onPressed: _compile,
            ),
            const SizedBox(height: 14),
          ],
          if (!hasVars || _compiled) ...[
            Row(children: [
              const Text('РЕЗУЛЬТАТ',
                  style: TextStyle(
                    fontSize: 10, letterSpacing: 1.5,
                    color: AppColors.uaYellow,
                  )),
              const Spacer(),
              if (_compiled)
                const Icon(Icons.check_circle, color: AppColors.success, size: 14),
            ]),
            const SizedBox(height: 8),
          ],
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _compiled ? AppColors.success.withValues(alpha: 0.3) : AppColors.border,
                ),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  _result,
                  style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 13,
                    color: AppColors.textPrimary, height: 1.6,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.copy, size: 16, color: AppColors.textSecondary),
                label: const Text('COPY',
                    style: TextStyle(color: AppColors.textSecondary, letterSpacing: 0.8)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.border),
                  minimumSize: const Size(0, 46),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _result));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Скопійовано в буфер'),
                    backgroundColor: AppColors.uaBlue,
                    duration: Duration(seconds: 1),
                  ));
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.share, size: 16),
                label: const Text('SHARE', style: TextStyle(letterSpacing: 0.8)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.uaYellow,
                  foregroundColor: Colors.black,
                  minimumSize: const Size(0, 46),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => Share.share(_result),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// ГРА "KREMLIN COTTON" (пасхалка)
// ─────────────────────────────────────────────
class CottonGame extends StatefulWidget {
  final Function(String) onLog;
  const CottonGame({super.key, required this.onLog});
  @override
  State<CottonGame> createState() => _CottonGameState();
}

class _CottonGameState extends State<CottonGame> with SingleTickerProviderStateMixin {
  double dX = 0.5, bX = -1, bY = -1;
  List<double> targets = [0.1, 0.4, 0.7, 0.9];
  int score = 0;
  Timer? _gameTimer;
  late AnimationController _fireCtrl;

  @override
  void initState() {
    super.initState();
    _fireCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 1))
        ..repeat(reverse: true);
    _gameTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!mounted) return;
      setState(() {
        for (int i = 0; i < targets.length; i++) {
          targets[i] += 0.015;
          if (targets[i] > 1.1) targets[i] = -0.1;
        }
        if (bY >= 0) {
          bY += 0.04;
          if (bY > 0.85) {
            for (int i = 0; i < targets.length; i++) {
              if ((bX - targets[i]).abs() < 0.1) {
                score++;
                targets[i] = -0.5;
                widget.onLog("БАВОВНА! Ціль №$score ліквідована.");
              }
            }
            bY = -1; bX = -1;
          }
        }
      });
    });
  }

  @override
  void dispose() {
    _gameTimer?.cancel();
    _fireCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final h = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapDown: (d) {
          final x = d.globalPosition.dx / w;
          if (x < 0.3)      setState(() => dX = (dX - 0.1).clamp(0.05, 0.95));
          else if (x > 0.7) setState(() => dX = (dX + 0.1).clamp(0.05, 0.95));
          else if (bY < 0)  setState(() { bX = dX; bY = 0.15; });
        },
        child: Stack(children: [
          // Фон — силует
          Positioned(bottom: 0, left: 0, right: 0, height: 180,
            child: Stack(children: [
              Container(decoration: const BoxDecoration(
                color: Color(0xFF0A152F),
                borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
              )),
              Positioned(bottom: 0, left: w * 0.4, width: w * 0.2, height: 160,
                child: Column(children: [
                  Container(width: w * 0.15, height: 100, color: AppColors.uaBlue),
                  Container(width: 20, height: 20,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle, color: AppColors.uaYellow,
                      )),
                ])),
            ]),
          ),
          // Вогонь
          AnimatedBuilder(
            animation: _fireCtrl,
            builder: (_, __) => Positioned(
              bottom: 160, left: w * 0.45, width: w * 0.1, height: 30,
              child: Container(decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: _fireCtrl.value * 0.8),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [BoxShadow(color: Colors.orange, blurRadius: 20 * _fireCtrl.value)],
              )),
            ),
          ),
          // Цілі
          ...targets.map((tx) => AnimatedPositioned(
            duration: Duration.zero, bottom: 60, left: tx * w,
            child: const Column(children: [
              CircleAvatar(radius: 6, backgroundColor: Colors.grey),
              Icon(Icons.person, color: Colors.white, size: 35),
            ]),
          )),
          // Бомба
          if (bY >= 0)
            AnimatedPositioned(
              duration: Duration.zero, top: bY * h, left: bX * w,
              child: const Icon(Icons.wb_sunny, color: Colors.orange, size: 30),
            ),
          // Дрон
          AnimatedPositioned(
            duration: const Duration(milliseconds: 100),
            top: 80, left: dX * w - 30,
            child: const Icon(Icons.airplanemode_active, color: AppColors.accent, size: 60),
          ),
          // HUD
          Positioned(
            top: 40, left: 20,
            child: Text(
              'SCORE: $score\nSTATUS: HOT_ZONE',
              style: const TextStyle(
                color: AppColors.success, fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          // Вихід
          Positioned(
            bottom: 20, right: 20,
            child: IconButton(
              icon: const Icon(Icons.close, color: AppColors.textHint),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ]),
      ),
    );
  }
}
