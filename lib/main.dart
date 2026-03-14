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
import 'dart:ui';
import 'dart:async';
import 'dart:math';

void main() {
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarColor: Colors.transparent));
  runApp(const PromptApp());
}

class Prompt {
  String id, title, content, category;
  bool isFavorite;
  Prompt({required this.id, required this.title, required this.content, required this.category, this.isFavorite = false});
  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'content': content, 'category': category, 'isFavorite': isFavorite};
  factory Prompt.fromJson(Map<String, dynamic> json) => Prompt(id: json['id'], title: json['title'], content: json['content'], category: json['category'], isFavorite: json['isFavorite'] ?? false);
}

class PDFDoc {
  String id, name, path;
  PDFDoc({required this.id, required this.name, required this.path});
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'path': path};
  factory PDFDoc.fromJson(Map<String, dynamic> json) => PDFDoc(id: json['id'], name: json['name'], path: json['path']);
}

class PromptApp extends StatelessWidget {
  const PromptApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF040E22), 
        appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, elevation: 0),
        tabBarTheme: const TabBarTheme(
          labelColor: Color(0xFFFFD700),
          unselectedLabelColor: Colors.white54,
          indicator: UnderlineTabIndicator(borderSide: BorderSide(color: Color(0xFFFFD700), width: 2)),
        ),
      ),
      home: const MainScreen(),
    );
  }
}

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
  int _secretCounter = 0; // Для пасхалки

  final List<String> categories = ['ФО', 'ЮО', 'ГЕОІНТ', 'МОНІТОРИНГ', 'ІНСТРУМЕНТИ', 'ДОКУМЕНТИ'];
  final Color uaBlue = const Color(0xFF0057B7);
  final Color uaYellow = const Color(0xFFFFD700);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: categories.length, vsync: this);
    _tabController.addListener(() { setState(() {}); });
    _loadData();
  }

  void _logAction(String action) {
    final now = DateTime.now();
    final timeStr = "${now.day.toString().padLeft(2,'0')}.${now.month.toString().padLeft(2,'0')} ${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}";
    setState(() {
      auditLogs.insert(0, "[$timeStr] $action");
      if (auditLogs.length > 50) auditLogs.removeLast();
    });
    _save();
  }

  void _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final String? pStr = prefs.getString('prompts_data');
    final String? dStr = prefs.getString('docs_data');
    final List<String>? logs = prefs.getStringList('audit_logs');
    setState(() {
      if (pStr != null) prompts = (json.decode(pStr) as List).map((i) => Prompt.fromJson(i)).toList();
      if (dStr != null) docs = (json.decode(dStr) as List).map((i) => PDFDoc.fromJson(i)).toList();
      if (logs != null) auditLogs = logs;
      if (prompts.isEmpty) {
        prompts = [Prompt(id: '1', title: 'Аналіз фізичної особи', category: 'ФО', isFavorite: true, content: 'Ти - аналітик OSINT. Проведи пошук: ПІБ - {ПІБ}, ДН - {дата_народження}.')];
        _logAction("Створено базовий профіль");
      }
    });
  }

  void _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('prompts_data', json.encode(prompts.map((p) => p.toJson()).toList()));
    await prefs.setString('docs_data', json.encode(docs.map((d) => d.toJson()).toList()));
    await prefs.setStringList('audit_logs', auditLogs);
  }

  void _importFromTxt() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['txt']);
    if (result != null && result.files.single.path != null) {
      try {
        String content = await File(result.files.single.path!).readAsString();
        List<Prompt> imported = [];
        for (var block in content.split('===')) {
          if (block.trim().isEmpty) continue;
          String cat = 'МОНІТОРИНГ', title = '', text = '';
          bool isText = false;
          for (var line in block.trim().split('\n')) {
            String lineLow = line.toLowerCase().trim();
            if (lineLow.startsWith('категорія:')) {
              String rawCat = lineLow.replaceFirst('категорія:', '').trim();
              if (rawCat == 'фо' || rawCat.contains('фіз')) cat = 'ФО';
              else if (rawCat == 'юо' || rawCat.contains('юр')) cat = 'ЮО';
              else if (rawCat.contains('гео')) cat = 'ГЕОІНТ';
              else if (rawCat.contains('мон')) cat = 'МОНІТОРИНГ';
            }
            else if (lineLow.startsWith('назва:')) title = line.replaceFirst(RegExp(r'Назва:', caseSensitive: false), '').trim();
            else if (lineLow.startsWith('текст:')) { text = line.replaceFirst(RegExp(r'Текст:', caseSensitive: false), '').trim(); isText = true; }
            else if (isText) text += '\n$line';
          }
          if (title.isNotEmpty && text.isNotEmpty) imported.add(Prompt(id: DateTime.now().millisecondsSinceEpoch.toString() + imported.length.toString(), title: title, content: text.trim(), category: cat));
        }
        setState(() => prompts.addAll(imported));
        _logAction("SYS: Імпортовано TXT (${imported.length} записів)");
        _save();
      } catch (e) {
        _logAction("ERR: Помилка імпорту");
      }
    }
  }

  void _addOrEditPrompt({Prompt? p}) {
    final tCtrl = TextEditingController(text: p?.title ?? '');
    final cCtrl = TextEditingController(text: p?.content ?? '');
    String selectedCat = p?.category ?? categories[_tabController.index > 3 ? 0 : _tabController.index];
    if (selectedCat == 'ДОКУМЕНТИ' || selectedCat == 'ІНСТРУМЕНТИ') selectedCat = 'ФО';

    showDialog(context: context, builder: (ctx) => StatefulBuilder(
      builder: (context, setDialogState) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0A152F),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: uaBlue, width: 1)),
          title: Text(p == null ? 'НОВИЙ ЗАПИС' : 'РЕДАГУВАННЯ', style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.1, fontSize: 16)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                value: selectedCat,
                dropdownColor: const Color(0xFF0A152F),
                items: ['ФО', 'ЮО', 'ГЕОІНТ', 'МОНІТОРИНГ'].map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontFamily: 'monospace')))).toList(),
                onChanged: (val) => setDialogState(() => selectedCat = val!),
                decoration: InputDecoration(labelText: 'КЛАСИФІКАЦІЯ', labelStyle: TextStyle(color: uaYellow)),
              ),
              const SizedBox(height: 16),
              TextField(controller: tCtrl, decoration: const InputDecoration(labelText: 'ІДЕНТИФІКАТОР')),
              const SizedBox(height: 16),
              TextField(controller: cCtrl, maxLines: 5, decoration: const InputDecoration(labelText: 'МАСИВ ДАНИХ {ЗМІННІ}')),
            ]),
          ),
          actions: [
            if (p != null) TextButton(onPressed: () { setState(() => prompts.remove(p)); _logAction("Видалено запис: ${p.title}"); _save(); Navigator.pop(ctx); }, child: const Text('ВИДАЛИТИ', style: TextStyle(color: Colors.redAccent))),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('СКАСУВАТИ', style: TextStyle(color: Colors.white54))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: uaBlue, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4))),
              onPressed: () {
                setState(() {
                  if (p == null) { prompts.add(Prompt(id: DateTime.now().toString(), title: tCtrl.text, content: cCtrl.text, category: selectedCat)); _logAction("Створено запис: ${tCtrl.text}"); }
                  else { p.title = tCtrl.text; p.content = cCtrl.text; p.category = selectedCat; _logAction("Оновлено запис: ${tCtrl.text}"); }
                });
                _save(); Navigator.pop(ctx);
              }, child: const Text('ЗАПИСАТИ', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      }
    ));
  }

  void _pickPDF() async {
    FilePickerResult? r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    if (r != null && r.files.single.path != null) {
      final dir = await getApplicationDocumentsDirectory();
      final uniqueName = '${DateTime.now().millisecondsSinceEpoch}_${r.files.single.name}';
      final newPath = '${dir.path}/$uniqueName';
      await File(r.files.single.path!).copy(newPath);
      setState(() => docs.add(PDFDoc(id: DateTime.now().toString(), name: r.files.single.name, path: newPath)));
      _logAction("SYS: Додано документ ${r.files.single.name}");
      _save();
    }
  }

  // СЕКРЕТНИЙ SYS.INFO З ТРИГЕРОМ ГРИ
  void _showSysInfo() {
    _secretCounter = 0;
    Map<String, int> stats = {'ФО': 0, 'ЮО': 0, 'ГЕОІНТ': 0, 'МОНІТОРИНГ': 0};
    for (var p in prompts) { if (stats.containsKey(p.category)) stats[p.category] = stats[p.category]! + 1; }
    
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF040E22),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: uaYellow, width: 1)),
      title: Row(children: [
        GestureDetector(
          onTap: () {
            _secretCounter++;
            if (_secretCounter >= 5) {
              Navigator.pop(ctx);
              _logAction("SYS: Операція БАВОВНА активована!");
              Navigator.push(context, MaterialPageRoute(builder: (_) => CottonGame(onLog: _logAction)));
            }
          },
          child: Icon(Icons.analytics, color: uaYellow)
        ), 
        const SizedBox(width: 10), 
        const Text('SYS.INFO', style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold))
      ]),
      content: Column(
        mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _infoRow('TOTAL RECORDS:', prompts.length.toString()),
          _infoRow('SECURE DOCS:', docs.length.toString()),
          const Divider(color: Colors.white24, height: 20),
          _infoRow('ФО (Фізособи):', stats['ФО'].toString()),
          _infoRow('ЮО (Компанії):', stats['ЮО'].toString()),
          _infoRow('ГЕОІНТ:', stats['ГЕОІНТ'].toString()),
          _infoRow('МОНІТОРИНГ:', stats['МОНІТОРИНГ'].toString()),
        ],
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text('CLOSE', style: TextStyle(color: uaYellow)))],
    ));
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontFamily: 'monospace', fontSize: 13)),
        Text(value, style: TextStyle(color: uaBlue, fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 16)),
      ]),
    );
  }

  void _showAuditLog() {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF040E22),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: uaBlue, width: 1)),
      title: const Row(children: [Icon(Icons.terminal, color: Colors.white54), SizedBox(width: 10), Text('AUDIT_LOG', style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold))]),
      content: SizedBox(
        width: double.maxFinite, height: 300,
        child: auditLogs.isEmpty ? const Center(child: Text('NO RECORDS')) : ListView.builder(itemCount: auditLogs.length, itemBuilder: (context, index) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(auditLogs[index], style: const TextStyle(color: Colors.greenAccent, fontFamily: 'monospace', fontSize: 11)))),
      ),
      actions: [
        TextButton(onPressed: () { setState(() { auditLogs.clear(); _save(); }); Navigator.pop(ctx); }, child: const Text('CLEAR', style: TextStyle(color: Colors.redAccent))),
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CLOSE', style: TextStyle(color: Colors.white54))),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Row(mainAxisSize: MainAxisSize.min, children: [Text('🔱', style: TextStyle(color: uaYellow, fontSize: 20)), const SizedBox(width: 8), const Text('UKR_OSINT', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2.0, fontSize: 18))]),
        actions: [
          IconButton(icon: Icon(Icons.data_usage, color: uaYellow, size: 22), onPressed: _showSysInfo),
          IconButton(icon: const Icon(Icons.receipt_long, color: Colors.white70, size: 22), onPressed: _showAuditLog),
          IconButton(icon: Icon(Icons.download, color: uaBlue, size: 24), onPressed: _importFromTxt),
        ],
        bottom: TabBar(controller: _tabController, isScrollable: true, tabs: categories.map((c) => Tab(text: c)).toList()),
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF040B16), Color(0xFF091630), Color(0xFF040E22)])),
        child: SafeArea(
          child: TabBarView(
            controller: _tabController,
            children: categories.map((cat) {
              if (cat == 'ДОКУМЕНТИ') {
                return ListView.builder(
                  itemCount: docs.length, padding: const EdgeInsets.only(top: 10, bottom: 90),
                  itemBuilder: (ctx, i) => Card(
                    color: Colors.white.withOpacity(0.03), margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: ListTile(
                      leading: const Icon(Icons.description, color: Colors.white54, size: 28),
                      title: Text(docs[i].name),
                      onTap: () { Navigator.push(context, MaterialPageRoute(builder: (_) => PDFViewerScreen(doc: docs[i]))); },
                      trailing: IconButton(icon: const Icon(Icons.close, color: Colors.white24), onPressed: () { setState(() => docs.removeAt(i)); _save(); }),
                    ),
                  ),
                );
              }
              if (cat == 'ІНСТРУМЕНТИ') return ToolsMenuScreen(onLog: _logAction);
              final items = prompts.where((p) => p.category == cat).toList();
              items.sort((a, b) => (b.isFavorite ? 1 : 0).compareTo(a.isFavorite ? 1 : 0));
              return ReorderableListView.builder(
                padding: const EdgeInsets.only(top: 10, bottom: 90), itemCount: items.length,
                onReorder: (oldIdx, newIdx) {
                  setState(() { if (newIdx > oldIdx) newIdx -= 1; final item = items.removeAt(oldIdx); items.insert(newIdx, item); prompts.removeWhere((p) => p.category == cat); prompts.addAll(items); });
                  _save();
                },
                itemBuilder: (ctx, i) {
                  final p = items[i];
                  return Card(
                    key: ValueKey(p.id), color: Colors.white.withOpacity(0.03), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: p.isFavorite ? uaYellow.withOpacity(0.3) : Colors.transparent)), margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: ListTile(
                      leading: IconButton(icon: Icon(p.isFavorite ? Icons.star : Icons.star_border, color: p.isFavorite ? uaYellow : Colors.white24), onPressed: () { setState(() => p.isFavorite = !p.isFavorite); _save(); }),
                      title: Text(p.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(p.content, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white38, fontFamily: 'monospace')),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GenScreen(p: p, onLog: _logAction))),
                      onLongPress: () => _addOrEditPrompt(p: p),
                    ),
                  );
                },
              );
            }).toList(),
          ),
        ),
      ),
      floatingActionButton: _tabController.index == 4 ? null : FloatingActionButton(
        backgroundColor: uaBlue, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: uaYellow, width: 1.5)),
        onPressed: () => _tabController.index == 5 ? _pickPDF() : _addOrEditPrompt(),
        child: Icon(_tabController.index == 5 ? Icons.note_add : Icons.add, color: Colors.white),
      ),
    );
  }
}

