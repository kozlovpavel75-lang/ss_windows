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
  String id, title, content, category; bool isFavorite;
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
  String name, desc, pros, cons, rec, payload; bool isSelected;
  PromptEnhancer({required this.name, required this.desc, required this.pros, required this.cons, required this.rec, required this.payload, this.isSelected = false});
}

// --- ВІЗУАЛ ---
class TopoGridPainter extends CustomPainter {
  final bool isGreen; TopoGridPainter(this.isGreen);
  @override void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = isGreen ? Colors.green.withOpacity(0.05) : const Color(0xFF0057B7).withOpacity(0.03)..strokeWidth = 1.0;
    for (double i = 0; i < size.width; i += 40) canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    for (double i = 0; i < size.height; i += 40) canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
      setState(() { f++; _disp = ""; for (int i = 0; i < widget.text.length; i++) { if (f > i + 3) _disp += widget.text[i]; else _disp += "X#&?@"[math.Random().nextInt(5)]; } if (f > widget.text.length + 10) t.cancel(); });
    });
  }
  @override void dispose() { _t?.cancel(); super.dispose(); }
  @override Widget build(BuildContext context) => Text(_disp, style: widget.style);
}

// --- APP ---
class PromptApp extends StatelessWidget {
  const PromptApp({super.key});
  @override Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isMatrixMode,
      builder: (ctx, matrix, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: matrix ? Colors.black : const Color(0xFF040E22),
          primaryColor: matrix ? Colors.greenAccent : const Color(0xFF0057B7),
          fontFamily: 'monospace',
          appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, elevation: 0),
          inputDecorationTheme: InputDecorationTheme(
            filled: true, fillColor: matrix ? Colors.black : const Color(0xFF0A152F),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: matrix ? const BorderSide(color: Colors.green) : BorderSide.none),
          ),
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

// --- ГОЛОВНИЙ ЕКРАН ---
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override State<MainScreen> createState() => _MainScreenState();
}
class _MainScreenState extends State<MainScreen> with SingleTickerProviderStateMixin {
  late TabController _tc;
  List<Prompt> prompts = []; List<PDFDoc> docs = []; List<String> logs = [];
  int _taps = 0;
  final List<String> cats = ['ФО', 'ЮО', 'ГЕОІНТ', 'МОНІТОРИНГ', 'ІНСТРУМЕНТИ', 'ДОКУМЕНТИ'];

  @override void initState() { super.initState(); _tc = TabController(length: cats.length, vsync: this); _tc.addListener(() { setState(() {}); }); _load(); }

  void _load() async {
    final p = await SharedPreferences.getInstance();
    final pS = p.getString('prompts'); final dS = p.getString('docs'); final lS = p.getStringList('logs');
    setState(() {
      if (pS != null) prompts = (json.decode(pS) as List).map((i) => Prompt.fromJson(i)).toList();
      if (dS != null) docs = (json.decode(dS) as List).map((i) => PDFDoc.fromJson(i)).toList();
      if (lS != null) logs = lS;
      if (prompts.isEmpty) prompts = [Prompt(id: '1', title: 'ПОШУК ПЕРСОНИ', category: 'ФО', content: 'Аналіз даних: {ПІБ}\nМісто: {Місто}', isFavorite: true)];
    });
  }

