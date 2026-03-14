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
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarColor: Colors.transparent));
  runApp(const PromptApp());
}

class Prompt {
  String id, title, content, category;
  Prompt({required this.id, required this.title, required this.content, required this.category});
  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'content': content, 'category': category};
  factory Prompt.fromJson(Map<String, dynamic> json) => Prompt(id: json['id'], title: json['title'], content: json['content'], category: json['category']);
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

// --- ЗАСТАВКА ---
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
  }

  void _showSysInfo() {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF040E22),
      shape: RoundedRectangleBorder(side: BorderSide(color: uaYellow)),
      title: const Text('SYS.INFO'),
      content: Text('ЗАПИСІВ: ${prompts.length}\nДОКУМЕНТІВ: ${docs.length}'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text('OK', style: TextStyle(color: uaYellow)))],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('UKR_OSINT'),
        actions: [
          IconButton(icon: Icon(Icons.analytics, color: uaYellow), onPressed: () {
            _showSysInfo();
            if (++_secretCounter >= 5) Navigator.push(context, MaterialPageRoute(builder: (_) => const CottonGame()));
          }),
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

  Widget _buildDocs() => ListView.builder(itemCount: docs.length, itemBuilder: (ctx, i) => ListTile(title: Text(docs[i].name), leading: const Icon(Icons.file_copy)));
}

// --- ВИПРАВЛЕНИЙ DORKS SCREEN З АНІМАЦІЄЮ ---
class DorksScreen extends StatefulWidget {
  const DorksScreen({super.key});
  @override
  State<DorksScreen> createState() => _DorksScreenState();
}

class _DorksScreenState extends State<DorksScreen> {
  final _t = TextEditingController();
  List<String> _d = [];
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();

  void _gen() {
    String s = _t.text.trim();
    if (s.isEmpty) return;
    
    for (var i = 0; i < _d.length; i++) {
       _listKey.currentState?.removeItem(0, (ctx, anim) => const SizedBox());
    }

    setState(() {
      _d = [
        "site:$s ext:pdf",
        "site:$s inurl:admin",
        "site:$s \"password\" ext:txt",
        "site:$s intitle:\"index of\"",
        "site:$s \"login\" | \"account\"",
        "site:pastebin.com \"$s\""
      ];
    });

    Future.delayed(const Duration(milliseconds: 50), () {
      for (var i = 0; i < _d.length; i++) {
        _listKey.currentState?.insertItem(i, duration: Duration(milliseconds: 300 + (i * 100)));
      }
    });
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('GOOGLE DORKS')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(controller: _t, decoration: const InputDecoration(labelText: 'ВВЕДІТЬ ДОМЕН ТА ТИСНІТЬ ENTER')),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFD700), foregroundColor: Colors.black),
          onPressed: _gen, child: const Text('ГЕНЕРУВАТИ МАСИВ', style: TextStyle(fontWeight: FontWeight.bold))
        ),
        const SizedBox(height: 10),
        Expanded(
          child: AnimatedList(
            key: _listKey,
            initialItemCount: _d.length,
            itemBuilder: (context, index, animation) {
              return SlideTransition(
                position: animation.drive(Tween(begin: const Offset(1, 0), end: Offset.zero).chain(CurveTween(curve: Curves.easeOutQuart))),
                child: FadeTransition(
                  opacity: animation,
                  child: Card(
                    color: Colors.white.withOpacity(0.05),
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: ListTile(
                      title: Text(_d[index], style: const TextStyle(fontFamily: 'monospace', color: Colors.greenAccent)),
                      trailing: const Icon(Icons.copy, color: Colors.white24),
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: _d[index]));
                        HapticFeedback.mediumImpact();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(backgroundColor: const Color(0xFF0057B7), content: Text('СКОПІЙОВАНО: ${_d[index]}'), duration: const Duration(seconds: 1))
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        )
      ]),
    );
  }
}

