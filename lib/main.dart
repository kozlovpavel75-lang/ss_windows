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

// Глобальна тема Матриці
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

// --- ВІЗУАЛ: СІТКА ТА ЕФЕКТИ ---
class TopoGridPainter extends CustomPainter {
  final bool isGreen;
  TopoGridPainter(this.isGreen);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = isGreen ? Colors.green.withOpacity(0.05) : const Color(0xFF0057B7).withOpacity(0.03)..strokeWidth = 1.0;
    for (double i = 0; i < size.width; i += 40) canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    for (double i = 0; i < size.height; i += 40) canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class ScrambleText extends StatefulWidget {
  final String text;
  final TextStyle style;
  const ScrambleText({super.key, required this.text, required this.style});
  @override
  State<ScrambleText> createState() => _ScrambleTextState();
}

class _ScrambleTextState extends State<ScrambleText> {
  String _display = "";
  Timer? _timer;
  final _chars = "ABCDEF0123456789#!@?*";
  @override
  void initState() {
    super.initState();
    int frame = 0;
    _timer = Timer.periodic(const Duration(milliseconds: 30), (t) {
      if (!mounted) return;
      setState(() {
        frame++; _display = "";
        for (int i = 0; i < widget.text.length; i++) {
          if (frame > i + 3) _display += widget.text[i];
          else _display += _chars[math.Random().nextInt(_chars.length)];
        }
        if (frame > widget.text.length + 10) t.cancel();
      });
    });
  }
  @override
  void dispose() { _timer?.cancel(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Text(_display, style: widget.style);
}

// --- ГОЛОВНИЙ ДОДАТОК ---
class PromptApp extends StatelessWidget {
  const PromptApp({super.key});
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isMatrixMode,
      builder: (context, matrix, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: Brightness.dark,
            scaffoldBackgroundColor: matrix ? Colors.black : const Color(0xFF040E22),
            primaryColor: matrix ? Colors.greenAccent : const Color(0xFF0057B7),
            fontFamily: 'monospace',
            inputDecorationTheme: InputDecorationTheme(
              filled: true, fillColor: matrix ? Colors.black : const Color(0xFF0A152F),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: matrix ? const BorderSide(color: Colors.green) : BorderSide.none),
            ),
          ),
          home: const SplashScreen(),
        );
      }
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
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: Container(width: double.infinity, height: double.infinity, decoration: const BoxDecoration(image: DecorationImage(image: AssetImage('assets/splash.png'), fit: BoxFit.cover))),
  );
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
  int _matrixTaps = 0;

  final List<String> categories = ['ФО', 'ЮО', 'ГЕОІНТ', 'МОНІТОРИНГ', 'ІНСТРУМЕНТИ', 'ДОКУМЕНТИ'];
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
    final timeStr = "${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
    setState(() {
      auditLogs.insert(0, "[$timeStr] $action");
      if (auditLogs.length > 50) auditLogs.removeLast();
    });
    _save();
  }

  void _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final pStr = prefs.getString('prompts_data');
    final dStr = prefs.getString('docs_data');
    final logs = prefs.getStringList('audit_logs');
    setState(() {
      if (pStr != null) prompts = (json.decode(pStr) as List).map((i) => Prompt.fromJson(i)).toList();
      if (dStr != null) docs = (json.decode(dStr) as List).map((i) => PDFDoc.fromJson(i)).toList();
      if (logs != null) auditLogs = logs;
      if (prompts.isEmpty) {
        prompts = [Prompt(id: '1', title: 'ПОШУК ПЕРСОНИ', category: 'ФО', content: 'Аналіз даних: {ПІБ}', isFavorite: true)];
      }
    });
  }

  void _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('prompts_data', json.encode(prompts.map((p) => p.toJson()).toList()));
    await prefs.setString('docs_data', json.encode(docs.map((d) => d.toJson()).toList()));
    await prefs.setStringList('audit_logs', auditLogs);
  }

  void _importTxt() async {
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
            if (l.startsWith('категорія:')) {
              String rawCat = l.replaceFirst('категорія:', '').trim();
              if (rawCat == 'фо' || rawCat.contains('фіз')) cat = 'ФО';
              else if (rawCat == 'юо' || rawCat.contains('юр')) cat = 'ЮО';
              else if (rawCat.contains('гео')) cat = 'ГЕОІНТ';
            }
            else if (l.startsWith('назва:')) title = line.replaceFirst(RegExp(r'Назва:', caseSensitive: false), '').trim();
            else if (l.startsWith('текст:')) { text = line.replaceFirst(RegExp(r'Текст:', caseSensitive: false), '').trim(); isText = true; }
            else if (isText) text += '\n$line';
          }
          if (title.isNotEmpty && text.isNotEmpty) {
            imported.add(Prompt(id: DateTime.now().millisecondsSinceEpoch.toString() + title, title: title, content: text.trim(), category: cat));
          }
        }
        setState(() => prompts.addAll(imported));
        _logAction("Імпорт: +${imported.length} записів");
        _save();
      } catch (e) { _logAction("Помилка імпорту"); }
    }
  }

  void _showStats() {
    Map<String, int> stats = {'ФО': 0, 'ЮО': 0, 'ГЕОІНТ': 0, 'МОНІТОРИНГ': 0};
    int total = prompts.length;
    for (var p in prompts) { if (stats.containsKey(p.category)) stats[p.category] = stats[p.category]! + 1; }
    showDialog(context: context, builder: (c) => AlertDialog(
      backgroundColor: const Color(0xFF040E22),
      title: const Text('MISSION_CONTROL'),
      content: Column(mainAxisSize: MainAxisSize.min, children: stats.entries.map((e) => Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(e.key), Text('${e.value}')]),
        LinearProgressIndicator(value: total == 0 ? 0 : e.value / total, color: const Color(0xFF0057B7)),
        const SizedBox(height: 8),
      ])).toList()),
    ));
  }

  void _addOrEditPrompt({Prompt? p}) {
    final tCtrl = TextEditingController(text: p?.title ?? '');
    final cCtrl = TextEditingController(text: p?.content ?? '');
    String selectedCat = p?.category ?? 'ФО';
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (context, setS) => AlertDialog(
      backgroundColor: const Color(0xFF0A152F),
      title: Text(p == null ? 'НОВИЙ ЗАПИС' : 'РЕДАГУВАННЯ'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButton<String>(isExpanded: true, value: selectedCat, items: ['ФО','ЮО','ГЕОІНТ','МОНІТОРИНГ'].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(), onChanged: (v) => setS(() => selectedCat = v!)),
        TextField(controller: tCtrl, decoration: const InputDecoration(labelText: 'НАЗВА')),
        TextField(controller: cCtrl, maxLines: 3, decoration: const InputDecoration(labelText: 'ЗМІСТ {VAR}')),
      ]),
      actions: [
        if (p != null) TextButton(onPressed: () async {
          Navigator.pop(ctx);
          setState(() { p.title = "█████████"; p.content = "████████████████"; });
          HapticFeedback.heavyImpact();
          await Future.delayed(const Duration(milliseconds: 600));
          setState(() => prompts.remove(p)); _save();
        }, child: const Text('ВИДАЛИТИ', style: TextStyle(color: Colors.red))),
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('СКАСУВАТИ')),
        ElevatedButton(onPressed: () {
          setState(() {
            if (p == null) prompts.add(Prompt(id: DateTime.now().toString(), title: tCtrl.text, content: cCtrl.text, category: selectedCat));
            else { p.title = tCtrl.text; p.content = cCtrl.text; p.category = selectedCat; }
          });
          _save(); Navigator.pop(ctx);
        }, child: const Text('ЗБЕРЕГТИ'))
      ],
    )));
  }

  void _pickPDF() async {
    FilePickerResult? r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    if (r != null && r.files.single.path != null) {
      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/${r.files.single.name}';
      await File(r.files.single.path!).copy(path);
      setState(() => docs.add(PDFDoc(id: DateTime.now().toString(), name: r.files.single.name, path: path)));
      _save();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () { if (++_matrixTaps >= 7) { isMatrixMode.value = !isMatrixMode.value; _matrixTaps = 0; HapticFeedback.vibrate(); } },
          child: Text('UKR_OSINT', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2, color: isMatrixMode.value ? Colors.greenAccent : Colors.white)),
        ),
        actions: [
          IconButton(icon: Icon(Icons.analytics, color: uaYellow), onPressed: _showStats),
          IconButton(icon: const Icon(Icons.receipt_long, color: Colors.white70), onPressed: () {
            showDialog(context: context, builder: (c) => AlertDialog(backgroundColor: Colors.black, title: const Text('AUDIT_LOG'), content: SizedBox(width: double.maxFinite, height: 300, child: ListView.builder(itemCount: auditLogs.length, itemBuilder: (cc, i) => Text(auditLogs[i], style: const TextStyle(fontSize: 10, color: Colors.greenAccent))))));
          }),
          IconButton(icon: const Icon(Icons.download, color: Color(0xFF0057B7)), onPressed: _importTxt),
        ],
        bottom: TabBar(controller: _tabController, isScrollable: true, tabs: categories.map((c) => Tab(text: c)).toList()),
      ),
      body: Stack(children: [
        CustomPaint(painter: TopoGridPainter(isMatrixMode.value), child: Container()),
        TabBarView(controller: _tabController, children: categories.map((cat) {
          if (cat == 'ІНСТРУМЕНТИ') return ToolsMenuScreen(onLog: _logAction);
          if (cat == 'ДОКУМЕНТИ') return _buildDocs();
          final items = prompts.where((p) => p.category == cat).toList();
          if (items.isEmpty) return _buildEmptyState('ПУСТО');
          items.sort((a, b) => (b.isFavorite ? 1 : 0).compareTo(a.isFavorite ? 1 : 0));
          return ListView.builder(itemCount: items.length, itemBuilder: (ctx, i) => Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), color: Colors.white.withOpacity(0.05),
            child: ListTile(
              leading: IconButton(icon: Icon(items[i].isFavorite ? Icons.star : Icons.star_border, color: items[i].isFavorite ? uaYellow : Colors.white24), onPressed: () { setState(() => items[i].isFavorite = !items[i].isFavorite); _save(); }),
              title: Text(items[i].title, style: const TextStyle(fontWeight: FontWeight.bold)),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GenScreen(p: items[i], onLog: _logAction))),
              onLongPress: () => _addOrEditPrompt(p: items[i]),
            ),
          ));
        }).toList()),
      ]),
      floatingActionButton: _tabController.index == 4 ? null : FloatingActionButton(backgroundColor: const Color(0xFF0057B7), onPressed: () => _tabController.index == 5 ? _pickPDF() : _addOrEditPrompt(), child: Icon(_tabController.index == 5 ? Icons.picture_as_pdf : Icons.add, color: Colors.white)),
    );
  }

  Widget _buildEmptyState(String msg) => Center(child: Text("[ $msg ]", style: const TextStyle(color: Colors.white24, letterSpacing: 2)));
  Widget _buildDocs() => docs.isEmpty ? _buildEmptyState('ФАЙЛІВ НЕМАЄ') : ListView.builder(itemCount: docs.length, itemBuilder: (ctx, i) => Card(
    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), color: Colors.white.withOpacity(0.05),
    child: ListTile(leading: const Icon(Icons.file_copy, color: Colors.white54), title: Text(docs[i].name), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PDFViewerScreen(doc: docs[i]))), trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.redAccent), onPressed: () { setState(() => docs.removeAt(i)); _save(); })),
  ));
}