// --- ТАКТИЧНИЙ СИМУЛЯТОР "KREMLIN COTTON" (2D Гра) ---
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
  Timer? gameTimer;
  late AnimationController _fireCtrl;

  @override
  void initState() {
    super.initState();
    _fireCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);
    gameTimer = Timer.periodic(const Duration(milliseconds: 50), (t) {
      if (!mounted) return;
      setState(() {
        // Рух цілей
        for (int i = 0; i < targets.length; i++) {
          targets[i] += 0.015;
          if (targets[i] > 1.1) targets[i] = -0.1;
        }
        // Рух бомби
        if (bY >= 0) {
          bY += 0.04;
          if (bY > 0.85) { // Рівень стіни
            for (int i = 0; i < targets.length; i++) {
              if ((bX - targets[i]).abs() < 0.1) { // Влучання
                score++;
                targets[i] = -0.5; // Прибираємо ціль
                widget.onLog("БАВОВНА! Ціль №${score} ліквідована.");
              }
            }
            bY = -1; bX = -1; // Бомба зникає
          }
        }
      });
    });
  }

  @override
  void dispose() { gameTimer?.cancel(); _fireCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final h = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapDown: (details) {
          double x = details.globalPosition.dx / w;
          if (x < 0.3) setState(() => dX = (dX - 0.1).clamp(0.05, 0.95));
          else if (x > 0.7) setState(() => dX = (dX + 0.1).clamp(0.05, 0.95));
          else if (bY < 0) setState(() { bX = dX; bY = 0.15; }); // Скидання
        },
        child: Stack(
          children: [
            // Силует Кремля та Вежі (Тактичний синій)
            Positioned(bottom: 0, left: 0, right: 0, height: 180, child: Stack(children: [
              Container(decoration: const BoxDecoration(color: Color(0xFF0A152F), borderRadius: BorderRadius.vertical(top: Radius.circular(30)))),
              Positioned(bottom: 0, left: w * 0.4, width: w * 0.2, height: 160, child: Column(children: [
                Container(width: w * 0.15, height: 100, color: const Color(0xFF0057B7)), // Спаська вежа
                Container(width: 20, height: 20, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFFFD700))), // Годинник
              ])),
            ])),
            // Анімація ВОГНЮ на вежі
            AnimatedBuilder(animation: _fireCtrl, builder: (ctx, child) => Positioned(
              bottom: 160, left: w * 0.45, width: w * 0.1, height: 30,
              child: Container(decoration: BoxDecoration(color: Colors.orange.withOpacity(_fireCtrl.value * 0.8), borderRadius: BorderRadius.circular(10), boxShadow: [BoxShadow(color: Colors.orange, blurRadius: 20 * _fireCtrl.value)])))),
            // Цілі (Впізнавані силуети)
            ...targets.map((tx) => AnimatedPositioned(
              duration: Duration.zero, bottom: 60, left: tx * w,
              child: const Column(children: [
                CircleAvatar(radius: 6, backgroundColor: Colors.grey), // Лисина
                Icon(Icons.person, color: Colors.white, size: 35), // Костюм
              ]),
            )),
            // Бомба
            if (bY >= 0) AnimatedPositioned(duration: Duration.zero, top: bY * h, left: bX * w, child: const Icon(Icons.wb_sunny, color: Colors.orange, size: 30)),
            // Ударний Дрон
            AnimatedPositioned(duration: const Duration(milliseconds: 100), top: 80, left: dX * w - 30, child: const Icon(Icons.airplanemode_active, color: Color(0xFF60A5FA), size: 60)),
            // Інфопанель
            Positioned(top: 40, left: 20, child: Text('SCORE: $score\nSTATUS: HOT_ZONE', style: const TextStyle(color: Colors.greenAccent, fontFamily: 'monospace', fontWeight: FontWeight.bold))),
            // Вихід
            Positioned(bottom: 20, right: 20, child: IconButton(icon: const Icon(Icons.close, color: Colors.white24), onPressed: () => Navigator.pop(context))),
          ],
        ),
      ),
    );
  }
}

