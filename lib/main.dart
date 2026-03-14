import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:exif/exif.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'dart:async';
import 'dart:math';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(statusBarColor: Colors.transparent));
  runApp(const PromptApp());
}

// --- МОДЕЛІ ДАНИХ ---

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

// --- ГОЛОВНИЙ ВХІД ---

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
      home: const SplashScreen(),
    );
  }
}

// --- ЕКРАН ЗАСТАВКИ (SPLASH SCREEN) ---

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(milliseconds: 1800), () {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => const MainScreen(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 800),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/splash.png'),
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }
}

// --- ГОЛОВНИЙ ЕКРАН ---

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

  final List<String> categories = ['ФО', 'ЮО', 'ГЕОІНТ', 'МОНІТОРИНГ', 'ІНСТРУМЕНТИ', 'ДОКУМЕНТИ'];
  final Color uaBlue = const Color(0xFF0057B7);
  final Color uaYellow = const Color(0xFFFFD700);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: categories.length, vsync: this);
    _tabController.addListener(() { if (mounted) setState(() {}); });
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
        prompts = [Prompt(id: '1', title: 'Базовий промпт ФО', category: 'ФО', isFavorite: true, content: 'Аналіз фізичної особи: {ПІБ}. Пріоритет: OSINT.')];
        _logAction("Ініціалізація бази даних");
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
            String l = line.toLowerCase().trim();
            if (l.startsWith('категорія:')) cat = l.replaceFirst('категорія:', '').trim().toUpperCase();
            else if (l.startsWith('назва:')) title = line.replaceFirst(RegExp(r'Назва:', caseSensitive: false), '').trim();
            else if (l.startsWith('текст:')) { text = line.replaceFirst(RegExp(r'Текст:', caseSensitive: false), '').trim(); isText = true; }
            else if (isText) text += '\n$line';
          }
          if (title.isNotEmpty && text.isNotEmpty) imported.add(Prompt(id: "${DateTime.now().millisecondsSinceEpoch}_${imported.length}", title: title, content: text.trim(), category: cat));
        }
        setState(() => prompts.addAll(imported));
        _logAction("SYS: Імпортовано ${imported.length} записів");
        _save();
      } catch (e) { _logAction("ERR: Помилка TXT"); }
    }
  }

  void _addOrEditPrompt({Prompt? p}) {
    final tCtrl = TextEditingController(text: p?.title ?? '');
    final cCtrl = TextEditingController(text: p?.content ?? '');
    String selectedCat = p?.category ?? 'ФО';

    showDialog(context: context, builder: (ctx) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        backgroundColor: const Color(0xFF0A152F),
        title: Text(p == null ? 'НОВИЙ ЗАПИС' : 'РЕДАГУВАННЯ'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
            value: ['ФО','ЮО','ГЕОІНТ','МОНІТОРИНГ'].contains(selectedCat) ? selectedCat : 'ФО',
            items: ['ФО','ЮО','ГЕОІНТ','МОНІТОРИНГ'].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
            onChanged: (val) => setDialogState(() => selectedCat = val!),
            decoration: const InputDecoration(labelText: 'КАТЕГОРІЯ'),
          ),
          TextField(controller: tCtrl, decoration: const InputDecoration(labelText: 'НАЗВА')),
          TextField(controller: cCtrl, maxLines: 4, decoration: const InputDecoration(labelText: 'КОНТЕНТ {VAR}')),
        ]),
        actions: [
          if (p != null) TextButton(onPressed: () { setState(() => prompts.remove(p)); _save(); Navigator.pop(ctx); }, child: const Text('ВИДАЛИТИ', style: TextStyle(color: Colors.red))),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('СКАСУВАТИ')),
          ElevatedButton(onPressed: () {
            setState(() {
              if (p == null) prompts.add(Prompt(id: DateTime.now().toString(), title: tCtrl.text, content: cCtrl.text, category: selectedCat));
              else { p.title = tCtrl.text; p.content = cCtrl.text; p.category = selectedCat; }
            });
            _save(); Navigator.pop(ctx);
          }, child: const Text('ЗБЕРЕГТИ'))
        ],
      )
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('UKR_OSINT', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2)),
        actions: [
          IconButton(icon: Icon(Icons.analytics, color: uaYellow), onPressed: () {
             _secretCounter++;
             if (_secretCounter >= 5) {
               _logAction("SYS: Режим БАВОВНА");
               Navigator.push(context, MaterialPageRoute(builder: (_) => CottonGame(onLog: _logAction)));
             }
          }),
          IconButton(icon: const Icon(Icons.receipt_long), onPressed: _showAuditLog),
          IconButton(icon: const Icon(Icons.download), onPressed: _importFromTxt),
        ],
        bottom: TabBar(controller: _tabController, isScrollable: true, tabs: categories.map((c) => Tab(text: c)).toList()),
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF040B16), Color(0xFF040E22)], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
        child: SafeArea(
          child: TabBarView(
            controller: _tabController,
            children: categories.map((cat) {
              if (cat == 'ДОКУМЕНТИ') return _buildDocsList();
              if (cat == 'ІНСТРУМЕНТИ') return ToolsMenuScreen(onLog: _logAction);
              final items = prompts.where((p) => p.category == cat).toList();
              return ListView.builder(
                itemCount: items.length,
                itemBuilder: (ctx, i) => Card(
                  color: Colors.white.withOpacity(0.03),
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: ListTile(
                    title: Text(items[i].title, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(items[i].content, maxLines: 1, overflow: TextOverflow.ellipsis),
                    leading: Icon(items[i].isFavorite ? Icons.star : Icons.star_border, color: uaYellow),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GenScreen(p: items[i], onLog: _logAction))),
                    onLongPress: () => _addOrEditPrompt(p: items[i]),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: uaBlue,
        onPressed: () => _tabController.index == 5 ? _pickPDF() : _addOrEditPrompt(),
        child: Icon(_tabController.index == 5 ? Icons.picture_as_pdf : Icons.add),
      ),
    );
  }

  Widget _buildDocsList() {
    return ListView.builder(
      itemCount: docs.length,
      itemBuilder: (ctx, i) => ListTile(
        leading: const Icon(Icons.description),
        title: Text(docs[i].name),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PDFViewerScreen(doc: docs[i]))),
        trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => setState(() => docs.removeAt(i))),
      ),
    );
  }

  void _showAuditLog() {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF040E22),
      title: const Text('AUDIT LOG'),
      content: SizedBox(width: double.maxFinite, height: 300, child: ListView.builder(itemCount: auditLogs.length, itemBuilder: (ctx, i) => Text(auditLogs[i], style: const TextStyle(fontSize: 10, color: Colors.greenAccent)))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CLOSE'))],
    ));
  }

  void _pickPDF() async {
    FilePickerResult? r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    if (r != null) {
      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/${r.files.single.name}';
      await File(r.files.single.path!).copy(path);
      setState(() => docs.add(PDFDoc(id: DateTime.now().toString(), name: r.files.single.name, path: path)));
      _save();
    }
  }
}

