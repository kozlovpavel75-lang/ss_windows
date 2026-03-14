import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:exif/exif.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'dart:async';
import 'dart:math';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
        inputDecorationTheme: InputDecorationTheme(
          filled: true, fillColor: const Color(0xFF0A152F),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

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
      if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainScreen()));
    });
  }
  @override
  Widget build(BuildContext context) => Scaffold(backgroundColor: Colors.black, body: Image.asset('assets/splash.png', fit: BoxFit.cover, width: double.infinity, height: double.infinity));
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
  int _secretCounter = 0;

  final List<String> categories = ['ФО', 'ЮО', 'ГЕОІНТ', 'МОНІТОРИНГ', 'ІНСТРУМЕНТИ', 'ДОКУМЕНТИ'];
  final Color uaBlue = const Color(0xFF0057B7);
  final Color uaYellow = const Color(0xFFFFD700);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: categories.length, vsync: this);
    _loadData();
  }

  void _logAction(String action) {
    final now = DateTime.now();
    final timeStr = "${now.day.toString().padLeft(2,'0')}.${now.month.toString().padLeft(2,'0')} ${now.hour}:${now.minute}";
    setState(() { auditLogs.insert(0, "[$timeStr] $action"); });
    _save();
  }

  void _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final pStr = prefs.getString('prompts_data');
    final dStr = prefs.getString('docs_data');
    setState(() {
      if (pStr != null) prompts = (json.decode(pStr) as List).map((i) => Prompt.fromJson(i)).toList();
      if (dStr != null) docs = (json.decode(dStr) as List).map((i) => PDFDoc.fromJson(i)).toList();
      if (prompts.isEmpty) prompts = [Prompt(id: '1', title: 'Пошук ФО', category: 'ФО', content: 'Аналіз: {ПІБ}')];
    });
  }

  void _save() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('prompts_data', json.encode(prompts.map((p) => p.toJson()).toList()));
    prefs.setString('docs_data', json.encode(docs.map((d) => d.toJson()).toList()));
    prefs.setStringList('audit_logs', auditLogs);
  }

  void _showSysInfo() {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF040E22),
      title: const Text('SYS.INFO', style: TextStyle(fontFamily: 'monospace')),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        _iRow('ЗАПИСІВ:', prompts.length.toString()),
        _iRow('ДОКУМЕНТІВ:', docs.length.toString()),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
    ));
  }

  Widget _iRow(String l, String v) => Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(l), Text(v, style: TextStyle(color: uaYellow))]);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('UKR_OSINT'),
        actions: [
          IconButton(icon: Icon(Icons.analytics, color: uaYellow), onPressed: () {
            _showSysInfo();
            if (++_secretCounter >= 5) Navigator.push(context, MaterialPageRoute(builder: (_) => CottonGame(onLog: _logAction)));
          }),
          IconButton(icon: const Icon(Icons.download), onPressed: () {}),
        ],
        bottom: TabBar(controller: _tabController, isScrollable: true, tabs: categories.map((c) => Tab(text: c)).toList()),
      ),
      body: TabBarView(
        controller: _tabController,
        children: categories.map((cat) {
          if (cat == 'ІНСТРУМЕНТИ') return ToolsMenuScreen(onLog: _logAction);
          if (cat == 'ДОКУМЕНТИ') return _buildDocs();
          final items = prompts.where((p) => p.category == cat).toList();
          return ListView.builder(itemCount: items.length, itemBuilder: (ctx, i) => Card(
            margin: const EdgeInsets.all(8), color: Colors.white10,
            child: ListTile(title: Text(items[i].title), subtitle: Text(items[i].content), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GenScreen(p: items[i], onLog: _logAction)))),
          ));
        }).toList(),
      ),
    );
  }

  Widget _buildDocs() => ListView.builder(itemCount: docs.length, itemBuilder: (ctx, i) => ListTile(title: Text(docs[i].name), leading: const Icon(Icons.file_copy), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PDFViewerScreen(doc: docs[i])))));
  
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

// --- НОВИЙ ОФЛАЙН ГЕНЕРАТОР НІКНЕЙМІВ ---
class NicknameGenScreen extends StatefulWidget {
  final Function(String) onLog;
  const NicknameGenScreen({super.key, required this.onLog});
  @override
  State<NicknameGenScreen> createState() => _NicknameGenScreenState();
}

class _NicknameGenScreenState extends State<NicknameGenScreen> {
  final _c = TextEditingController();
  List<String> _res = [];

