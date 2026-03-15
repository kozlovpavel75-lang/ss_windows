import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:exif/exif.dart';
import 'package:archive/archive.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'dart:async';
import 'dart:math' as math;

ValueNotifier<bool> isMatrixMode = ValueNotifier(false);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarColor: Colors.transparent));
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

class PromptEnhancer {
  String name, desc, pros, cons, recommendation, payload;
  bool isSelected;
  PromptEnhancer({required this.name, required this.desc, required this.pros, required this.cons, required this.recommendation, required this.payload, this.isSelected = false});
}

// --- ВІЗУАЛЬНІ ЕФЕКТИ ---
class ScrambleText extends StatefulWidget {
  final String text;
  final TextStyle style;
  const ScrambleText({super.key, required this.text, required this.style});
  @override State<ScrambleText> createState() => _ScrambleTextState();
}
class _ScrambleTextState extends State<ScrambleText> {
  String _display = ""; Timer? _timer;
  @override void initState() {
    super.initState();
    int frame = 0;
    _timer = Timer.periodic(const Duration(milliseconds: 30), (t) {
      if (!mounted) return;
      setState(() {
        frame++; _display = "";
        for (int i = 0; i < widget.text.length; i++) {
          if (frame > i + 3) _display += widget.text[i];
          else _display += "X#&@?"[math.Random().nextInt(5)];
        }
        if (frame > widget.text.length + 10) t.cancel();
      });
    });
  }
  @override void dispose() { _timer?.cancel(); super.dispose(); }
  @override Widget build(BuildContext context) => Text(_display, style: widget.style);
}

// --- ГОЛОВНИЙ ДОДАТОК ---
class PromptApp extends StatelessWidget {
  const PromptApp({super.key});
  @override Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isMatrixMode,
      builder: (context, matrix, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: matrix ? Colors.black : const Color(0xFF040E22),
          primaryColor: matrix ? Colors.greenAccent : const Color(0xFF0057B7),
          fontFamily: 'monospace',
        ),
        home: const SplashScreen(),
      ),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override State<SplashScreen> createState() => _SplashScreenState();
}
class _SplashScreenState extends State<SplashScreen> {
  @override void initState() { super.initState(); Timer(const Duration(milliseconds: 1800), () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainScreen()))); }
  @override Widget build(BuildContext context) => Scaffold(backgroundColor: Colors.black, body: Container(width: double.infinity, height: double.infinity, decoration: const BoxDecoration(image: DecorationImage(image: AssetImage('assets/splash.png'), fit: BoxFit.cover))));
}