  void _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('prompts', json.encode(prompts.map((i) => i.toJson()).toList()));
    await p.setString('docs', json.encode(docs.map((i) => i.toJson()).toList()));
    await p.setStringList('logs', logs);
  }

  void _log(String a) { setState(() => logs.insert(0, "[${DateTime.now().day.toString().padLeft(2,'0')}.${DateTime.now().month.toString().padLeft(2,'0')} ${DateTime.now().hour.toString().padLeft(2,'0')}:${DateTime.now().minute.toString().padLeft(2,'0')}] $a")); _save(); }

  void _import() async {
    FilePickerResult? r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['txt']);
    if (r != null && r.files.single.path != null) {
      try {
        String c = await File(r.files.single.path!).readAsString();
        List<Prompt> imp = [];
        for (var b in c.split('===')) {
          if (b.trim().isEmpty) continue;
          String cat = 'МОНІТОРИНГ', title = 'БЕЗ НАЗВИ', text = ''; bool isT = false;
          for (var l in b.trim().split('\n')) {
            String lw = l.toLowerCase().trim();
            if (lw.startsWith('категорія:')) {
              String rawCat = l.substring(10).trim().toUpperCase();
              if (rawCat.contains('ФІЗ') || rawCat == 'ФО') cat = 'ФО';
              else if (rawCat.contains('ЮР') || rawCat == 'ЮО') cat = 'ЮО';
              else if (rawCat.contains('ГЕО')) cat = 'ГЕОІНТ';
              else cat = 'МОНІТОРИНГ';
            }
            else if (lw.startsWith('назва:')) title = l.substring(6).trim();
            else if (lw.startsWith('текст:')) { text = l.substring(6).trim(); isT = true; }
            else if (isT) text += "\n$l";
          }
          if (text.isNotEmpty && title.isNotEmpty) imp.add(Prompt(id: DateTime.now().millisecondsSinceEpoch.toString() + title, title: title, content: text.trim(), category: cat));
        }
        setState(() => prompts.addAll(imp)); 
        _log("Імпортовано: ${imp.length} записів з TXT"); 
        _save();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Успішно імпортовано ${imp.length} промптів', style: const TextStyle(color: Colors.greenAccent)), backgroundColor: const Color(0xFF040E22)));
      } catch(e) {
        _log("Помилка імпорту TXT");
      }
    }
  }

  void _addP({Prompt? p}) {
    final tC = TextEditingController(text: p?.title ?? ''); final cC = TextEditingController(text: p?.content ?? '');
    String sC = p?.category ?? 'ФО';
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (c, setS) => AlertDialog(
      backgroundColor: const Color(0xFF0A152F), title: Text(p == null ? 'НОВИЙ ЗАПИС' : 'РЕДАГУВАННЯ'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(dropdownColor: const Color(0xFF0A152F), isExpanded: true, value: sC, items: ['ФО','ЮО','ГЕОІНТ','МОНІТОРИНГ'].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(), onChanged: (v) => setS(() => sC = v!)),
        const SizedBox(height: 10), TextField(controller: tC, decoration: const InputDecoration(labelText: 'НАЗВА')),
        const SizedBox(height: 10), TextField(controller: cC, maxLines: 4, decoration: const InputDecoration(labelText: 'ЗМІСТ {VAR}')),
      ]),
      actions: [
        if (p != null) TextButton(onPressed: () async { 
          Navigator.pop(ctx);
          setState(() { p.title = "█████████"; p.content = "████████████████"; });
          HapticFeedback.heavyImpact(); await Future.delayed(const Duration(milliseconds: 600));
          setState(() => prompts.remove(p)); _save(); 
        }, child: const Text('ВИДАЛИТИ', style: TextStyle(color: Colors.red))),
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('СКАСУВАТИ')),
        ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0057B7)), onPressed: () {
          setState(() { if (p == null) prompts.add(Prompt(id: DateTime.now().toString(), title: tC.text, content: cC.text, category: sC)); else { p.title = tC.text; p.content = cC.text; p.category = sC; } });
          _save(); Navigator.pop(ctx);
        }, child: const Text('ЗБЕРЕГТИ', style: TextStyle(color: Colors.white)))
      ],
    )));
  }

  void _pickPDF() async {
    FilePickerResult? r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    if (r != null && r.files.single.path != null) {
      final dir = await getApplicationDocumentsDirectory(); final path = '${dir.path}/${r.files.single.name}';
      await File(r.files.single.path!).copy(path);
      setState(() => docs.add(PDFDoc(id: DateTime.now().toString(), name: r.files.single.name, path: path))); _save();
    }
  }

  @override Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(onTap: () { if (++_taps >= 7) { isMatrixMode.value = !isMatrixMode.value; _taps = 0; HapticFeedback.vibrate(); } }, child: Text('UKR_OSINT', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2, color: isMatrixMode.value ? Colors.greenAccent : Colors.white))),
        actions: [
          IconButton(icon: const Icon(Icons.analytics, color: Colors.yellow), onPressed: () {
            Map<String, int> s = {'ФО': 0, 'ЮО': 0, 'ГЕОІНТ': 0, 'МОНІТОРИНГ': 0}; int tot = prompts.length;
            for (var p in prompts) if (s.containsKey(p.category)) s[p.category] = s[p.category]! + 1;
            showDialog(context: context, builder: (c) => AlertDialog(backgroundColor: const Color(0xFF040E22), title: const Text('СТАТИСТИКА БАЗИ'), content: Column(mainAxisSize: MainAxisSize.min, children: s.entries.map((e) => Column(children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(e.key), Text('${e.value}')]), const SizedBox(height: 4), LinearProgressIndicator(value: tot == 0 ? 0 : e.value / tot, color: Colors.blue), const SizedBox(height: 8)])).toList())));
          }),
          IconButton(icon: const Icon(Icons.receipt_long), onPressed: () => showDialog(context: context, builder: (c) => AlertDialog(backgroundColor: Colors.black, title: const Text('ЖУРНАЛ ДІЙ'), content: SizedBox(width: double.maxFinite, height: 300, child: logs.isEmpty ? const Center(child: Text('НЕМАЄ ЗАПИСІВ')) : ListView.builder(itemCount: logs.length, itemBuilder: (cc, i) => Text(logs[i], style: const TextStyle(fontSize: 10, color: Colors.greenAccent))))))),
          IconButton(icon: const Icon(Icons.download, color: Colors.blue), onPressed: _import),
        ],
        bottom: TabBar(controller: _tc, isScrollable: true, tabs: cats.map((c) => Tab(text: c)).toList()),
      ),
      body: Stack(children: [
        CustomPaint(painter: TopoGridPainter(isMatrixMode.value), child: Container()),
        TabBarView(controller: _tc, children: cats.map((cat) {
          if (cat == 'ІНСТРУМЕНТИ') return ToolsMenu(onLog: _log);
          if (cat == 'ДОКУМЕНТИ') return docs.isEmpty ? const Center(child: Text('[ ФАЙЛІВ НЕМАЄ ]', style: TextStyle(color: Colors.white24))) : ListView.builder(itemCount: docs.length, itemBuilder: (c, i) => Card(margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), color: Colors.white.withOpacity(0.05), child: ListTile(leading: const Icon(Icons.picture_as_pdf), title: Text(docs[i].name), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PDFViewerScreen(doc: docs[i]))), trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () { setState(() => docs.removeAt(i)); _save(); }))));
          final items = prompts.where((p) => p.category == cat).toList();
          if (items.isEmpty) return const Center(child: Text('[ ПУСТО ]', style: TextStyle(color: Colors.white24)));
          items.sort((a, b) => (b.isFavorite ? 1 : 0).compareTo(a.isFavorite ? 1 : 0));
          return ListView.builder(itemCount: items.length, itemBuilder: (ctx, i) => Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), color: Colors.white.withOpacity(0.05),
            child: ListTile(
              leading: IconButton(icon: Icon(items[i].isFavorite ? Icons.star : Icons.star_border, color: items[i].isFavorite ? Colors.yellow : Colors.white24), onPressed: () { setState(() => items[i].isFavorite = !items[i].isFavorite); _save(); }),
              title: Text(items[i].title, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(items[i].content, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GenScreen(p: items[i], onLog: _log))),
              onLongPress: () => _addP(p: items[i]),
            ),
          ));
        }).toList()),
      ]),
      floatingActionButton: _tc.index == 4 ? null : FloatingActionButton(backgroundColor: const Color(0xFF0057B7), onPressed: () => _tc.index == 5 ? _pickPDF() : _addP(), child: Icon(_tc.index == 5 ? Icons.picture_as_pdf : Icons.add, color: Colors.white)),
    );
  }
}
// --- МЕНЮ ІНСТРУМЕНТІВ ---
class ToolsMenu extends StatelessWidget {
  final Function(String) onLog; const ToolsMenu({super.key, required this.onLog});
  @override Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(12), children: [
    _t(context, 'DORKS', 'Google Конструктор', Icons.travel_explore, DorksScreen(onLog: onLog)),
    _t(context, 'СКАНЕР', 'Екстракція (IP/Телефон/Email)', Icons.radar, ScannerScreen(onLog: onLog)),
    _t(context, 'EXIF', 'Аналіз метаданих фото', Icons.image_search, ExifScreen(onLog: onLog)),
    _t(context, 'ІПН', 'Дешифратор РНОКПП', Icons.fingerprint, IpnScreen(onLog: onLog)),
    _t(context, 'ФІНАНСИ', 'Перевірка карток (Луна)', Icons.credit_card, FinScreen(onLog: onLog)),
    _t(context, 'АВТО', 'Регіони України', Icons.directions_car, AutoScreen(onLog: onLog)),
    _t(context, 'НІКНЕЙМИ', 'Генератор', Icons.psychology, NickScreen(onLog: onLog)),
    _t(context, 'ХРОНОЛОГІЯ', 'Таймлайн подій', Icons.timeline, TimeScreen(onLog: onLog)),
    _t(context, 'СЕЙФ', 'Захищений менеджер паролів', Icons.lock, VaultScreen(onLog: onLog)),
  ]);
  Widget _t(ctx, t, s, i, sc) => Card(color: Colors.white.withOpacity(0.03), child: ListTile(leading: Icon(i, color: Colors.yellow), title: Text(t, style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text(s, style: const TextStyle(fontSize: 10)), onTap: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => sc))));
}