// --- ІНШІ МОДУЛІ (СКАНЕР, EXIF, DORKS) ТЕЖ ОНОВЛЕНІ ---
class ToolsMenuScreen extends StatelessWidget {
  final Function(String) onLog;
  const ToolsMenuScreen({super.key, required this.onLog});
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(top: 20),
      children: [
        _tool(context, 'СКАНЕР', 'Екстракція артефактів', Icons.radar, ScannerScreen(onLog: onLog)),
        _tool(context, 'EXIF', 'Аналіз метаданих', Icons.image_search, ExifScreen(onLog: onLog)),
        _tool(context, 'DORKS', 'Google Конструктор', Icons.travel_explore, DorksScreen(onLog: onLog)),
      ],
    );
  }
  Widget _tool(ctx, t, s, i, scr) => Card(color: Colors.white.withOpacity(0.03), margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: ListTile(leading: Icon(i, color: const Color(0xFFFFD700)), title: Text(t), subtitle: Text(s), onTap: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => scr))));
}

class ScannerScreen extends StatefulWidget {
  final Function(String) onLog;
  const ScannerScreen({super.key, required this.onLog});
  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}
class _ScannerScreenState extends State<ScannerScreen> {
  final TextEditingController _c = TextEditingController();
  Map<String, List<String>> _r = {};
  bool _is = false; String _m = ""; Timer? _mt;
  void _scan() async {
    FocusScope.of(context).unfocus();
    setState(() { _is = true; _r.clear(); });
    _mt = Timer.periodic(const Duration(milliseconds: 50), (t) => setState(() => _m = List.generate(100, (i) => 'X')[Random().nextInt(5)]));
    await Future.delayed(const Duration(seconds: 1));
    final ip = RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b').allMatches(_c.text).map((m) => m.group(0)!).toList();
    final em = RegExp(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}').allMatches(_c.text).map((m) => m.group(0)!).toList();
    _mt?.cancel(); setState(() { _is = false; _r = {'IP': ip, 'EMAIL': em}; });
    widget.onLog("SYS: Скан завершено. Знайдено ${ip.length + em.length} артефактів.");
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(backgroundColor: const Color(0xFF040E22), appBar: AppBar(title: const Text('СКАНЕР')), body: Padding(padding: const EdgeInsets.all(16), child: Column(children: [TextField(controller: _c, maxLines: 5, decoration: InputDecoration(filled: true, fillColor: const Color(0xFF0A152F), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), hintText: 'Вставте текст...')), const SizedBox(height: 10), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFD700), minimumSize: const Size(double.infinity, 50)), onPressed: _scan, child: const Text('ЕКСТРАКЦІЯ', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold))), const SizedBox(height: 10), Expanded(child: _is ? Center(child: Text(_m, style: const TextStyle(color: Colors.greenAccent, fontSize: 18))) : ListView(children: _r.entries.map((e) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('>> ${e.key}', style: const TextStyle(color: Color(0xFFFFD700), fontWeight: FontWeight.bold)), ...e.value.map((v) => ListTile(title: Text(v), onTap: () => Clipboard.setData(ClipboardData(text: v))))] )).toList() ))])));
  }
}