// --- ЕКРАН ГЕНЕРАЦІЇ З ТАКТИЧНИМ ПІДСИЛЕННЯМ ---
class GenScreen extends StatefulWidget {
  final Prompt p;
  final Function(String) onLog;
  const GenScreen({super.key, required this.p, required this.onLog});
  @override
  State<GenScreen> createState() => _GenScreenState();
}

class _GenScreenState extends State<GenScreen> {
  final Map<String, TextEditingController> _ctrls = {};
  bool _isCompiled = false;
  List<TextSpan> _spans = [];
  int _limit = 0;
  Timer? _timer;

  final List<PromptEnhancer> _enhancers = [
    PromptEnhancer(
      name: 'CoT (Chain of Thought)', 
      desc: 'Змушує ШІ думати покроково.', 
      pros: 'Висока точність, прозорість висновків.', 
      cons: 'Довга відповідь, витрати токенів.', 
      recommendation: 'Для складних логічних задач та аналітики.', 
      payload: 'Пояснюй свій хід думок крок за кроком (Step-by-step) перед фінальною відповіддю.'
    ),
    PromptEnhancer(
      name: 'ToT (Tree of Thoughts)', 
      desc: 'Генерація та оцінка гіпотез.', 
      pros: 'Мінімізує галюцинації, знаходить альтернативи.', 
      cons: 'Може плутати прості завдання.', 
      recommendation: 'Коли є кілька версій подій або підозрюваних.', 
      payload: 'Розглянь 3 різні гіпотези. Проаналізуй кожну окремо і наприкінці обери найбільш імовірну.'
    ),
    PromptEnhancer(
      name: 'Persona (Експерт)', 
      desc: 'Задає професійну роль.', 
      pros: 'Стислий, професійний стиль.', 
      cons: 'Може стати занадто формальним.', 
      recommendation: 'Для підготовки офіційних звітів.', 
      payload: 'Дій як старший OSINT-аналітик з 10-річним досвідом. Твоя відповідь має бути сухою, точною та без зайвих пояснень.'
    ),
    PromptEnhancer(
      name: 'Self-Reflect (Критик)', 
      desc: 'ШІ перевіряє власні помилки.', 
      pros: 'Критичний погляд на дані.', 
      cons: 'Дуже повільна генерація.', 
      recommendation: 'Для перевірки фактів та спростування фейків.', 
      payload: 'Після надання відповіді, критично оціни її. Знайди можливі логічні дірки та додай блок "Корекція".'
    ),
  ];