// --- ВАРІАНТИ НІКНЕЙМУ ---
class NicknameGenScreen extends StatefulWidget {
  const NicknameGenScreen({super.key});
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
      _res = ["$s", "${s}_osint", "${s}_private", "the_$s", "real_$s", "$s@proton.me", "$s@ukr.net"];
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('ВАРІАНТИ НІКНЕЙМУ')),
    body: Column(children: [
      Padding(padding: const EdgeInsets.all(16), child: TextField(controller: _c, decoration: const InputDecoration(labelText: 'СЛОВО'))),
      ElevatedButton(onPressed: _generate, child: const Text('ГЕНЕРУВАТИ')),
      Expanded(child: ListView.builder(itemCount: _res.length, itemBuilder: (ctx, i) => ListTile(title: Text(_res[i]), onTap: () {
        Clipboard.setData(ClipboardData(text: _res[i]));
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Скопійовано')));
      })))
    ]),
  );
}

// --- ІНСТРУМЕНТИ ---
class ToolsMenuScreen extends StatelessWidget {
  final Function(String) onLog;
  const ToolsMenuScreen({super.key, required this.onLog});
  @override
  Widget build(BuildContext context) => ListView(children: [
    _t(context, 'ВАРІАНТИ НІКНЕЙМУ', 'Генерація офлайн', Icons.psychology, const NicknameGenScreen()),
    _t(context, 'DORKS', 'Кібер-конструктор (тільки копіювання)', Icons.travel_explore, const DorksScreen()),
    _t(context, 'СКАНЕР', 'Екстракція даних', Icons.radar, const ScannerScreen()),
  ]);
  Widget _t(ctx, t, s, i, scr) => ListTile(leading: Icon(i, color: Colors.yellow), title: Text(t), subtitle: Text(s), onTap: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => scr)));
}

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});
  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}
class _ScannerScreenState extends State<ScannerScreen> {
  final _c = TextEditingController(); List<String> _r = [];
  void _scan() {
    final ips = RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b').allMatches(_c.text).map((m) => "IP: ${m.group(0)}").toList();
    setState(() => _r = ips);
  }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('СКАНЕР')), body: Column(children: [Padding(padding: const EdgeInsets.all(16), child: TextField(controller: _c, maxLines: 5)), ElevatedButton(onPressed: _scan, child: const Text('СКАНУВАТИ')), Expanded(child: ListView.builder(itemCount: _r.length, itemBuilder: (ctx, i) => ListTile(title: Text(_r[i]))))]));
}

class CottonGame extends StatelessWidget {
  const CottonGame({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(backgroundColor: Colors.black, body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.local_fire_department, size: 100, color: Colors.orange), const Text('БАВОВНА!'), ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('BACK'))])));
}

class PDFViewerScreen extends StatelessWidget {
  final PDFDoc doc;
  const PDFViewerScreen({super.key, required this.doc});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(doc.name)), body: PDFView(filePath: doc.path));
}

// --- ПРАВИЛЬНИЙ, ВІДНОВЛЕНИЙ GEN SCREEN ---
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
    for (var m in reg.allMatches(widget.p.content)) {
      _ctrls[m.group(1)!] = TextEditingController();
    }
  }
  
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.p.title)),
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        ..._ctrls.keys.map((k) => Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: TextField(controller: _ctrls[k], decoration: InputDecoration(labelText: k)),
        )),
        const SizedBox(height: 10),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0057B7), minimumSize: const Size(double.infinity, 50)),
          onPressed: () {
            String t = widget.p.content;
            _ctrls.forEach((k,v) => t = t.replaceAll('{$k}', v.text));
            setState(() => _res = t);
            widget.onLog("Згенеровано: ${widget.p.title}");
          },
          child: const Text('КОМПІЛЮВАТИ', style: TextStyle(color: Colors.white))
        ),
        const SizedBox(height: 10),
        Expanded(child: SingleChildScrollView(child: SelectableText(_res, style: const TextStyle(fontFamily: 'monospace')))),
        Row(children: [
          Expanded(child: ElevatedButton(onPressed: () {
            Clipboard.setData(ClipboardData(text: _res));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Скопійовано')));
          }, child: const Text('COPY'))),
          const SizedBox(width: 10),
          Expanded(child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFD700)),
            onPressed: () => Share.share(_res),
            child: const Text('SHARE', style: TextStyle(color: Colors.black))
          ))
        ])
      ])
    )
  );
}