// --- DORKS ---
class DorksScreen extends StatefulWidget {
  final Function(String) onLog; const DorksScreen({super.key, required this.onLog});
  @override State<DorksScreen> createState() => _DorksScreenState();
}
class _DorksScreenState extends State<DorksScreen> {
  final _t = TextEditingController(); List<Map<String, String>> _d = [];
  void _gen() {
    String s = _t.text.trim(); if (s.isEmpty) return;
    setState(() => _d = [
      {'t': 'ДОКУМЕНТИ', 'd': 'Пошук документів на сайті', 'q': 'site:$s ext:pdf OR ext:docx OR ext:txt OR ext:csv'},
      {'t': 'БАЗИ ДАНИХ', 'd': 'Дампи баз даних', 'q': 'site:$s ext:sql OR ext:db OR ext:bak OR ext:dump'},
      {'t': 'КОНФІГИ', 'd': 'Файли конфігурацій', 'q': 'site:$s ext:env OR ext:conf OR ext:ini OR ext:xml'},
      {'t': 'КАМЕРИ', 'd': 'Відкриті веб-камери', 'q': 'site:$s inurl:view/view.shtml OR inurl:axis-cgi/jpg'},
      {'t': 'АДМІН-ПАНЕЛІ', 'd': 'Панелі авторизації', 'q': 'site:$s inurl:admin OR inurl:login OR inurl:wp-admin'},
      {'t': 'ПАРОЛІ', 'd': 'Логи з паролями', 'q': 'site:$s "password" ext:txt OR ext:log'}
    ]); widget.onLog("Dorks: згенеровано для $s");
  }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('КОНСТРУКТОР DORKS')), body: Column(children: [ Padding(padding: const EdgeInsets.all(16), child: TextField(controller: _t, decoration: const InputDecoration(labelText: 'ЦІЛЬОВИЙ ДОМЕН (напр. example.com)'))), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0057B7)), onPressed: _gen, child: const Text('ЗГЕНЕРУВАТИ', style: TextStyle(color: Colors.white))), Expanded(child: ListView.builder(itemCount: _d.length, itemBuilder: (c, i) => Card(margin: const EdgeInsets.all(8), color: Colors.white.withOpacity(0.05), child: ListTile(title: Text(_d[i]['t']!, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.greenAccent)), subtitle: Text("${_d[i]['d']!}\n\n${_d[i]['q']!}"), isThreeLine: true, trailing: IconButton(icon: const Icon(Icons.copy), onPressed: () { Clipboard.setData(ClipboardData(text: _d[i]['q']!)); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Скопійовано!'))); } ))))) ]));
}

// --- СКАНЕР ---
class ScannerScreen extends StatefulWidget {
  final Function(String) onLog; const ScannerScreen({super.key, required this.onLog});
  @override State<ScannerScreen> createState() => _ScannerScreenState();
}
class _ScannerScreenState extends State<ScannerScreen> with SingleTickerProviderStateMixin {
  final _c = TextEditingController(); List<Map<String, String>> _r = []; late AnimationController _l; bool _sc = false;
  @override void initState() { super.initState(); _l = AnimationController(vsync: this, duration: const Duration(seconds: 2)); }
  @override void dispose() { _l.dispose(); super.dispose(); }
  void _load() async {
    FilePickerResult? r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['txt', 'docx']);
    if (r != null) {
      final file = File(r.files.single.path!); String txt = "";
      if (r.files.single.extension == 'docx') { final arc = ZipDecoder().decodeBytes(await file.readAsBytes()); for (var f in arc) if (f.name == 'word/document.xml') txt = utf8.decode(f.content).replaceAll(RegExp(r'<[^>]*>'), ' '); } else txt = await file.readAsString();
      setState(() => _c.text = txt);
    }
  }
  void _scan() async {
    setState(() { _sc = true; _r.clear(); }); _l.repeat(); await Future.delayed(const Duration(seconds: 2));
    String t = _c.text;
    final i = RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b').allMatches(t).map((m) => {'v': m.group(0)!, 't': 'IP'});
    final p = RegExp(r'(?:\+380|\+7|8)[ \-\(\)]?\d{2,3}[ \-\(\)]?\d{3}[ \-]?\d{2}[ \-]?\d{2}').allMatches(t).map((m) => {'v': m.group(0)!, 't': 'ТЕЛЕФОН'});
    final e = RegExp(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}').allMatches(t).map((m) => {'v': m.group(0)!, 't': 'EMAIL'});
    final u = RegExp(r'(?:https?:\/\/)?(?:www\.)?(?:t\.me|instagram\.com|facebook\.com|vk\.com|x\.com)\/[a-zA-Z0-9_.-]+').allMatches(t).map((m) => {'v': m.group(0)!, 't': 'СОЦМЕРЕЖА/ЛІНК'});
    setState(() { _r = [...i, ...p, ...e, ...u]; _sc = false; }); _l.stop(); widget.onLog("Сканер: знайдено ${_r.length} об'єктів");
  }
  bool _en(String v) => v.contains('.ru') || v.contains('+7') || v.contains('vk.com') || v.contains('mail.ru');
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('РАДАР-СКАНЕР'), actions: [IconButton(icon: const Icon(Icons.file_open), onPressed: _load)]), body: Column(children: [
    Stack(children: [ Padding(padding: const EdgeInsets.all(16), child: TextField(controller: _c, maxLines: 5, decoration: const InputDecoration(labelText: 'ВВЕДІТЬ АБО ЗАВАНТАЖТЕ ТЕКСТ'))), if (_sc) AnimatedBuilder(animation: _l, builder: (c, _) => Positioned(top: 20 + (_l.value * 120), left: 16, right: 16, child: Container(height: 2, color: Colors.red, decoration: const BoxDecoration(boxShadow: [BoxShadow(color: Colors.red, blurRadius: 10)])))) ]),
    ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0057B7)), onPressed: _scan, child: const Text('СКАЛУВАТИ ДАНІ', style: TextStyle(color: Colors.white))),
    Expanded(child: ListView.builder(itemCount: _r.length, itemBuilder: (c, i) => Card(color: _en(_r[i]['v']!) ? Colors.red.withOpacity(0.2) : Colors.white.withOpacity(0.05), child: ListTile(title: Text(_r[i]['v']!, style: TextStyle(color: _en(_r[i]['v']!) ? Colors.redAccent : Colors.greenAccent, fontWeight: FontWeight.bold)), subtitle: Text(_r[i]['t']!, style: const TextStyle(fontSize: 10)), trailing: IconButton(icon: const Icon(Icons.copy, size: 16), onPressed: () { Clipboard.setData(ClipboardData(text: _r[i]['v']!)); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Скопійовано!'))); })))))
  ]));
}

// --- EXIF ---
class ExifScreen extends StatefulWidget {
  final Function(String) onLog; const ExifScreen({super.key, required this.onLog});
  @override State<ExifScreen> createState() => _ExifScreenState();
}
class _ExifScreenState extends State<ExifScreen> {
  Map<String, dynamic> _d = {};
  void _p() async { FilePickerResult? r = await FilePicker.platform.pickFiles(type: FileType.image); if (r != null) { final t = await readExifFromBytes(await File(r.files.single.path!).readAsBytes()); setState(() => _d = t); widget.onLog("EXIF: фото проаналізовано"); } }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('EXIF АНАЛІЗАТОР')), body: Column(children: [ const SizedBox(height: 10), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0057B7)), onPressed: _p, child: const Text('ОБРАТИ ФОТО', style: TextStyle(color: Colors.white))), const SizedBox(height: 10), Expanded(child: _d.isEmpty ? const Center(child: Text('ЧЕКАЮ НА ФАЙЛ...', style: TextStyle(color: Colors.white24))) : ListView.builder(itemCount: _d.length, itemBuilder: (c, i) => Card(color: Colors.white.withOpacity(0.05), margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), child: ListTile(title: Text(_d.keys.elementAt(i), style: const TextStyle(fontSize: 12)), subtitle: Text(_d.values.elementAt(i).toString(), style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)))))) ]));
}