  @override
  void initState() {
    super.initState();
    final reg = RegExp(r'\{([^}]+)\}');
    for (var m in reg.allMatches(widget.p.content)) _ctrls[m.group(1)!] = TextEditingController();
  }

  void _compile() {
    _spans.clear();
    String t = widget.p.content;
    int last = 0;
    final reg = RegExp(r'\{([^}]+)\}');
    for (var m in reg.allMatches(t)) {
      if (m.start > last) _spans.add(TextSpan(text: t.substring(last, m.start), style: const TextStyle(color: Colors.greenAccent)));
      String val = _ctrls[m.group(1)!]!.text;
      _spans.add(TextSpan(text: val.isEmpty ? "{${m.group(1)}}" : val, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)));
      last = m.end;
    }
    if (last < t.length) _spans.add(TextSpan(text: t.substring(last), style: const TextStyle(color: Colors.greenAccent)));

    final selected = _enhancers.where((e) => e.isSelected).toList();
    if (selected.isNotEmpty) {
      _spans.add(const TextSpan(text: "\n\n### SYSTEM_INSTRUCTIONS:\n", style: TextStyle(color: Colors.yellow, fontWeight: FontWeight.bold)));
      for (var e in selected) _spans.add(TextSpan(text: "- ${e.payload}\n", style: const TextStyle(color: Colors.yellow)));
    }