class ExifScreen extends StatefulWidget {
  final Function(String) onLog;
  const ExifScreen({super.key, required this.onLog});
  @override
  State<ExifScreen> createState() => _ExifScreenState();
}
class _ExifScreenState extends State<ExifScreen> {
  Map<String, dynamic> _d = {};
  void _pick() async {
    FilePickerResult? r = await FilePicker.platform.pickFiles(type: FileType.image);
    if (r != null) {
      final bytes = await File(r.files.single.path!).readAsBytes();
      final t = await readExifFromBytes(bytes);
      setState(() => _d = t);
      widget.onLog("SYS: EXIF аналіз. Знайдено ${t.length} тегів.");
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(backgroundColor: const Color(0xFF040E22), appBar: AppBar(title: const Text('EXIF АНАЛІЗАТОР')), body: Column(children: [ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0057B7), minimumSize: const Size(double.infinity, 50)), onPressed: _pick, child: const Text('ОБРАТИ ФОТО')), Expanded(child: ListView(children: _d.entries.map((e) => Card(color: Colors.white.withOpacity(0.01), child: ListTile(title: Text(e.key), subtitle: Text(e.value.toString())))).toList()))]));
  }
}

class DorksScreen extends StatefulWidget {
  final Function(String) onLog;
  const DorksScreen({super.key, required this.onLog});
  @override
  State<DorksScreen> createState() => _DorksScreenState();
}
class _DorksScreenState extends State<DorksScreen> {
  final _t = TextEditingController(); List<String> _d = [];
  void _gen() { String t = _t.text.trim(); if(t.isNotEmpty) { setState(() => _d = ["site:$t ext:pdf", "site:$t inurl:admin", "site:$t ext:sql OR ext:db", "site:$t intitle:\"index of\"", "site:$t \"password\" ext:txt"]); widget.onLog("SYS: Згенеровано Dorks для $t"); FocusScope.of(context).unfocus(); } }
  @override
  Widget build(BuildContext context) {
    return Scaffold(backgroundColor: const Color(0xFF040E22), appBar: AppBar(title: const Text('GOOGLE DORKS')), body: Padding(padding: const EdgeInsets.all(16), child: Column(children: [TextField(controller: _t, decoration: InputDecoration(labelText: 'Домен (напр. target.com)', filled: true, fillColor: const Color(0xFF0A152F))), const SizedBox(height: 10), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0057B7), minimumSize: const Size(double.infinity, 50)), onPressed: _gen, child: const Text('ГЕНЕРУВАТИ АТАКУ')), const SizedBox(height: 10), Expanded(child: ListView(children: _d.map((e) => Card(color: Colors.white.withOpacity(0.01), child: ListTile(title: Text(e), onTap: () => Clipboard.setData(ClipboardData(text: e))))).toList()))])));
  }
}