// --- ІПН ---
class IpnScreen extends StatefulWidget {
  final Function(String) onLog; const IpnScreen({super.key, required this.onLog});
  @override State<IpnScreen> createState() => _IpnScreenState();
}
class _IpnScreenState extends State<IpnScreen> {
  final _c = TextEditingController(); Map<String, String>? _r;
  void _d() {
    String s = _c.text.trim(); if (s.length != 10) return;
    DateTime d = DateTime(1899, 12, 31).add(Duration(days: int.parse(s.substring(0, 5)))); int a = DateTime.now().year - d.year;
    setState(() => _r = {'ДАТА НАРОДЖЕННЯ': "${d.day.toString().padLeft(2,'0')}.${d.month.toString().padLeft(2,'0')}.${d.year}", 'ПОВНИХ РОКІВ': "$a", 'СТАТЬ': int.parse(s[8]) % 2 == 0 ? 'Жіноча' : 'Чоловіча'});
    widget.onLog("ІПН: успішно дешифровано");
  }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('ДЕШИФРАТОР ІПН')), body: Padding(padding: const EdgeInsets.all(16), child: Column(children: [ TextField(controller: _c, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'ВВЕДІТЬ 10 ЦИФР РНОКПП')), const SizedBox(height: 10), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0057B7)), onPressed: _d, child: const Text('ДЕШИФРУВАТИ', style: TextStyle(color: Colors.white))), const SizedBox(height: 20), if (_r != null) ..._r!.entries.map((e) => ListTile(title: Text(e.key, style: const TextStyle(color: Colors.grey)), subtitle: ScrambleText(text: e.value, style: const TextStyle(color: Colors.greenAccent, fontSize: 22, fontWeight: FontWeight.bold)))) ])));
}