    setState(() { _isCompiled = true; _limit = 0; });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 5), (timer) {
      if (!mounted) return;
      setState(() { _limit += 12; if (_limit >= _totalLen()) timer.cancel(); });
    });
  }

  int _totalLen() => _spans.map((s) => s.text!.length).fold(0, (a, b) => a + b);

  void _showEnhance() {
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: const Color(0xFF0A152F), builder: (c) => StatefulBuilder(builder: (cc, setM) => Container(
      padding: const EdgeInsets.all(16), height: MediaQuery.of(context).size.height * 0.8,
      child: Column(children: [
        const Text('ТАКТИЧНЕ ПІДСИЛЕННЯ (PROMPT ENG)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.yellow)),
        const SizedBox(height: 10),
        Expanded(child: ListView.builder(itemCount: _enhancers.length, itemBuilder: (ccc, i) => Card(
          color: Colors.white.withOpacity(0.05),
          child: CheckboxListTile(
            title: Text(_enhancers[i].name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_enhancers[i].desc, style: const TextStyle(fontSize: 12)),
              Text("ПЕРЕВАГИ: ${_enhancers[i].pros}", style: const TextStyle(fontSize: 10, color: Colors.greenAccent)),
              Text("РЕКОМЕНДОВАНО: ${_enhancers[i].recommendation}", style: const TextStyle(fontSize: 10, color: Colors.blueAccent)),
            ]),
            value: _enhancers[i].isSelected, onChanged: (v) { setM(() => _enhancers[i].isSelected = v!); if (_isCompiled) _compile(); },
          ),
        ))),
        ElevatedButton(onPressed: () => Navigator.pop(c), child: const Text('ЗАКРИТИ'))
      ]),
    )));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.p.title)),
    body: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
      if (!_isCompiled) ...[
        ..._ctrls.keys.map((k) => TextField(controller: _ctrls[k], decoration: InputDecoration(labelText: k))),
        const SizedBox(height: 20),
        ElevatedButton(style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)), onPressed: _compile, child: const Text('КОМПІЛЮВАТИ')),
      ] else ...[
        ElevatedButton.icon(icon: const Icon(Icons.flash_on, color: Colors.yellow), label: const Text('ПІДСИЛЕННЯ ПРОМПТУ'), onPressed: _showEnhance),
        const SizedBox(height: 10),
        Expanded(child: Container(width: double.infinity, padding: const EdgeInsets.all(12), color: Colors.black, child: SingleChildScrollView(child: RichText(text: TextSpan(children: _getVisibleSpans()))))),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: ElevatedButton(onPressed: () => setState(() => _isCompiled = false), child: const Text('RESET'))),
          const SizedBox(width: 10),
          Expanded(child: ElevatedButton(onPressed: () { Clipboard.setData(ClipboardData(text: _spans.map((s) => s.text).join())); }, child: const Text('COPY'))),
        ]),
      ]
    ])),
  );

  List<TextSpan> _getVisibleSpans() {
    List<TextSpan> res = []; int cur = 0;
    for (var s in _spans) {
      if (cur + s.text!.length <= _limit) { res.add(s); cur += s.text!.length; }
      else { res.add(TextSpan(text: s.text!.substring(0, _limit - cur), style: s.style)); break; }
    }
    return res;
  }
}