// --- MAIN SCREEN ---
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override State<MainScreen> createState() => _MainScreenState();
}
class _MainScreenState extends State<MainScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Prompt> prompts = [];
  List<PDFDoc> docs = [];
  List<String> auditLogs = [];
  int _matrixTaps = 0;
  final List<String> categories = ['ФО', 'ЮО', 'ГЕОІНТ', 'МОНІТОРИНГ', 'ІНСТРУМЕНТИ', 'ДОКУМЕНТИ'];

  @override void initState() { super.initState(); _tabController = TabController(length: categories.length, vsync: this); _loadData(); }

  void _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final pStr = prefs.getString('prompts_data');
    final dStr = prefs.getString('docs_data');
    final logs = prefs.getStringList('audit_logs');
    setState(() {
      if (pStr != null) prompts = (json.decode(pStr) as List).map((i) => Prompt.fromJson(i)).toList();
      if (dStr != null) docs = (json.decode(dStr) as List).map((i) => PDFDoc.fromJson(i)).toList();
      if (logs != null) auditLogs = logs;
      if (prompts.isEmpty) prompts = [Prompt(id: '1', title: 'ПОШУК ПЕРСОНИ', category: 'ФО', content: 'Дані: {ПІБ}', isFavorite: true)];
    });
  }
  void _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('prompts_data', json.encode(prompts.map((p) => p.toJson()).toList()));
    await prefs.setString('docs_data', json.encode(docs.map((d) => d.toJson()).toList()));
    await prefs.setStringList('audit_logs', auditLogs);
  }
  void _log(String a) { setState(() => auditLogs.insert(0, "[${DateTime.now().hour}:${DateTime.now().minute}] $a")); _save(); }

  @override Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(onTap: () { if (++_matrixTaps >= 7) { isMatrixMode.value = !isMatrixMode.value; _matrixTaps = 0; } }, child: Text('UKR_OSINT', style: TextStyle(color: isMatrixMode.value ? Colors.greenAccent : Colors.white))),
        actions: [
          IconButton(icon: const Icon(Icons.analytics, color: Colors.yellow), onPressed: _showStats),
          IconButton(icon: const Icon(Icons.receipt_long), onPressed: _showLogs),
          IconButton(icon: const Icon(Icons.download, color: Colors.blue), onPressed: _importTxt),
        ],
        bottom: TabBar(controller: _tabController, isScrollable: true, tabs: categories.map((c) => Tab(text: c)).toList()),
      ),
      body: TabBarView(controller: _tabController, children: categories.map((cat) {
        if (cat == 'ІНСТРУМЕНТИ') return ToolsMenuScreen(onLog: _log);
        if (cat == 'ДОКУМЕНТИ') return _buildDocs();
        final items = prompts.where((p) => p.category == cat).toList();
        return ListView.builder(itemCount: items.length, itemBuilder: (ctx, i) => Card(margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), color: Colors.white.withOpacity(0.05), child: ListTile(title: Text(items[i].title), subtitle: Text(items[i].content, maxLines: 1), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GenScreen(p: items[i], onLog: _log))))));
      }).toList()),
    );
  }

  void _showStats() {
    showDialog(context: context, builder: (c) => AlertDialog(backgroundColor: Colors.black, title: const Text('STATS'), content: Text('Загалом записів: ${prompts.length}\nДокументів: ${docs.length}')));
  }
  void _showLogs() {
    showDialog(context: context, builder: (c) => AlertDialog(backgroundColor: Colors.black, title: const Text('LOGS'), content: SizedBox(width: double.maxFinite, height: 300, child: ListView.builder(itemCount: auditLogs.length, itemBuilder: (cc, i) => Text(auditLogs[i], style: const TextStyle(fontSize: 10, color: Colors.greenAccent))))));
  }
  void _importTxt() async {
    FilePickerResult? r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['txt']);
    if (r != null) {
      String content = await File(r.files.single.path!).readAsString();
      _log("Імпорт з TXT");
    }
  }
  Widget _buildDocs() => ListView.builder(itemCount: docs.length, itemBuilder: (ctx, i) => Card(margin: const EdgeInsets.all(8), child: ListTile(leading: const Icon(Icons.file_copy), title: Text(docs[i].name), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PDFViewerScreen(doc: docs[i]))))));
}

// --- TOOLS ---
class ToolsMenuScreen extends StatelessWidget {
  final Function(String) onLog;
  const ToolsMenuScreen({super.key, required this.onLog});
  @override Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(12), children: [
    _t(context, 'DORKS', Icons.travel_explore, DorksScreen(onLog: onLog)),
    _t(context, 'SCANNER', Icons.radar, ScannerScreen(onLog: onLog)),
    _t(context, 'EXIF', Icons.image_search, ExifScreen(onLog: onLog)),
    _t(context, 'IPN', Icons.fingerprint, IpnDecoderScreen(onLog: onLog)),
    _t(context, 'FINANCE', Icons.credit_card, FinValidatorScreen(onLog: onLog)),
    _t(context, 'AUTO', Icons.directions_car, AutoModuleScreen(onLog: onLog)),
    _t(context, 'VAULT', Icons.lock, PasswordManagerScreen(onLog: onLog)),
    _t(context, 'TIMELINE', Icons.timeline, TimelineScreen(onLog: onLog)),
  ]);
  Widget _t(ctx, t, i, s) => Card(child: ListTile(leading: Icon(i, color: Colors.yellow), title: Text(t), onTap: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => s))));
}