// --- ФІНАНСИ ---
class FinScreen extends StatefulWidget {
  final Function(String) onLog; const FinScreen({super.key, required this.onLog});
  @override State<FinScreen> createState() => _FinScreenState();
}
class _FinScreenState extends State<FinScreen> {
  final _c = TextEditingController(); String _r = "";
  void _ch() {
    String cc = _c.text.replaceAll(' ', ''); if (cc.isEmpty) return;
    int s = 0; bool a = false; for (int i = cc.length - 1; i >= 0; i--) { int n = int.parse(cc[i]); if (a) { n *= 2; if (n > 9) n -= 9; } s += n; a = !a; }
    setState(() => _r = s % 10 == 0 ? "✅ ВАЛІДНА КАРТКА" : "❌ НЕ КОРЕКТНА (ПОМИЛКА ЛУНА)"); widget.onLog("Фінанси: перевірка картки");
  }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('ВАЛІДАТОР КАРТОК')), body: Padding(padding: const EdgeInsets.all(16), child: Column(children: [ TextField(controller: _c, decoration: const InputDecoration(labelText: 'НОМЕР КАРТКИ')), const SizedBox(height: 10), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0057B7)), onPressed: _ch, child: const Text('ПЕРЕВІРИТИ (АЛГОРИТМ ЛУНА)', style: TextStyle(color: Colors.white))), const SizedBox(height: 30), Text(_r, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _r.contains('ВАЛІДНА') ? Colors.greenAccent : Colors.redAccent)) ])));
}

// --- АВТО ---
class AutoScreen extends StatefulWidget {
  final Function(String) onLog; const AutoScreen({super.key, required this.onLog});
  @override State<AutoScreen> createState() => _AutoScreenState();
}
class _AutoScreenState extends State<AutoScreen> {
  final _c = TextEditingController(); String _r = "";
  final Map<String, String> _reg = {'AA': 'м. Київ', 'KA': 'м. Київ', 'TT': 'м. Київ', 'AB': 'Вінницька обл.', 'KB': 'Вінницька обл.', 'AC': 'Волинська обл.', 'AE': 'Дніпропетровська обл.', 'KE': 'Дніпропетровська обл.', 'AH': 'Донецька обл.', 'AM': 'Житомирська обл.', 'AO': 'Закарпатська обл.', 'AP': 'Запорізька обл.', 'AT': 'Івано-Франківська обл.', 'AI': 'Київська обл.', 'BA': 'Кіровоградська обл.', 'BB': 'Луганська обл.', 'BC': 'Львівська обл.', 'HC': 'Львівська обл.', 'BE': 'Миколаївська обл.', 'BH': 'Одеська обл.', 'HH': 'Одеська обл.', 'BI': 'Полтавська обл.', 'BK': 'Рівненська обл.', 'BM': 'Сумська обл.', 'BO': 'Тернопільська обл.', 'AX': 'Харківська обл.', 'KX': 'Харківська обл.', 'BT': 'Херсонська обл.', 'BX': 'Хмельницька обл.', 'CA': 'Черкаська обл.', 'CB': 'Чернігівська обл.', 'CE': 'Чернівецька обл.', 'AK': 'АР Крим', 'CH': 'м. Севастополь'};
  void _ch() { String s = _c.text.trim().toUpperCase(); if (s.length < 2) return; setState(() => _r = _reg[s.substring(0, 2)] ?? "Невідомий регіон / Новий формат"); widget.onLog("Авто: пошук регіону"); }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('АВТО НОМЕРИ')), body: Padding(padding: const EdgeInsets.all(16), child: Column(children: [ TextField(controller: _c, decoration: const InputDecoration(labelText: 'НОМЕР (напр. АА1234ВВ)')), const SizedBox(height: 10), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0057B7)), onPressed: _ch, child: const Text('ВИЗНАЧИТИ РЕГІОН', style: TextStyle(color: Colors.white))), const SizedBox(height: 30), Text(_r, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.greenAccent)) ])));
}