// --- ІНСТРУМЕНТИ ---
class ToolsMenuScreen extends StatelessWidget {
  final Function(String) onLog;
  const ToolsMenuScreen({super.key, required this.onLog});
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(10), children: [
    _t(context, 'DORKS', 'Google Конструктор', Icons.travel_explore, DorksScreen(onLog: onLog)),
    _t(context, 'СКАНЕР', 'Екстракція (Laser/DOCX)', Icons.radar, ScannerScreen(onLog: onLog)),
    _t(context, 'EXIF', 'Аналіз фотографій', Icons.image_search, ExifScreen(onLog: onLog)),
    _t(context, 'ДЕШИФРАТОР ІПН', 'Аналіз РНОКПП (Brute)', Icons.fingerprint, IpnDecoderScreen(onLog: onLog)),
    _t(context, 'ФІНАНСИ', 'Валідатор карток/IBAN', Icons.credit_card, FinValidatorScreen(onLog: onLog)),
    _t(context, 'АВТОМОБІЛІ', 'Регіони та VIN', Icons.directions_car, AutoModuleScreen(onLog: onLog)),
    _t(context, 'НІКНЕЙМИ', 'Генерація варіантів', Icons.psychology, NicknameGenScreen(onLog: onLog)),
    _t(context, 'ТАЙМЛАЙН', 'Хронологія розслідування', Icons.timeline, TimelineScreen(onLog: onLog)),
    _t(context, 'СЕЙФ', 'Захищені паролі', Icons.lock, PasswordManagerScreen(onLog: onLog)),
  ]);
  Widget _t(ctx, t, s, i, scr) => Card(margin: const EdgeInsets.symmetric(vertical: 6), color: Colors.white.withOpacity(0.03), child: ListTile(leading: Icon(i, color: const Color(0xFFFFD700)), title: Text(t), subtitle: Text(s), onTap: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => scr))));
}