// --- НОВИЙ МОДУЛЬ: SHERLOCK (Пошук за нікнеймом) ---

class SherlockScreen extends StatefulWidget {
  final Function(String) onLog;
  const SherlockScreen({super.key, required this.onLog});
  @override
  State<SherlockScreen> createState() => _SherlockScreenState();
}

class _SherlockScreenState extends State<SherlockScreen> {
  final TextEditingController _ctrl = TextEditingController();
  Map<String, String> _res = {};
  bool _loading = false;
  double _prog = 0;

  final Map<String, String> _sites = {
    'GitHub': 'https://github.com/',
    'Telegram': 'https://t.me/',
    'Instagram': 'https://www.instagram.com/',
    'Reddit': 'https://www.reddit.com/user/',
    'TikTok': 'https://www.tiktok.com/@',
    'Steam': 'https://steamcommunity.com/id/',
    'Pinterest': 'https://www.pinterest.com/',
    'Twitter': 'https://x.com/',
  };

  void _run() async {
    String nick = _ctrl.text.trim();
    if (nick.isEmpty) return;
    setState(() { _loading = true; _res.clear(); _prog = 0; });

    int i = 0;
    for (var s in _sites.entries) {
      try {
        final r = await http.get(Uri.parse('${s.value}$nick')).timeout(const Duration(seconds: 4));
        setState(() {
          _res[s.key] = (r.statusCode == 200) ? 'ЗНАЙДЕНО' : 'ВІДСУТНІЙ';
          i++; _prog = i / _sites.length;
        });
      } catch (e) {
        setState(() { _res[s.key] = 'ПОМИЛКА'; i++; });
      }
    }
    setState(() => _loading = false);
    widget.onLog("SHERLOCK: Перевірка нікнейма $nick завершена.");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF040E22),
      appBar: AppBar(title: const Text('SHERLOCK SCANNER')),
      body: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
        TextField(controller: _ctrl, decoration: const InputDecoration(labelText: 'ВВЕДІТЬ НІКНЕЙМ', filled: true, fillColor: Color(0xFF0A152F))),
        const SizedBox(height: 10),
        if (_loading) LinearProgressIndicator(value: _prog, color: Colors.yellow),
        const SizedBox(height: 10),
        ElevatedButton(style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50), backgroundColor: const Color(0xFF0057B7)), onPressed: _loading ? null : _run, child: const Text('ПОЧАТИ ПОШУК')),
        Expanded(child: ListView(children: _res.entries.map((e) => ListTile(
          title: Text(e.key), 
          subtitle: Text('${_sites[e.key]}${_ctrl.text}'),
          trailing: Text(e.value, style: TextStyle(color: e.value == 'ЗНАЙДЕНО' ? Colors.green : Colors.grey)),
          onTap: () => Share.share('${_sites[e.key]}${_ctrl.text}'),
        )).toList()))
      ])),
    );
  }
}