// --- DORKS ---
class DorksScreen extends StatefulWidget {
  final Function(String) onLog;
  const DorksScreen({super.key, required this.onLog});
  @override State<DorksScreen> createState() => _DorksScreenState();
}
class _DorksScreenState extends State<DorksScreen> {
  final _t = TextEditingController(); List<Map<String, String>> _d = [];
  void _gen() {
    String s = _t.text.trim(); if (s.isEmpty) return;
    setState(() => _d = [
      {'t': 'DOCS', 'd': 'PDF, DOC, TXT файли', 'q': 'site:$s ext:pdf OR ext:docx OR ext:txt'},
      {'t': 'ADMIN', 'd': 'Панелі входу', 'q': 'site:$s inurl:admin OR inurl:login'},
      {'t': 'DB', 'd': 'SQL дампи', 'q': 'site:$s ext:sql OR ext:db'},
    ]);
  }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('DORKS')), body: Column(children: [
    Padding(padding: const EdgeInsets.all(16), child: TextField(controller: _t, decoration: const InputDecoration(labelText: 'ДОМЕН'))),
    ElevatedButton(onPressed: _gen, child: const Text('GENERATE')),
    Expanded(child: ListView.builder(itemCount: _d.length, itemBuilder: (c, i) => Card(child: ListTile(title: Text(_d[i]['t']!), subtitle: Text(_d[i]['d']!), trailing: IconButton(icon: const Icon(Icons.copy), onPressed: () => Clipboard.setData(ClipboardData(text: _d[i]['q']!)))))))
  ]));
}

// --- SCANNER ---
class ScannerScreen extends StatefulWidget {
  final Function(String) onLog;
  const ScannerScreen({super.key, required this.onLog});
  @override State<ScannerScreen> createState() => _ScannerScreenState();
}
class _ScannerScreenState extends State<ScannerScreen> with SingleTickerProviderStateMixin {
  final _c = TextEditingController(); List<String> _r = []; late AnimationController _l; bool _sc = false;
  @override void initState() { super.initState(); _l = AnimationController(vsync: this, duration: const Duration(seconds: 2)); }
  void _loadDoc() async {
    FilePickerResult? r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['txt', 'docx']);
    if (r != null) {
      final file = File(r.files.single.path!); String text = "";
      if (r.files.single.extension == 'docx') {
        final archive = ZipDecoder().decodeBytes(await file.readAsBytes());
        for (var f in archive) if (f.name == 'word/document.xml') text = utf8.decode(f.content).replaceAll(RegExp(r'<[^>]*>'), ' ');
      } else text = await file.readAsString();
      setState(() => _c.text = text);
    }
  }
  void _scan() async {
    setState(() { _sc = true; _r.clear(); }); _l.repeat(); await Future.delayed(const Duration(seconds: 2));
    String t = _c.text;
    _r = RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b').allMatches(t).map((m) => "IP: ${m.group(0)}").toList();
    _r.addAll(RegExp(r'(?:\+380|\+7|8)[ \-\(\)]?\d{2,3}[ \-\(\)]?\d{3}[ \-]?\d{2}[ \-]?\d{2}').allMatches(t).map((m) => "PH: ${m.group(0)}").toList());
    setState(() { _sc = false; }); _l.stop();
  }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('SCANNER'), actions: [IconButton(icon: const Icon(Icons.file_open), onPressed: _loadDoc)]), body: Column(children: [
    Stack(children: [
      Padding(padding: const EdgeInsets.all(16), child: TextField(controller: _c, maxLines: 5, decoration: const InputDecoration(labelText: 'INPUT'))),
      if (_sc) AnimatedBuilder(animation: _l, builder: (c, _) => Positioned(top: 20 + (_l.value * 120), left: 16, right: 16, child: Container(height: 2, color: Colors.red))),
    ]),
    ElevatedButton(onPressed: _scan, child: const Text('SCAN')),
    Expanded(child: ListView.builder(itemCount: _r.length, itemBuilder: (c, i) => Card(color: _r[i].contains('+7') ? Colors.red.withOpacity(0.1) : null, child: ListTile(title: Text(_r[i])))))
  ]));
}