// --- DORKS (ПОВНИЙ ФУНКЦІОНАЛ) ---
class DorksScreen extends StatefulWidget {
  final Function(String) onLog;
  const DorksScreen({super.key, required this.onLog});
  @override
  State<DorksScreen> createState() => _DorksScreenState();
}
class _DorksScreenState extends State<DorksScreen> {
  final _t = TextEditingController();
  List<Map<String, String>> _d = [];
  void _gen() {
    String s = _t.text.trim(); if (s.isEmpty) return;
    setState(() { _d = [
      {'t': 'DOCS', 'd': 'PDF, DOC, TXT файли на сайті', 'q': 'site:$s ext:pdf OR ext:docx OR ext:txt'},
      {'t': 'DB', 'd': 'Дампи баз даних та SQL', 'q': 'site:$s ext:sql OR ext:db OR ext:bak'},
      {'t': 'ADMIN', 'd': 'Панелі входу адміністратора', 'q': 'site:$s inurl:admin OR inurl:login'},
      {'t': 'CAM', 'd': 'Відкриті вебкамери (CCTV)', 'q': 'site:$s inurl:view/view.shtml'},
      {'t': 'CONFIG', 'd': 'Файли конфігурації (.env, .conf)', 'q': 'site:$s ext:env OR ext:conf OR ext:xml'},
    ]; });
    widget.onLog("Dorks: $s");
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('GOOGLE_DORKS')),
    body: Column(children: [
      Padding(padding: const EdgeInsets.all(16), child: TextField(controller: _t, decoration: const InputDecoration(labelText: 'ВВЕДІТЬ ДОМЕН'))),
      ElevatedButton(onPressed: _gen, child: const Text('GENERATE')),
      Expanded(child: ListView.builder(itemCount: _d.length, itemBuilder: (c, i) => Card(margin: const EdgeInsets.all(8), child: ListTile(title: Text(_d[i]['t']!), subtitle: Text(_d[i]['d']!), trailing: IconButton(icon: const Icon(Icons.copy), onPressed: () => Clipboard.setData(ClipboardData(text: _d[i]['q']!))))))),
    ]),
  );
}

// --- СКАНЕР (З ФАЙЛАМИ ТА ЛАЗЕРОМ) ---
class ScannerScreen extends StatefulWidget {
  final Function(String) onLog;
  const ScannerScreen({super.key, required this.onLog});
  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}
class _ScannerScreenState extends State<ScannerScreen> with SingleTickerProviderStateMixin {
  final _c = TextEditingController();
  List<String> _r = [];
  late AnimationController _lCtrl;
  bool _isScanning = false;

  @override
  void initState() { super.initState(); _lCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2)); }
  @override
  void dispose() { _lCtrl.dispose(); super.dispose(); }

  void _load() async {
    FilePickerResult? r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['txt', 'docx', 'log']);
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
    setState(() { _isScanning = true; _r.clear(); });
    _lCtrl.repeat(); await Future.delayed(const Duration(seconds: 2));
    String t = _c.text;
    final ips = RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b').allMatches(t).map((m) => "IP: ${m.group(0)}").toList();
    final phs = RegExp(r'(?:\+380|\+7|8)[ \-\(\)]?\d{2,3}[ \-\(\)]?\d{3}[ \-]?\d{2}[ \-]?\d{2}').allMatches(t).map((m) => "PH: ${m.group(0)}").toList();
    final ems = RegExp(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}').allMatches(t).map((m) => "EM: ${m.group(0)}").toList();
    setState(() { _r = [...ips, ...phs, ...ems]; _isScanning = false; });
    _lCtrl.stop();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('RADAR_SCANNER'), actions: [IconButton(icon: const Icon(Icons.file_open), onPressed: _load)]),
    body: Column(children: [
      Stack(children: [
        Padding(padding: const EdgeInsets.all(16), child: TextField(controller: _c, maxLines: 5, decoration: const InputDecoration(labelText: 'INPUT_DATA'))),
        if (_isScanning) AnimatedBuilder(animation: _lCtrl, builder: (c, _) => Positioned(top: 20 + (_lCtrl.value * 120), left: 16, right: 16, child: Container(height: 2, color: Colors.redAccent, decoration: const BoxDecoration(boxShadow: [BoxShadow(color: Colors.red, blurRadius: 10)])))),
      ]),
      ElevatedButton(onPressed: _scan, child: const Text('RUN_SCAN')),
      Expanded(child: ListView.builder(itemCount: _r.length, itemBuilder: (c, i) => Card(color: _r[i].contains('+7') ? Colors.red.withOpacity(0.1) : Colors.white.withOpacity(0.05), child: ListTile(title: Text(_r[i], style: TextStyle(color: _r[i].contains('+7') ? Colors.redAccent : Colors.greenAccent)))))),
    ]),
  );
}