// --- НІКНЕЙМИ ---
class NickScreen extends StatefulWidget {
  final Function(String) onLog; const NickScreen({super.key, required this.onLog});
  @override State<NickScreen> createState() => _NickScreenState();
}
class _NickScreenState extends State<NickScreen> {
  final _c = TextEditingController(); List<String> _r = [];
  void _g() { String s = _c.text.trim().toLowerCase().replaceAll(' ', '_'); if (s.isEmpty) return; setState(() => _r = [s, "${s}_osint", "the_$s", "real_$s", "${s}2026", "$s.ua", "sec_$s", "$s.priv", "$s@gmail.com", "$s@proton.me"]); widget.onLog("Нікнейми: генерація"); }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('ГЕНЕРАТОР НІКІВ')), body: Column(children: [ Padding(padding: const EdgeInsets.all(16), child: TextField(controller: _c, decoration: const InputDecoration(labelText: 'БАЗОВЕ СЛОВО АБО ПРІЗВИЩЕ'))), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0057B7)), onPressed: _g, child: const Text('ЗГЕНЕРУВАТИ ВАРІАНТИ', style: TextStyle(color: Colors.white))), Expanded(child: ListView.builder(itemCount: _r.length, itemBuilder: (c, i) => Card(color: Colors.white.withOpacity(0.05), margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), child: ListTile(title: Text(_r[i], style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)), trailing: IconButton(icon: const Icon(Icons.copy, size: 16), onPressed: () { Clipboard.setData(ClipboardData(text: _r[i])); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Скопійовано!'))); } ))))) ]));
}

// --- ХРОНОЛОГІЯ ---
class TimeScreen extends StatefulWidget {
  final Function(String) onLog; const TimeScreen({super.key, required this.onLog});
  @override State<TimeScreen> createState() => _TimeScreenState();
}
class _TimeScreenState extends State<TimeScreen> {
  List<Map<String, String>> _e = [];
  @override void initState() { super.initState(); _l(); }
  void _l() async { final p = await SharedPreferences.getInstance(); final d = p.getString('tl'); if (d != null) setState(() => _e = List<Map<String, String>>.from(json.decode(d).map((x) => Map<String, String>.from(x)))); }
  void _s() async { final p = await SharedPreferences.getInstance(); p.setString('tl', json.encode(_e)); }
  void _a() {
    final dC = TextEditingController(text: "${DateTime.now().day.toString().padLeft(2,'0')}.${DateTime.now().month.toString().padLeft(2,'0')}.${DateTime.now().year}"); final tC = TextEditingController();
    showDialog(context: context, builder: (c) => AlertDialog(backgroundColor: const Color(0xFF0A152F), title: const Text('НОВА ПОДІЯ'), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: dC, decoration: const InputDecoration(labelText: 'Дата')), const SizedBox(height: 10), TextField(controller: tC, maxLines: 3, decoration: const InputDecoration(labelText: 'Опис події'))]), actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('СКАСУВАТИ')), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0057B7)), onPressed: () { setState(() => _e.add({'d': dC.text, 't': tC.text})); _s(); Navigator.pop(c); widget.onLog("Таймлайн: додано подію"); }, child: const Text('ДОДАТИ', style: TextStyle(color: Colors.white)))]));
  }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('ХРОНОЛОГІЯ')), body: _e.isEmpty ? const Center(child: Text('ПОДІЙ НЕМАЄ', style: TextStyle(color: Colors.white24))) : ListView.builder(itemCount: _e.length, itemBuilder: (c, i) => Card(color: Colors.white.withOpacity(0.05), margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), child: ListTile(leading: const Icon(Icons.circle, size: 12, color: Colors.blueAccent), title: Text(_e[i]['d']!, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent)), subtitle: Text(_e[i]['t']!), trailing: IconButton(icon: const Icon(Icons.delete, size: 16, color: Colors.red), onPressed: () { setState(() => _e.removeAt(i)); _s(); })))), floatingActionButton: FloatingActionButton(backgroundColor: const Color(0xFF0057B7), onPressed: _a, child: const Icon(Icons.add, color: Colors.white)));
}