  void _generate() {
    String s = _c.text.trim().toLowerCase();
    if (s.isEmpty) return;
    setState(() {
      _res = [
        "$s", "${s}_osint", "${s}.private", "the_$s", "real_$s", "${s}_2026",
        "$s.ua", "$s.dev", "$s.sec", "${s}_archive",
        "$s@gmail.com", "$s@proton.me", "$s@ukr.net", "$s.osint@mail.com"
      ];
    });
    widget.onLog("Генерація варіантів для: $s");
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('ВАРІАНТИ НІКНЕЙМУ')),
    body: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
      TextField(controller: _c, decoration: const InputDecoration(labelText: 'ОСНОВНЕ СЛОВО / НІК')),
      const SizedBox(height: 10),
      ElevatedButton(onPressed: _generate, style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)), child: const Text('ГЕНЕРУВАТИ ОФЛАЙН')),
      Expanded(child: ListView.builder(itemCount: _res.length, itemBuilder: (ctx, i) => ListTile(
        title: Text(_res[i]), 
        trailing: const Icon(Icons.copy, size: 18), 
        onTap: () { Clipboard.setData(ClipboardData(text: _res[i])); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Скопійовано'))); },
      )))
    ])),
  );
}

class ToolsMenuScreen extends StatelessWidget {
  final Function(String) onLog;
  const ToolsMenuScreen({super.key, required this.onLog});
  @override
  Widget build(BuildContext context) => ListView(children: [
    _t(context, 'ВАРІАНТИ НІКНЕЙМУ', 'Офлайн генерація логінів/пошт', Icons.psychology, NicknameGenScreen(onLog: onLog)),
    _t(context, 'DORKS', 'Google пошук (відкриває в браузері)', Icons.travel_explore, DorksScreen(onLog: onLog)),
    _t(context, 'СКАНЕР', 'Екстракція даних з тексту', Icons.radar, ScannerScreen(onLog: onLog)),
  ]);
  Widget _t(ctx, t, s, i, scr) => ListTile(leading: Icon(i, color: Colors.yellow), title: Text(t), subtitle: Text(s), onTap: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => scr)));
}

class DorksScreen extends StatefulWidget {
  final Function(String) onLog;
  const DorksScreen({super.key, required this.onLog});
  @override
  State<DorksScreen> createState() => _DorksScreenState();
}

class _DorksScreenState extends State<DorksScreen> {
  final _t = TextEditingController();
  List<String> _d = [];
  void _gen() {
    String s = _t.text.trim();
    if (s.isEmpty) return;
    setState(() => _d = ["site:$s ext:pdf", "site:$s inurl:admin", "site:$s \"password\" ext:txt", "site:$s intitle:\"index of\""]);
    widget.onLog("Dorks для: $s");
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('GOOGLE DORKS')),
    body: Column(children: [
      Padding(padding: const EdgeInsets.all(16), child: TextField(controller: _t, decoration: const InputDecoration(labelText: 'Домен'))),
      ElevatedButton(onPressed: _gen, child: const Text('ГЕНЕРУВАТИ')),
      Expanded(child: ListView.builder(itemCount: _d.length, itemBuilder: (ctx, i) => ListTile(
        title: Text(_d[i]), subtitle: const Text('Натисніть щоб шукати в Google'),
        onTap: () async {
          final url = Uri.parse('https://www.google.com/search?q=${Uri.encodeComponent(_d[i])}');
          if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
          Clipboard.setData(ClipboardData(text: _d[i]));
        },
      )))
    ]),
  );
}

class ScannerScreen extends StatefulWidget {
  final Function(String) onLog;
  const ScannerScreen({super.key, required this.onLog});
  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}
class _ScannerScreenState extends State<ScannerScreen> {
  final _c = TextEditingController(); List<String> _r = [];
  void _scan() {
    final ips = RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b').allMatches(_c.text).map((m) => "IP: ${m.group(0)}").toList();
    final ems = RegExp(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}').allMatches(_c.text).map((m) => "EMAIL: ${m.group(0)}").toList();
    setState(() => _r = [...ips, ...ems]);
  }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('СКАНЕР')), body: Column(children: [TextField(controller: _c, maxLines: 5), ElevatedButton(onPressed: _scan, child: const Text('СКАНУВАТИ')), Expanded(child: ListView(itemCount: _r.length, itemBuilder: (ctx, i) => ListTile(title: Text(_r[i]))))]));
}

class PDFViewerScreen extends StatelessWidget {
  final PDFDoc doc;
  const PDFViewerScreen({super.key, required this.doc});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(doc.name)), body: PDFView(filePath: doc.path));
}

class GenScreen extends StatelessWidget {
  final Prompt p; final Function(String) onLog;
  const GenScreen({super.key, required this.p, required this.onLog});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(p.title)), body: Center(child: SelectableText(p.content)));
}

class CottonGame extends StatelessWidget {
  final Function(String) onLog;
  const CottonGame({super.key, required this.onLog});
  @override
  Widget build(BuildContext context) => Scaffold(backgroundColor: Colors.black, body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    const Icon(Icons.local_fire_department, color: Colors.orange, size: 100),
    const Text('РЕЖИМ БАВОВНА АКТИВОВАНО', style: TextStyle(fontWeight: FontWeight.bold)),
    ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('BACK'))
  ])));
}