// --- EXIF (ПОВНИЙ АНАЛІЗ) ---
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
      final tags = await readExifFromBytes(await File(r.files.single.path!).readAsBytes());
      setState(() => _d = tags);
    }
  }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('EXIF')), body: Column(children: [
    ElevatedButton(onPressed: _pick, child: const Text('ОБРАТИ ФОТО')),
    Expanded(child: ListView.builder(itemCount: _d.length, itemBuilder: (c, i) => ListTile(title: Text(_d.keys.elementAt(i)), subtitle: Text(_d.values.elementAt(i).toString()))))
  ]));
}

// --- ІПН (РЕАЛЬНИЙ ДЕКОДЕР) ---
class IpnDecoderScreen extends StatefulWidget {
  final Function(String) onLog;
  const IpnDecoderScreen({super.key, required this.onLog});
  @override
  State<IpnDecoderScreen> createState() => _IpnDecoderScreenState();
}
class _IpnDecoderScreenState extends State<IpnDecoderScreen> {
  final _c = TextEditingController(); Map<String, String>? _res;
  void _decode() {
    String s = _c.text.trim(); if (s.length != 10) return;
    DateTime dob = DateTime(1899, 12, 31).add(Duration(days: int.parse(s.substring(0, 5))));
    int age = DateTime.now().year - dob.year;
    setState(() => _res = {'ДАТА': "${dob.day}.${dob.month}.${dob.year}", 'СТАТЬ': int.parse(s[8]) % 2 == 0 ? 'Жіноча' : 'Чоловіча', 'ВІК': "$age"});
  }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('IPN_BRUTE')), body: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
    TextField(controller: _c, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '10 ЦИФР')),
    ElevatedButton(onPressed: _decode, child: const Text('DECODE')),
    if (_res != null) ..._res!.entries.map((e) => ListTile(title: Text(e.key), subtitle: ScrambleText(text: e.value, style: const TextStyle(color: Colors.greenAccent))))
  ])));
}

// --- ФІНАНСИ (АЛГОРИТМ ЛУНА) ---
class FinValidatorScreen extends StatefulWidget {
  final Function(String) onLog;
  const FinValidatorScreen({super.key, required this.onLog});
  @override
  State<FinValidatorScreen> createState() => _FinValidatorScreenState();
}
class _FinValidatorScreenState extends State<FinValidatorScreen> {
  final _c = TextEditingController(); String _r = "";
  void _check() {
    String cc = _c.text.replaceAll(' ', ''); if (cc.isEmpty) return;
    int sum = 0; bool alt = false;
    for (int i = cc.length - 1; i >= 0; i--) {
      int n = int.parse(cc[i]); if (alt) { n *= 2; if (n > 9) n -= 9; }
      sum += n; alt = !alt;
    }
    setState(() => _r = sum % 10 == 0 ? "ВАЛІДНА КАРТКА" : "НЕ КОРЕКТНА");
  }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('FINANCE')), body: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
    TextField(controller: _c, decoration: const InputDecoration(labelText: 'НОМЕР КАРТКИ')),
    ElevatedButton(onPressed: _check, child: const Text('VAL_LUHN')),
    const SizedBox(height: 20), Text(_r, style: TextStyle(fontSize: 20, color: _r.contains('ВАЛІДНА') ? Colors.greenAccent : Colors.redAccent))
  ])));
}

// --- АВТО (РЕГІОНИ) ---
class AutoModuleScreen extends StatefulWidget {
  final Function(String) onLog;
  const AutoModuleScreen({super.key, required this.onLog});
  @override
  State<AutoModuleScreen> createState() => _AutoModuleScreenState();
}
class _AutoModuleScreenState extends State<AutoModuleScreen> {
  final _c = TextEditingController(); String _r = "";
  final Map<String, String> _reg = {'AA': 'м. Київ', 'KA': 'м. Київ', 'BC': 'Львівська обл', 'HC': 'Львівська обл', 'AE': 'Дніпро', 'KE': 'Дніпро'};
  void _check() {
    String s = _c.text.trim().toUpperCase(); if (s.length < 2) return;
    setState(() => _r = _reg[s.substring(0, 2)] ?? "Невідомий регіон України");
  }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('AUTO_PLATES')), body: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
    TextField(controller: _c, decoration: const InputDecoration(labelText: 'НОМЕР (АА1234ВВ)')),
    ElevatedButton(onPressed: _check, child: const Text('CHECK')),
    Text(_r, style: const TextStyle(fontSize: 20, color: Colors.greenAccent))
  ])));
}