// --- СЕЙФ З ПАРОЛЕМ ---
class VaultScreen extends StatefulWidget {
  final Function(String) onLog; const VaultScreen({super.key, required this.onLog});
  @override State<VaultScreen> createState() => _VaultScreenState();
}
class _VaultScreenState extends State<VaultScreen> {
  bool _unlocked = false; final _mp = TextEditingController();
  List<Map<String, String>> _v = [];
  @override void initState() { super.initState(); _l(); }
  void _l() async { final p = await SharedPreferences.getInstance(); final d = p.getString('vt'); if (d != null) setState(() => _v = List<Map<String, String>>.from(json.decode(d).map((x) => Map<String, String>.from(x)))); }
  void _s() async { final p = await SharedPreferences.getInstance(); p.setString('vt', json.encode(_v)); }
  void _a() {
    final rC = TextEditingController(), lC = TextEditingController(), pC = TextEditingController();
    showDialog(context: context, builder: (c) => AlertDialog(backgroundColor: const Color(0xFF0A152F), title: const Text('НОВИЙ ЗАПИС'), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: rC, decoration: const InputDecoration(labelText: 'Ресурс (Сайт/Додаток)')), const SizedBox(height: 10), TextField(controller: lC, decoration: const InputDecoration(labelText: 'Логін / Email / Phone')), const SizedBox(height: 10), TextField(controller: pC, decoration: const InputDecoration(labelText: 'Пароль'))]), actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('СКАСУВАТИ')), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0057B7)), onPressed: () { setState(() => _v.add({'r': rC.text, 'l': lC.text, 'p': pC.text})); _s(); Navigator.pop(c); widget.onLog("Сейф: додано запис"); }, child: const Text('ЗБЕРЕГТИ', style: TextStyle(color: Colors.white)))]));
  }
  @override Widget build(BuildContext context) {
    if (!_unlocked) {
      return Scaffold(appBar: AppBar(title: const Text('СЕЙФ [ЗАБЛОКОВАНО]')), body: Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [ const Icon(Icons.lock, size: 64, color: Colors.yellow), const SizedBox(height: 20), TextField(controller: _mp, obscureText: true, decoration: const InputDecoration(labelText: 'МАЙСТЕР-ПАРОЛЬ'), onSubmitted: (val) { if (val == 'osint2026') { setState(() => _unlocked = true); widget.onLog("Сейф: успішний вхід"); } else { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('НЕВІРНИЙ ПАРОЛЬ!'), backgroundColor: Colors.red)); } }), const SizedBox(height: 20), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0057B7)), onPressed: () { if (_mp.text == 'osint2026') { setState(() => _unlocked = true); widget.onLog("Сейф: успішний вхід"); } else { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('НЕВІРНИЙ ПАРОЛЬ!'), backgroundColor: Colors.red)); } }, child: const Text('ВІДЧИНИТИ', style: TextStyle(color: Colors.white))) ]))));
    }
    return Scaffold(appBar: AppBar(title: const Text('СЕЙФ [ВІДКРИТО]'), actions: [IconButton(icon: const Icon(Icons.lock_open, color: Colors.red), onPressed: () => setState(() { _unlocked = false; _mp.clear(); }))]), body: _v.isEmpty ? const Center(child: Text('СЕЙФ ПУСТИЙ', style: TextStyle(color: Colors.white24))) : ListView.builder(itemCount: _v.length, itemBuilder: (c, i) => Card(color: Colors.white.withOpacity(0.05), margin: const EdgeInsets.all(8), child: ListTile(leading: const Icon(Icons.security, color: Colors.yellow), title: Text(_v[i]['r']!, style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)), subtitle: Text("Логін: ${_v[i]['l']!}\nПароль: ${_v[i]['p']!}"), isThreeLine: true, trailing: Column(mainAxisAlignment: MainAxisAlignment.center, children: [IconButton(icon: const Icon(Icons.copy, size: 20, color: Colors.white), padding: EdgeInsets.zero, constraints: const BoxConstraints(), onPressed: () { Clipboard.setData(ClipboardData(text: _v[i]['p']!)); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Пароль скопійовано'))); }), const SizedBox(height: 8), IconButton(icon: const Icon(Icons.delete, size: 20, color: Colors.red), padding: EdgeInsets.zero, constraints: const BoxConstraints(), onPressed: () { setState(() => _v.removeAt(i)); _s(); })])))), floatingActionButton: FloatingActionButton(backgroundColor: const Color(0xFF0057B7), onPressed: _a, child: const Icon(Icons.add, color: Colors.white)));
  }
}

// --- ЕКРАН ГЕНЕРАЦІЇ ПРОМПТІВ ---
class GenScreen extends StatefulWidget {
  final Prompt p; final Function(String) onLog;
  const GenScreen({super.key, required this.p, required this.onLog});
  @override State<GenScreen> createState() => _GenScreenState();
}
class _GenScreenState extends State<GenScreen> {
  final Map<String, TextEditingController> _c = {}; bool _comp = false; List<TextSpan> _s = []; int _l = 0; Timer? _t;
  final List<PromptEnhancer> _e = [
    PromptEnhancer(name: 'CoT (Chain of Thought)', desc: 'Покрокове мислення', pros: 'Висока точність', cons: 'Довга відповідь', rec: 'Для логіки', payload: 'Пояснюй свій хід думок крок за кроком (Step-by-step) перед фінальною відповіддю.'),
    PromptEnhancer(name: 'ToT (Tree of Thoughts)', desc: 'Дерево думок', pros: 'Аналіз гіпотез', cons: 'Повільно', rec: 'Коли мало даних', payload: 'Згенеруй 3 гіпотези. Проаналізуй кожну і обери найбільш імовірну.'),
    PromptEnhancer(name: 'Persona (Експерт)', desc: 'Професійна роль', pros: 'Сухий стиль', cons: '-', rec: 'Для звітів', payload: 'Дій як старший OSINT-аналітик. Твоя відповідь має бути максимально точною, сухою, без емоцій.'),
    PromptEnhancer(name: 'BLUF (Bottom Line Up Front)', desc: 'Висновок спочатку', pros: 'Економія часу', cons: 'Менше деталей', rec: 'Для керівництва', payload: 'Використовуй формат BLUF. Спочатку головний висновок в 1-2 речення, потім деталі.'),
    PromptEnhancer(name: 'JSON Format', desc: 'Видача кодом', pros: 'Машинний формат', cons: 'Тільки текст', rec: 'Для екстракції', payload: 'Поверни результат ВИКЛЮЧНО у форматі валідного JSON. Без тексту до і після.'),
  ];

  @override void initState() { 
    super.initState(); 
    final r = RegExp(r'\{([^}]+)\}'); 
    for (var m in r.allMatches(widget.p.content)) _c[m.group(1)!] = TextEditingController(); 
    // Якщо немає змінних, компілюємо відразу
    if (_c.isEmpty) _compF();
  }
  
  void _compF() {
    _s.clear(); String t = widget.p.content; int last = 0; final r = RegExp(r'\{([^}]+)\}');
    for (var m in r.allMatches(t)) {
      if (m.start > last) _s.add(TextSpan(text: t.substring(last, m.start), style: const TextStyle(color: Colors.greenAccent)));
      String v = _c[m.group(1)!]!.text; _s.add(TextSpan(text: v.isEmpty ? "{${m.group(1)}}" : v, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))); last = m.end;
    }
    if (last < t.length) _s.add(TextSpan(text: t.substring(last), style: const TextStyle(color: Colors.greenAccent)));
    
    final sel = _e.where((e) => e.isSelected).toList();
    if (sel.isNotEmpty) {
      _s.add(const TextSpan(text: "\n\n### SYSTEM_INSTRUCTIONS:\n", style: TextStyle(color: Colors.yellow, fontWeight: FontWeight.bold)));
      for (var e in sel) _s.add(TextSpan(text: "- ${e.payload}\n", style: const TextStyle(color: Colors.yellow)));
    }
    
    setState(() { _comp = true; _l = 0; }); _t?.cancel();
    _t = Timer.periodic(const Duration(milliseconds: 5), (tm) { if (!mounted) return; setState(() { _l += 15; if (_l >= _s.map((e) => e.text!.length).fold(0, (a,b)=>a+b)) tm.cancel(); }); });
    widget.onLog("Компіляція: ${widget.p.title}");
  }

  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(widget.p.title)), body: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
    if (!_comp) ...[
      Expanded(child: ListView(children: _c.keys.map((k) => Padding(padding: const EdgeInsets.only(bottom: 12), child: TextField(controller: _c[k], decoration: InputDecoration(labelText: k)))).toList())), 
      const SizedBox(height: 10), 
      ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0057B7), minimumSize: const Size(double.infinity, 50)), onPressed: _compF, child: const Text('КОМПІЛЮВАТИ ЗАПИТ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))
    ],
    if (_comp) ...[
      ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0A152F)), icon: const Icon(Icons.flash_on, color: Colors.yellow), label: const Text('ТАКТИЧНЕ ПІДСИЛЕННЯ', style: TextStyle(color: Colors.white)), onPressed: () {
        showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: const Color(0xFF0A152F), builder: (c) => StatefulBuilder(builder: (cc, sM) => Container(padding: const EdgeInsets.all(16), height: MediaQuery.of(context).size.height * 0.8, child: Column(children: [
          const Text('ПІДСИЛЕННЯ ПРОМПТУ', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.yellow, fontSize: 18)), const SizedBox(height: 10),
          Expanded(child: ListView.builder(itemCount: _e.length, itemBuilder: (ccc, i) => Card(color: Colors.white.withOpacity(0.05), child: CheckboxListTile(title: Text(_e[i].name, style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(_e[i].desc, style: const TextStyle(fontSize: 12)), const SizedBox(height: 4), Text("ПЕРЕВАГИ: ${_e[i].pros}", style: const TextStyle(fontSize: 10, color: Colors.greenAccent)), Text("РЕКОМЕНДОВАНО ДЛЯ: ${_e[i].rec}", style: const TextStyle(fontSize: 10, color: Colors.blueAccent))]), isThreeLine: true, value: _e[i].isSelected, onChanged: (v) { sM(() => _e[i].isSelected = v!); if (_comp) _compF(); })))),
          const SizedBox(height: 10), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0057B7), minimumSize: const Size(double.infinity, 50)), onPressed: () => Navigator.pop(c), child: const Text('ЗАКРИТИ', style: TextStyle(color: Colors.white)))
        ]))));
      }), const SizedBox(height: 10),
      Expanded(child: Container(width: double.infinity, padding: const EdgeInsets.all(12), color: Colors.black, child: SingleChildScrollView(child: RichText(text: TextSpan(children: _gV()))))), const SizedBox(height: 10),
      Row(children: [
        if (_c.isNotEmpty) Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.white10), onPressed: () => setState(() => _comp = false), child: const Text('РЕСЕТ', style: TextStyle(color: Colors.white)))), 
        if (_c.isNotEmpty) const SizedBox(width: 10), 
        Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0057B7)), onPressed: () { Clipboard.setData(ClipboardData(text: _s.map((x) => x.text).join())); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Текст скопійовано!'))); }, child: const Text('СКОПІЮВАТИ', style: TextStyle(color: Colors.white))))
      ]),
    ]
  ])));
  List<TextSpan> _gV() { List<TextSpan> r = []; int c = 0; for (var x in _s) { if (c + x.text!.length <= _l) { r.add(x); c += x.text!.length; } else { r.add(TextSpan(text: x.text!.substring(0, _l - c), style: x.style)); break; } } return r; }
}

class PDFViewerScreen extends StatelessWidget { final PDFDoc doc; const PDFViewerScreen({super.key, required this.doc}); @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(doc.name)), body: PDFView(filePath: doc.path)); }