// --- GEN SCREEN ---
class GenScreen extends StatefulWidget {
  final Prompt p; final Function(String) onLog;
  const GenScreen({super.key, required this.p, required this.onLog});
  @override State<GenScreen> createState() => _GenScreenState();
}
class _GenScreenState extends State<GenScreen> {
  final Map<String, TextEditingController> _ctrls = {}; bool _comp = false; List<TextSpan> _spans = []; int _lim = 0; Timer? _timer;
  final List<PromptEnhancer> _enh = [
    PromptEnhancer(name: 'CoT', desc: 'Покрокове мислення', pros: 'Точність, логічність', cons: 'Довша відповідь', recommendation: 'Складні аналітичні задачі', payload: 'Think step-by-step.'),
    PromptEnhancer(name: 'ToT', desc: 'Дерево думок', pros: 'Глибокий аналіз', cons: 'Висока складність', recommendation: 'Генерація гіпотез', payload: 'Generate 3 hypotheses and evaluate each.'),
    PromptEnhancer(name: 'Persona', desc: 'Експертна роль', pros: 'Професійний тон', cons: 'Можливі обмеження', recommendation: 'Профільні звіти', payload: 'Act as an OSINT expert.'),
  ];
  @override void initState() { super.initState(); final reg = RegExp(r'\{([^}]+)\}'); for (var m in reg.allMatches(widget.p.content)) _ctrls[m.group(1)!] = TextEditingController(); }
  void _compile() {
    _spans.clear(); String t = widget.p.content; int last = 0; final reg = RegExp(r'\{([^}]+)\}');
    for (var m in reg.allMatches(t)) {
      if (m.start > last) _spans.add(TextSpan(text: t.substring(last, m.start), style: const TextStyle(color: Colors.greenAccent)));
      _spans.add(TextSpan(text: _ctrls[m.group(1)!]!.text, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)));
      last = m.end;
    }
    if (last < t.length) _spans.add(TextSpan(text: t.substring(last), style: const TextStyle(color: Colors.greenAccent)));
    for (var e in _enh.where((e) => e.isSelected)) _spans.add(TextSpan(text: "\n\n[SYSTEM]: ${e.payload}", style: const TextStyle(color: Colors.yellow)));
    setState(() { _comp = true; _lim = 0; }); _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 5), (t) { setState(() { _lim += 15; if (_lim >= 2000) t.cancel(); }); });
  }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(widget.p.title)), body: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
    if (!_comp) ...[..._ctrls.keys.map((k) => TextField(controller: _ctrls[k], decoration: InputDecoration(labelText: k))), ElevatedButton(onPressed: _compile, child: const Text('COMPILE'))],
    if (_comp) ...[
      ElevatedButton(onPressed: (){
        showModalBottomSheet(context: context, builder: (c) => StatefulBuilder(builder: (cc, setM) => Container(padding: const EdgeInsets.all(16), child: Column(children: [
          const Text('ТАКТИЧНЕ ПІДСИЛЕННЯ', style: TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: ListView.builder(itemCount: _enh.length, itemBuilder: (ccc, i) => CheckboxListTile(title: Text(_enh[i].name), subtitle: Text("${_enh[i].desc}\nPROS: ${_enh[i].pros}\nCONS: ${_enh[i].cons}"), isThreeLine: true, value: _enh[i].isSelected, onChanged: (v){ setM(() => _enh[i].isSelected = v!); _compile(); }))),
        ]))));
      }, child: const Text('ENHANCE')),
      Expanded(child: Container(width: double.infinity, color: Colors.black, child: SingleChildScrollView(child: RichText(text: TextSpan(children: _getV()))))),
    ]
  ])));
  List<TextSpan> _getV() { List<TextSpan> r = []; int c = 0; for (var s in _spans) { if (c + s.text!.length <= _lim) { r.add(s); c += s.text!.length; } else { r.add(TextSpan(text: s.text!.substring(0, _lim - c), style: s.style)); break; } } return r; }
}

// --- ТЕХНІЧНІ ІНСТРУМЕНТИ ---
class ExifScreen extends StatefulWidget { final Function(String) onLog; const ExifScreen({super.key, required this.onLog}); @override State<ExifScreen> createState() => _ExifScreenState(); }
class _ExifScreenState extends State<ExifScreen> {
  Map<String, dynamic> _d = {};
  void _pick() async {
    FilePickerResult? r = await FilePicker.platform.pickFiles(type: FileType.image);
    if (r != null) { final tags = await readExifFromBytes(await File(r.files.single.path!).readAsBytes()); setState(() => _d = tags); }
  }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('EXIF')), body: Column(children: [ ElevatedButton(onPressed: _pick, child: const Text('PICK PHOTO')), Expanded(child: ListView.builder(itemCount: _d.length, itemBuilder: (c, i) => ListTile(title: Text(_d.keys.elementAt(i)), subtitle: Text(_d.values.elementAt(i).toString())))) ]));
}