// --- ТАЙМЛАЙН (ФУНКЦІОНАЛЬНИЙ) ---
class TimelineScreen extends StatefulWidget {
  final Function(String) onLog;
  const TimelineScreen({super.key, required this.onLog});
  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}
class _TimelineScreenState extends State<TimelineScreen> {
  List<Map<String, String>> _e = [];
  void _add() {
    final dC = TextEditingController(), tC = TextEditingController();
    showDialog(context: context, builder: (c) => AlertDialog(backgroundColor: Colors.black, title: const Text('НОВА ПОДІЯ'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: dC, decoration: const InputDecoration(labelText: 'Дата')),
        TextField(controller: tC, decoration: const InputDecoration(labelText: 'Подія')),
      ]),
      actions: [ElevatedButton(onPressed: () { setState(() => _e.add({'d': dC.text, 't': tC.text})); Navigator.pop(c); }, child: const Text('ADD'))],
    ));
  }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('TIMELINE')), body: ListView.builder(itemCount: _e.length, itemBuilder: (c, i) => ListTile(leading: const Icon(Icons.circle, size: 12, color: Colors.blue), title: Text(_e[i]['d']!), subtitle: Text(_e[i]['t']!))), floatingActionButton: FloatingActionButton(onPressed: _add, child: const Icon(Icons.add)));
}

// --- НІКНЕЙМИ ---
class NicknameGenScreen extends StatefulWidget {
  final Function(String) onLog;
  const NicknameGenScreen({super.key, required this.onLog});
  @override
  State<NicknameGenScreen> createState() => _NicknameGenScreenState();
}
class _NicknameGenScreenState extends State<NicknameGenScreen> {
  final _c = TextEditingController(); List<String> _res = [];
  void _gen() { setState(() => _res = ["${_c.text}_sec", "the_${_c.text}", "${_c.text}_osint"]); }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('NICKS')), body: Column(children: [
    TextField(controller: _c, decoration: const InputDecoration(labelText: 'БАЗОВЕ СЛОВО')),
    ElevatedButton(onPressed: _gen, child: const Text('GEN')),
    Expanded(child: ListView.builder(itemCount: _res.length, itemBuilder: (c, i) => ListTile(title: Text(_res[i]))))
  ]));
}

// --- СЕЙФ ---
class PasswordManagerScreen extends StatefulWidget {
  final Function(String) onLog;
  const PasswordManagerScreen({super.key, required this.onLog});
  @override
  State<PasswordManagerScreen> createState() => _PasswordManagerScreenState();
}
class _PasswordManagerScreenState extends State<PasswordManagerScreen> {
  List<Map<String, String>> _v = [];
  void _add() {
    final sC = TextEditingController(), pC = TextEditingController();
    showDialog(context: context, builder: (c) => AlertDialog(backgroundColor: Colors.black, title: const Text('ЗАХИСТИТИ ПАРОЛЬ'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: sC, decoration: const InputDecoration(labelText: 'Сервіс')),
        TextField(controller: pC, decoration: const InputDecoration(labelText: 'Пароль')),
      ]),
      actions: [ElevatedButton(onPressed: () { setState(() => _v.add({'s': sC.text, 'p': pC.text})); Navigator.pop(c); }, child: const Text('SAFE'))],
    ));
  }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('VAULT_SECURE')), body: ListView.builder(itemCount: _v.length, itemBuilder: (c, i) => ListTile(title: Text(_v[i]['s']!), subtitle: Text(_v[i]['p']!))), floatingActionButton: FloatingActionButton(onPressed: _add, child: const Icon(Icons.security)));
}

class PDFViewerScreen extends StatelessWidget {
  final PDFDoc doc;
  const PDFViewerScreen({super.key, required this.doc});
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(doc.name)), body: PDFView(filePath: doc.path));
}