class PDFViewerScreen extends StatelessWidget {
  final PDFDoc doc;
  const PDFViewerScreen({super.key, required this.doc});
  @override
  Widget build(BuildContext context) {
    return Scaffold(backgroundColor: const Color(0xFF040E22), appBar: AppBar(title: Text(doc.name)), body: PDFView(filePath: doc.path));
  }
}

class GenScreen extends StatefulWidget {
  final Prompt p;
  final Function(String) onLog;
  const GenScreen({super.key, required this.p, required this.onLog});
  @override
  State<GenScreen> createState() => _GenScreenState();
}
class _GenScreenState extends State<GenScreen> {
  final Map<String, TextEditingController> _ctrls = {};
  String _res = '';
  @override
  void initState() {
    super.initState();
    _res = widget.p.content;
    final reg = RegExp(r'\{([^}]+)\}');
    for (var m in reg.allMatches(widget.p.content)) { _ctrls[m.group(1)!] = TextEditingController(); }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(backgroundColor: const Color(0xFF091630), appBar: AppBar(title: const Text('ГЕНЕРАТОР ПРОМПТІВ')), body: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('ПАРАМЕТРИ:', style: TextStyle(color: const Color(0xFFFFD700))), ..._ctrls.keys.map((k) => TextField(controller: _ctrls[k], decoration: InputDecoration(labelText: k, filled: true, fillColor: const Color(0xFF040E22)))), const SizedBox(height: 10), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0057B7), minimumSize: const Size(double.infinity, 50)), onPressed: () { String t = widget.p.content; _ctrls.forEach((k, v) => t = t.replaceAll('{$k}', v.text.isEmpty ? '{$k}' : v.text)); setState(() => _res = t); widget.onLog("Генерація: ${widget.p.title}"); }, child: const Text('КОМПІЛЮВАТИ')), const SizedBox(height: 10), Expanded(child: Container(width: double.infinity, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8)), child: SingleChildScrollView(child: SelectableText(_res, style: const TextStyle(fontFamily: 'monospace'))))), const SizedBox(height: 10), Row(children: [Expanded(child: ElevatedButton(onPressed: () => Clipboard.setData(ClipboardData(text: _res)), child: const Text('COPY'))), const SizedBox(width: 10), Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFD700)), onPressed: () => Share.share(_res), child: const Text('SHARE', style: TextStyle(color: Colors.black))))])])));
  }
}