class IpnDecoderScreen extends StatefulWidget { final Function(String) onLog; const IpnDecoderScreen({super.key, required this.onLog}); @override State<IpnDecoderScreen> createState() => _IpnDecoderScreenState(); }
class _IpnDecoderScreenState extends State<IpnDecoderScreen> {
  final _c = TextEditingController(); Map<String, String>? _r;
  void _dec() {
    String s = _c.text.trim(); if (s.length != 10) return;
    DateTime dob = DateTime(1899, 12, 31).add(Duration(days: int.parse(s.substring(0, 5))));
    setState(() => _r = {'ДАТА': "${dob.day}.${dob.month}.${dob.year}", 'СТАТЬ': int.parse(s[8]) % 2 == 0 ? 'Жіноча' : 'Чоловіча'});
  }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('IPN')), body: Padding(padding: const EdgeInsets.all(16), child: Column(children: [ TextField(controller: _c, decoration: const InputDecoration(labelText: '10 ЦИФР')), ElevatedButton(onPressed: _dec, child: const Text('DECODE')), if (_r != null) ..._r!.entries.map((e) => ListTile(title: Text(e.key), subtitle: ScrambleText(text: e.value, style: const TextStyle(color: Colors.greenAccent)))) ])));
}

class FinValidatorScreen extends StatefulWidget { final Function(String) onLog; const FinValidatorScreen({super.key, required this.onLog}); @override State<FinValidatorScreen> createState() => _FinValidatorScreenState(); }
class _FinValidatorScreenState extends State<FinValidatorScreen> {
  final _c = TextEditingController(); String _res = "";
  void _check() {
    String cc = _c.text.replaceAll(' ', ''); int sum = 0; bool alt = false;
    for (int i = cc.length - 1; i >= 0; i--) { int n = int.parse(cc[i]); if (alt) { n *= 2; if (n > 9) n -= 9; } sum += n; alt = !alt; }
    setState(() => _res = sum % 10 == 0 ? "ВАЛІДНА" : "НЕ КОРЕКТНА");
  }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('FINANCE')), body: Padding(padding: const EdgeInsets.all(16), child: Column(children: [ TextField(controller: _c, decoration: const InputDecoration(labelText: 'НОМЕР КАРТКИ')), ElevatedButton(onPressed: _check, child: const Text('CHECK')), Text(_res, style: const TextStyle(fontSize: 24)) ])));
}

class AutoModuleScreen extends StatefulWidget { final Function(String) onLog; const AutoModuleScreen({super.key, required this.onLog}); @override State<AutoModuleScreen> createState() => _AutoModuleScreenState(); }
class _AutoModuleScreenState extends State<AutoModuleScreen> {
  final _c = TextEditingController(); String _r = "";
  void _check() { String s = _c.text.toUpperCase(); if (s.startsWith('AA') || s.startsWith('KA')) setState(() => _r = "КИЇВ"); else setState(() => _r = "ІНШИЙ РЕГІОН"); }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('AUTO')), body: Padding(padding: const EdgeInsets.all(16), child: Column(children: [ TextField(controller: _c, decoration: const InputDecoration(labelText: 'НОМЕР')), ElevatedButton(onPressed: _check, child: const Text('CHECK')), Text(_r, style: const TextStyle(fontSize: 24)) ])));
}

class TimelineScreen extends StatefulWidget { final Function(String) onLog; const TimelineScreen({super.key, required this.onLog}); @override State<TimelineScreen> createState() => _TimelineScreenState(); }
class _TimelineScreenState extends State<TimelineScreen> {
  List<Map<String, String>> _e = [];
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('TIMELINE')), body: ListView.builder(itemCount: _e.length, itemBuilder: (c, i) => ListTile(title: Text(_e[i]['t']!))), floatingActionButton: FloatingActionButton(onPressed: () => setState(() => _e.add({'t': 'ПОДІЯ'})), child: const Icon(Icons.add)));
}

class PasswordManagerScreen extends StatefulWidget { final Function(String) onLog; const PasswordManagerScreen({super.key, required this.onLog}); @override State<PasswordManagerScreen> createState() => _PasswordManagerScreenState(); }
class _PasswordManagerScreenState extends State<PasswordManagerScreen> {
  List<Map<String, String>> _v = [];
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('VAULT')), body: ListView.builder(itemCount: _v.length, itemBuilder: (c, i) => ListTile(title: Text(_v[i]['u']!), subtitle: Text(_v[i]['p']!))), floatingActionButton: FloatingActionButton(onPressed: () => setState(() => _v.add({'u': 'USER', 'p': 'PASS'})), child: const Icon(Icons.add)));
}

class PDFViewerScreen extends StatelessWidget { final PDFDoc doc; const PDFViewerScreen({super.key, required this.doc}); @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(doc.name)), body: PDFView(filePath: doc.path)); }