// --- ІНСТРУМЕНТИ ---

class ToolsMenuScreen extends StatelessWidget {
  final Function(String) onLog;
  const ToolsMenuScreen({super.key, required this.onLog});
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        _b(context, 'SHERLOCK', 'Пошук за нікнеймом', Icons.person_search, SherlockScreen(onLog: onLog)),
        _b(context, 'EXIF', 'Аналіз метаданих фото', Icons.image_search, ExifScreen(onLog: onLog)),
        _b(context, 'СКАНЕР', 'Пошук IP та Email у тексті', Icons.radar, ScannerScreen(onLog: onLog)),
        _b(context, 'DORKS', 'Google Dorks конструктор', Icons.travel_explore, DorksScreen(onLog: onLog)),
      ],
    );
  }
  Widget _b(ctx, t, s, i, scr) => Card(color: Colors.white.withOpacity(0.02), child: ListTile(leading: Icon(i, color: Colors.yellow), title: Text(t), subtitle: Text(s), onTap: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => scr))));
}

// --- ІНШІ ДОПОМІЖНІ ЕКРАНИ (EXIF, SCANNER, DORKS, GEN) ---

class ExifScreen extends StatefulWidget {
  final Function(String) onLog;
  const ExifScreen({super.key, required this.onLog});
  @override
  State<ExifScreen> createState() => _ExifScreenState();
}
class _ExifScreenState extends State<ExifScreen> {
  Map<String, dynamic> _data = {};
  void _pick() async {
    FilePickerResult? r = await FilePicker.platform.pickFiles(type: FileType.image);
    if (r != null) {
      final bytes = await File(r.files.single.path!).readAsBytes();
      final tags = await readExifFromBytes(bytes);
      setState(() => _data = tags);
      widget.onLog("EXIF: Оброблено фото ${r.files.single.name}");
    }
  }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('EXIF')), body: Column(children: [ElevatedButton(onPressed: _pick, child: const Text('ОБРАТИ ФОТО')), Expanded(child: ListView(children: _data.entries.map((e) => ListTile(title: Text(e.key), subtitle: Text(e.value.toString()))).toList()))]));
}

class ScannerScreen extends StatefulWidget {
  final Function(String) onLog;
  const ScannerScreen({super.key, required this.onLog});
  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}
class _ScannerScreenState extends State<ScannerScreen> {
  final _c = TextEditingController();
  List<String> _res = [];
  void _scan() {
    final ips = RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b').allMatches(_c.text).map((m) => "IP: ${m.group(0)}").toList();
    final emails = RegExp(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}').allMatches(_c.text).map((m) => "EMAIL: ${m.group(0)}").toList();
    setState(() => _res = [...ips, ...emails]);
    widget.onLog("SCANNER: Знайдено ${_res.length} об'єктів");
  }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('СКАНЕР')), body: Column(children: [TextField(controller: _c, maxLines: 5), ElevatedButton(onPressed: _scan, child: const Text('СКАНУВАТИ')), Expanded(child: ListView(children: _res.map((s) => ListTile(title: Text(s), onTap: () => Clipboard.setData(ClipboardData(text: s)))).toList()))]));
}

class DorksScreen extends StatefulWidget {
  final Function(String) onLog;
  const DorksScreen({super.key, required this.onLog});
  @override
  State<DorksScreen> createState() => _DorksScreenState();
}
class _DorksScreenState extends State<DorksScreen> {
  final _t = TextEditingController(); List<String> _d = [];
  void _gen() { String t = _t.text.trim(); if(t.isNotEmpty) setState(() => _d = ["site:$t ext:pdf", "site:$t inurl:admin", "site:$t \"password\" ext:txt"]); }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('GOOGLE DORKS')), body: Column(children: [TextField(controller: _t, decoration: const InputDecoration(labelText: 'Домен')), ElevatedButton(onPressed: _gen, child: const Text('ГЕНЕРУВАТИ')), Expanded(child: ListView(children: _d.map((s) => ListTile(title: Text(s), onTap: () => Clipboard.setData(ClipboardData(text: s)))).toList()))]));
}

class PDFViewerScreen extends StatelessWidget {
  final PDFDoc doc;
  const PDFViewerScreen({super.key, required this.doc});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(doc.name)), body: PDFView(filePath: doc.path));
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
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(widget.p.title)), body: Padding(padding: const EdgeInsets.all(16), child: Column(children: [..._ctrls.keys.map((k) => TextField(controller: _ctrls[k], decoration: InputDecoration(labelText: k))), const SizedBox(height: 20), ElevatedButton(onPressed: () { String t = widget.p.content; _ctrls.forEach((k,v) => t = t.replaceAll('{$k}', v.text)); setState(() => _res = t); }, child: const Text('КОМПІЛЮВАТИ')), Expanded(child: SingleChildScrollView(child: SelectableText(_res))), Row(children: [ElevatedButton(onPressed: () => Clipboard.setData(ClipboardData(text: _res)), child: const Text('COPY')), ElevatedButton(onPressed: () => Share.share(_res), child: const Text('SHARE'))])])));
}

// --- ПАСХАЛКА БАВОВНА (Спрощена) ---
class CottonGame extends StatelessWidget {
  final Function(String) onLog;
  const CottonGame({super.key, required this.onLog});
  @override
  Widget build(BuildContext context) => Scaffold(backgroundColor: Colors.black, body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    const Icon(Icons.local_fire_department, color: Colors.orange, size: 100),
    const Text('ОПЕРАЦІЯ БАВОВНА АКТИВОВАНА', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
    const SizedBox(height: 20),
    ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('BACK TO BASE'))
  ])));
}
