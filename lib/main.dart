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

class PromptEnhancer {
  String name, desc, bestWith, warning, payload;
  bool isSelected;
  PromptEnhancer({required this.name, required this.desc, required this.bestWith, required this.warning, required this.payload, this.isSelected = false});
}

// --- ГОЛОВНИЙ ДОДАТОК ---
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
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: Colors.black,
      body: Image.asset('assets/splash.png', fit: BoxFit.cover, width: double.infinity, height: double.infinity));
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

  final List<String> categories = ['ФО', 'ЮО', 'ГЕОІНТ', 'МОНІТОРИНГ', 'ІНСТРУМЕНТИ', 'ДОКУМЕНТИ'];
  final Color uaYellow = const Color(0xFFFFD700);
  final Color uaBlue = const Color(0xFF0057B7);

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
        prompts = [Prompt(id: '1', title: 'Пошук ФО', category: 'ФО', content: 'Аналіз: {ПІБ}', isFavorite: true)];
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

  void _showSysInfo() {
    Map<String, int> stats = {'ФО': 0, 'ЮО': 0, 'ГЕОІНТ': 0, 'МОНІТОРИНГ': 0};
    for (var p in prompts) {
      if (stats.containsKey(p.category)) stats[p.category] = stats[p.category]! + 1;
    }

    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF040E22),
      shape: RoundedRectangleBorder(side: BorderSide(color: uaYellow)),
      title: const Text('SYS.INFO', style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold)),
      content: Column(
        mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('ЗАГАЛОМ ЗАПИСІВ:', style: TextStyle(color: Colors.white70, fontSize: 13)), Text('${prompts.length}', style: TextStyle(color: uaYellow, fontWeight: FontWeight.bold))]),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('ДОКУМЕНТІВ:', style: TextStyle(color: Colors.white70, fontSize: 13)), Text('${docs.length}', style: TextStyle(color: uaYellow, fontWeight: FontWeight.bold))]),
          const Divider(color: Colors.white24, height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('ФО:', style: TextStyle(color: Colors.white70)), Text('${stats['ФО']}', style: TextStyle(color: uaBlue, fontWeight: FontWeight.bold))]),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('ЮО:', style: TextStyle(color: Colors.white70)), Text('${stats['ЮО']}', style: TextStyle(color: uaBlue, fontWeight: FontWeight.bold))]),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('ГЕОІНТ:', style: TextStyle(color: Colors.white70)), Text('${stats['ГЕОІНТ']}', style: TextStyle(color: uaBlue, fontWeight: FontWeight.bold))]),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('МОНІТОРИНГ:', style: TextStyle(color: Colors.white70)), Text('${stats['МОНІТОРИНГ']}', style: TextStyle(color: uaBlue, fontWeight: FontWeight.bold))]),
        ],
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text('OK', style: TextStyle(color: uaYellow)))],
    ));
  }
  
  void _showAuditLog() {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF040E22),
      shape: RoundedRectangleBorder(side: BorderSide(color: uaBlue)),
      title: const Row(children: [Icon(Icons.terminal, color: Colors.white54), SizedBox(width: 10), Text('AUDIT_LOG', style: TextStyle(fontFamily: 'monospace'))]),
      content: SizedBox(
        width: double.maxFinite, height: 300,
        child: auditLogs.isEmpty 
          ? const Center(child: Text('NO RECORDS')) 
          : ListView.builder(itemCount: auditLogs.length, itemBuilder: (context, index) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(auditLogs[index], style: const TextStyle(color: Colors.greenAccent, fontFamily: 'monospace', fontSize: 11)))),
      ),
      actions: [
        TextButton(onPressed: () { setState(() { auditLogs.clear(); _save(); }); Navigator.pop(ctx); }, child: const Text('CLEAR', style: TextStyle(color: Colors.redAccent))),
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CLOSE', style: TextStyle(color: Colors.white54))),
      ],
    ));
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
          if (title.isNotEmpty && text.isNotEmpty) imported.add(Prompt(id: "${DateTime.now().millisecondsSinceEpoch}_${imported.length}", title: title, content: text.trim(), category: cat));
        }
        setState(() => prompts.addAll(imported));
        _logAction("SYS: Імпортовано TXT (${imported.length} записів)");
        _save();
      } catch (e) { _logAction("ERR: Помилка імпорту"); }
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
            dropdownColor: const Color(0xFF0A152F),
            value: ['ФО','ЮО','ГЕОІНТ','МОНІТОРИНГ'].contains(selectedCat) ? selectedCat : 'ФО',
            items: ['ФО','ЮО','ГЕОІНТ','МОНІТОРИНГ'].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
            onChanged: (val) => setDialogState(() => selectedCat = val!),
            decoration: const InputDecoration(labelText: 'КАТЕГОРІЯ'),
          ),
          const SizedBox(height: 10),
          TextField(controller: tCtrl, decoration: const InputDecoration(labelText: 'НАЗВА')),
          const SizedBox(height: 10),
          TextField(controller: cCtrl, maxLines: 4, decoration: const InputDecoration(labelText: 'КОНТЕНТ {VAR}')),
        ]),
        actions: [
          if (p != null) TextButton(onPressed: () async { 
            Navigator.pop(ctx);
            String originalTitle = p.title;
            setState(() { p.title = '██████████'; p.content = '████████████████████████████'; });
            HapticFeedback.heavyImpact();
            await Future.delayed(const Duration(milliseconds: 600));
            setState(() => prompts.remove(p)); 
            _logAction("Видалено: $originalTitle"); 
            _save(); 
          }, child: const Text('ВИДАЛИТИ', style: TextStyle(color: Colors.red))),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('СКАСУВАТИ', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: uaBlue),
            onPressed: () {
              setState(() {
                if (p == null) {
                  prompts.add(Prompt(id: DateTime.now().toString(), title: tCtrl.text, content: cCtrl.text, category: selectedCat));
                  _logAction("Створено: ${tCtrl.text}");
                } else {
                  p.title = tCtrl.text; p.content = cCtrl.text; p.category = selectedCat;
                  _logAction("Оновлено: ${tCtrl.text}");
                }
              });
              _save(); Navigator.pop(ctx);
            }, child: const Text('ЗБЕРЕГТИ', style: TextStyle(color: Colors.white))
          )
        ],
      )
    ));
  }

  void _pickPDF() async {
    FilePickerResult? r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    if (r != null && r.files.single.path != null) {
      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/${r.files.single.name}';
      await File(r.files.single.path!).copy(path);
      setState(() => docs.add(PDFDoc(id: DateTime.now().toString(), name: r.files.single.name, path: path)));
      _logAction("Додано PDF: ${r.files.single.name}");
      _save();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('UKR_OSINT', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2)),
        actions: [
          IconButton(icon: Icon(Icons.analytics, color: uaYellow), onPressed: _showSysInfo), 
          IconButton(icon: const Icon(Icons.receipt_long, color: Colors.white70), onPressed: _showAuditLog),
          IconButton(icon: Icon(Icons.download, color: uaBlue), onPressed: _importFromTxt),
        ],
        bottom: TabBar(controller: _tabController, isScrollable: true, tabs: categories.map((c) => Tab(text: c)).toList()),
      ),
      body: TabBarView(
        controller: _tabController,
        children: categories.map((cat) {
          if (cat == 'ІНСТРУМЕНТИ') return ToolsMenuScreen(onLog: _logAction);
          if (cat == 'ДОКУМЕНТИ') return _buildDocs();
          
          final items = prompts.where((p) => p.category == cat).toList();
          items.sort((a, b) => (b.isFavorite ? 1 : 0).compareTo(a.isFavorite ? 1 : 0));
          
          return ReorderableListView.builder(
            padding: const EdgeInsets.only(top: 10, bottom: 90),
            itemCount: items.length,
            onReorder: (oldIdx, newIdx) {
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
              return Card(
                key: ValueKey(p.id),
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                color: Colors.white.withOpacity(0.05),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: p.isFavorite ? uaYellow.withOpacity(0.5) : Colors.transparent)),
                child: ListTile(
                  leading: IconButton(icon: Icon(p.isFavorite ? Icons.star : Icons.star_border, color: p.isFavorite ? uaYellow : Colors.white24), onPressed: () { setState(() => p.isFavorite = !p.isFavorite); _save(); }),
                  title: Text(p.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(p.content, maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GenScreen(p: p, onLog: _logAction))),
                  onLongPress: () => _addOrEditPrompt(p: p),
                ),
              );
            }
          );
        }).toList(),
      ),
      floatingActionButton: _tabController.index == 4 ? null : FloatingActionButton(
        backgroundColor: uaBlue,
        onPressed: () => _tabController.index == 5 ? _pickPDF() : _addOrEditPrompt(),
        child: Icon(_tabController.index == 5 ? Icons.picture_as_pdf : Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildDocs() => ListView.builder(itemCount: docs.length, itemBuilder: (ctx, i) => Card(
    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), color: Colors.white.withOpacity(0.05),
    child: ListTile(
      title: Text(docs[i].name), leading: const Icon(Icons.file_copy, color: Colors.white54), 
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PDFViewerScreen(doc: docs[i]))),
      trailing: IconButton(icon: const Icon(Icons.delete_outline, color: Colors.white24), onPressed: () async {
        final doc = docs[i];
        setState(() => doc.name = '██████████');
        HapticFeedback.heavyImpact();
        await Future.delayed(const Duration(milliseconds: 500));
        setState(() => docs.removeAt(i));
        _save();
      }),
    ),
  ));
}

// --- ІНСТРУМЕНТИ ---
class ToolsMenuScreen extends StatelessWidget {
  final Function(String) onLog;
  const ToolsMenuScreen({super.key, required this.onLog});
  
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.only(top: 10, bottom: 20),
    children: [
      _t(context, 'ВАРІАНТИ НІКНЕЙМУ', 'Офлайн генерація логінів/пошт', Icons.psychology, NicknameGenScreen(onLog: onLog)),
      _t(context, 'DORKS', 'Кібер-конструктор Google запитів', Icons.travel_explore, DorksScreen(onLog: onLog)),
      _t(context, 'МЕНЕДЖЕР ПАРОЛІВ', 'Захищений крипто-блокнот', Icons.lock_outline, PasswordManagerScreen(onLog: onLog)),
      _t(context, 'СКАНЕР', 'Екстракція об\'єктів з тексту або DOC/TXT', Icons.radar, ScannerScreen(onLog: onLog)),
      _t(context, 'EXIF', 'Аналіз метаданих фотографії', Icons.image_search, ExifScreen(onLog: onLog)),
      _t(context, 'ТАЙМЛАЙН', 'Хронологія розслідування', Icons.timeline, TimelineScreen(onLog: onLog)),
    ]
  );
  
  Widget _t(ctx, t, s, i, scr) => Card(
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), color: Colors.white.withOpacity(0.03),
    child: ListTile(leading: Icon(i, color: const Color(0xFFFFD700)), title: Text(t, style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text(s), onTap: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => scr)))
  );
}

// --- МЕНЕДЖЕР ПАРОЛІВ ---
class PasswordManagerScreen extends StatefulWidget {
  final Function(String) onLog;
  const PasswordManagerScreen({super.key, required this.onLog});
  @override
  State<PasswordManagerScreen> createState() => _PasswordManagerScreenState();
}

class _PasswordManagerScreenState extends State<PasswordManagerScreen> {
  String? _masterPwd;
  bool _isUnlocked = false;
  List<Map<String, dynamic>> _vault = [];
  final _pwdCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadVault();
  }

  void _loadVault() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _masterPwd = prefs.getString('master_pwd');
      final v = prefs.getString('vault_data');
      if (v != null) _vault = List<Map<String, dynamic>>.from(json.decode(v));
    });
  }

  void _saveVault() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('vault_data', json.encode(_vault));
    await prefs.setString('master_pwd', _masterPwd!);
  }

  void _auth() {
    if (_pwdCtrl.text == _masterPwd) {
      setState(() { _isUnlocked = true; _pwdCtrl.clear(); });
      widget.onLog("SYS: Сховище паролів розблоковано");
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Невірний пароль!', style: TextStyle(color: Colors.red))));
    }
  }

  void _setupMaster() {
    if (_pwdCtrl.text.isNotEmpty) {
      setState(() { _masterPwd = _pwdCtrl.text; _isUnlocked = true; _pwdCtrl.clear(); });
      _saveVault();
      widget.onLog("SYS: Встановлено майстер-пароль");
    }
  }

  void _changeMaster() {
    final c = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF0A152F),
      title: const Text('ЗМІНА МАЙСТЕР-ПАРОЛЯ'),
      content: TextField(controller: c, obscureText: true, decoration: const InputDecoration(labelText: 'Новий пароль')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('СКАСУВАТИ')),
        ElevatedButton(onPressed: () {
          if (c.text.isNotEmpty) {
            setState(() => _masterPwd = c.text);
            _saveVault();
            widget.onLog("SYS: Майстер-пароль змінено");
          }
          Navigator.pop(ctx);
        }, child: const Text('ЗБЕРЕГТИ'))
      ],
    ));
  }

  void _addRecord() {
    final rC = TextEditingController(), lC = TextEditingController(), pC = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF0A152F),
      title: const Text('НОВИЙ ЗАПИС'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: rC, decoration: const InputDecoration(labelText: 'Ресурс (напр. Telegram)')),
        const SizedBox(height: 10),
        TextField(controller: lC, decoration: const InputDecoration(labelText: 'Логін / Email')),
        const SizedBox(height: 10),
        TextField(controller: pC, decoration: const InputDecoration(labelText: 'Пароль')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('СКАСУВАТИ')),
        ElevatedButton(onPressed: () {
          if (rC.text.isNotEmpty) {
            setState(() => _vault.add({'res': rC.text, 'log': lC.text, 'pwd': pC.text}));
            _saveVault();
          }
          Navigator.pop(ctx);
        }, child: const Text('ДОДАТИ'))
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_masterPwd == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('СЕКРЕТНЕ СХОВИЩЕ')),
        body: Padding(padding: const EdgeInsets.all(20), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.shield, size: 80, color: Color(0xFF0057B7)),
          const SizedBox(height: 20),
          const Text('Встановіть Майстер-Пароль для захисту', textAlign: TextAlign.center),
          const SizedBox(height: 20),
          TextField(controller: _pwdCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Майстер-пароль')),
          const SizedBox(height: 10),
          ElevatedButton(style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50), backgroundColor: const Color(0xFFFFD700)), onPressed: _setupMaster, child: const Text('ЗБЕРЕГТИ', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)))
        ])),
      );
    }

    if (!_isUnlocked) {
      return Scaffold(
        appBar: AppBar(title: const Text('СЕКРЕТНЕ СХОВИЩЕ')),
        body: Padding(padding: const EdgeInsets.all(20), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.lock, size: 80, color: Colors.white54),
          const SizedBox(height: 20),
          TextField(controller: _pwdCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Введіть пароль')),
          const SizedBox(height: 10),
          ElevatedButton(style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50), backgroundColor: const Color(0xFF0057B7)), onPressed: _auth, child: const Text('РОЗБЛОКУВАТИ', style: TextStyle(color: Colors.white)))
        ])),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('СХОВИЩЕ ПАРОЛІВ'), actions: [IconButton(icon: const Icon(Icons.key, color: Color(0xFFFFD700)), onPressed: _changeMaster)]),
      body: _vault.isEmpty 
        ? const Center(child: Text('Сховище порожнє', style: TextStyle(color: Colors.white54))) 
        : ListView.builder(itemCount: _vault.length, itemBuilder: (ctx, i) {
            final item = _vault[i];
            return Card(
              color: Colors.white.withOpacity(0.05), margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: ExpansionTile(
                title: Text(item['res'], style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.greenAccent)),
                subtitle: Text(item['log']),
                children: [
                  ListTile(
                    title: Text(item['pwd'], style: const TextStyle(fontFamily: 'monospace')),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(icon: const Icon(Icons.copy, color: Colors.white54), onPressed: () {
                        Clipboard.setData(ClipboardData(text: item['pwd']));
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Пароль скопійовано')));
                      }),
                      IconButton(icon: const Icon(Icons.delete, color: Colors.redAccent), onPressed: () async {
                        setState(() { _vault[i]['res'] = '██████████'; _vault[i]['log'] = '██████████'; _vault[i]['pwd'] = '██████████'; });
                        HapticFeedback.heavyImpact();
                        await Future.delayed(const Duration(milliseconds: 500));
                        setState(() => _vault.removeAt(i));
                        _saveVault();
                      }),
                    ]),
                  )
                ],
              ),
            );
          }),
      floatingActionButton: FloatingActionButton(backgroundColor: const Color(0xFF0057B7), onPressed: _addRecord, child: const Icon(Icons.add, color: Colors.white)),
    );
  }
}

// --- ВАРІАНТИ НІКНЕЙМУ ---
class NicknameGenScreen extends StatefulWidget {
  final Function(String) onLog;
  final String? initialQuery;
  const NicknameGenScreen({super.key, required this.onLog, this.initialQuery});
  @override
  State<NicknameGenScreen> createState() => _NicknameGenScreenState();
}

class _NicknameGenScreenState extends State<NicknameGenScreen> {
  final _c = TextEditingController();
  List<String> _res = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery != null) {
      _c.text = widget.initialQuery!.replaceAll('@', '');
      WidgetsBinding.instance.addPostFrameCallback((_) => _generate());
    }
  }

  void _generate() {
    String s = _c.text.trim().toLowerCase();
    if (s.isEmpty) return;
    setState(() {
      _res = [
        s, "${s}_osint", "${s}_private", "the_$s", "real_$s", "${s}2026",
        "$s.ua", "$s.dev", "$s.sec", "${s}_archive",
        "$s@gmail.com", "$s@proton.me", "$s@ukr.net", "$s.osint@mail.com"
      ];
    });
    widget.onLog("Згенеровано нікнейми для: $s");
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('ВАРІАНТИ НІКНЕЙМУ')),
    body: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
      TextField(controller: _c, decoration: const InputDecoration(labelText: 'ОСНОВНЕ СЛОВО / НІК')),
      const SizedBox(height: 10),
      ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0057B7), minimumSize: const Size(double.infinity, 50)),
        onPressed: _generate, child: const Text('ГЕНЕРУВАТИ ОФЛАЙН', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
      ),
      const SizedBox(height: 10),
      Expanded(child: ListView.builder(itemCount: _res.length, itemBuilder: (ctx, i) => Card(
        color: Colors.white.withOpacity(0.05),
        child: ListTile(
          title: Text(_res[i], style: const TextStyle(fontFamily: 'monospace', color: Colors.greenAccent)), 
          trailing: const Icon(Icons.copy, size: 18, color: Colors.white54), 
          onTap: () {
            Clipboard.setData(ClipboardData(text: _res[i]));
            HapticFeedback.lightImpact();
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: const Color(0xFF0057B7), content: Text('Скопійовано: ${_res[i]}'), duration: const Duration(seconds: 1)));
          }
        ),
      )))
    ])),
  );
}

// --- DORKS SCREEN (РОЗШИРЕНИЙ) ---
class DorksScreen extends StatefulWidget {
  final Function(String) onLog;
  final String? initialQuery;
  const DorksScreen({super.key, required this.onLog, this.initialQuery});
  @override
  State<DorksScreen> createState() => _DorksScreenState();
}

class _DorksScreenState extends State<DorksScreen> {
  final _t = TextEditingController();
  List<Map<String, String>> _d = [];
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery != null) {
      _t.text = widget.initialQuery!;
      WidgetsBinding.instance.addPostFrameCallback((_) => _gen());
    }
  }

  void _gen() {
    String s = _t.text.trim();
    if (s.isEmpty) return;
    
    for (var i = 0; i < _d.length; i++) {
       _listKey.currentState?.removeItem(0, (ctx, anim) => const SizedBox());
    }

    setState(() {
      _d = [
        {'title': 'Камери (CCTV)', 'desc': 'Пошук відкритих IP-камер', 'dork': 'site:$s inurl:view/view.shtml'},
        {'title': 'Документи (PDF, DOC)', 'desc': 'Відкриті звіти та документи', 'dork': 'site:$s ext:pdf OR ext:docx OR ext:txt'},
        {'title': 'Бази даних (SQL)', 'desc': 'Дампи баз даних', 'dork': 'site:$s ext:sql OR ext:db'},
        {'title': 'Резервні копії (Backups)', 'desc': 'Архіви сайтів', 'dork': 'site:$s ext:bak OR ext:zip OR ext:tar'},
        {'title': 'Відкриті директорії', 'desc': 'Серверні папки (Index of)', 'dork': 'site:$s intitle:"index of"'},
        {'title': 'Витоки паролів', 'desc': 'Файли зі згадкою паролів', 'dork': 'site:$s "password" ext:txt'},
        {'title': 'Адмін-панелі', 'desc': 'Точки входу для адміністраторів', 'dork': 'site:$s inurl:admin OR inurl:login'},
        {'title': 'Конфіги (Config)', 'desc': 'Файли конфігурації сервера', 'dork': 'site:$s ext:xml OR ext:conf OR ext:env'},
        {'title': 'Співробітники на LinkedIn', 'desc': 'Пошук профілів працівників', 'dork': 'site:linkedin.com/in "$s"'},
        {'title': 'Витоки коду (GitHub)', 'desc': 'Згадки домену в чужому коді', 'dork': 'site:github.com "$s"'},
        {'title': 'Приховані API', 'desc': 'Пошук відкритих API ендпоінтів', 'dork': 'site:$s inurl:api'},
      ];
    });

    widget.onLog("Dorks згенеровано для: $s");

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
        Padding(padding: const EdgeInsets.all(16), child: TextField(controller: _t, decoration: const InputDecoration(labelText: 'ВВЕДІТЬ ДОМЕН (напр. target.com)'))),
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
              final item = _d[index];
              return SlideTransition(
                position: animation.drive(Tween(begin: const Offset(1, 0), end: Offset.zero).chain(CurveTween(curve: Curves.easeOutQuart))),
                child: FadeTransition(
                  opacity: animation,
                  child: Card(
                    color: Colors.white.withOpacity(0.05), margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: ListTile(
                      title: Text(item['title']!, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(item['desc']!, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                        const SizedBox(height: 4),
                        Text(item['dork']!, style: const TextStyle(fontFamily: 'monospace', color: Colors.greenAccent)),
                      ]),
                      trailing: const Icon(Icons.copy, color: Colors.white24),
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: item['dork']!));
                        HapticFeedback.mediumImpact();
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: const Color(0xFF0057B7), content: Text('СКОПІЙОВАНО: ${item['title']}'), duration: const Duration(seconds: 1)));
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

// --- СКАНЕР (З ІМПОРТОМ DOCX ХАКОМ ТА ПЕРЕХРЕСНИМ МЕНЮ) ---
class ScannerScreen extends StatefulWidget {
  final Function(String) onLog;
  const ScannerScreen({super.key, required this.onLog});
  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final _c = TextEditingController(); 
  List<String> _r = [];

  void _loadTxt() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom, 
      allowedExtensions: ['txt', 'doc', 'docx', 'csv', 'log']
    );
    
    if (result != null && result.files.single.path != null) {
      try {
        final file = File(result.files.single.path!);
        String content = '';
        final ext = result.files.single.extension?.toLowerCase();
        
        if (ext == 'txt' || ext == 'csv' || ext == 'log') {
          content = await file.readAsString();
        } else {
          // OSINT ХАК: Читаємо бінарник (doc/pdf) і витягуємо всі друковані символи
          final bytes = await file.readAsBytes();
          final chars = bytes.where((b) => (b >= 32 && b <= 126) || b == 10 || b == 13).toList();
          content = String.fromCharCodes(chars);
        }
        
        setState(() => _c.text = content);
        widget.onLog("Сканер: завантажено ${result.files.single.name}");
        _scan();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Помилка читання: $e')));
      }
    }
  }

  void _scan() {
    String text = _c.text;
    if (text.isEmpty) return;

    final ips = RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b').allMatches(text).map((m) => "IP: ${m.group(0)}").toList();
    final ems = RegExp(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}').allMatches(text).map((m) => "EMAIL: ${m.group(0)}").toList();
    final phones = RegExp(r'(?:\+380|\+7|8)[ \-\(\)]?\d{2,3}[ \-\(\)]?\d{3}[ \-]?\d{2}[ \-]?\d{2}').allMatches(text).map((m) => "PHONE: ${m.group(0)}").toList();
    final links = RegExp(r'(?:https?:\/\/)?(?:www\.)?(?:t\.me|instagram\.com|facebook\.com|vk\.com|x\.com|twitter\.com|tiktok\.com|linkedin\.com)\/[a-zA-Z0-9_.-]+').allMatches(text).map((m) => "SOCIAL: ${m.group(0)}").toList();
    final nicks = RegExp(r'(?:^|\s)(@[a-zA-Z0-9_]+)').allMatches(text).map((m) => "NICK: ${m.group(1)}").toList();

    setState(() => _r = [...ips, ...ems, ...phones, ...links, ...nicks]);
    widget.onLog("Сканер: знайдено ${_r.length} об'єктів");
    FocusScope.of(context).unfocus();
  }

  void _showCrossActions(String rawVal) {
    String val = rawVal.split(': ').last.trim();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0A152F),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Wrap(
        children: [
          Padding(padding: const EdgeInsets.all(16), child: Text('ДІЯ ДЛЯ: $val', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFFFD700)))),
          ListTile(leading: const Icon(Icons.copy, color: Colors.white), title: const Text('Копіювати'), onTap: () { Clipboard.setData(ClipboardData(text: val)); Navigator.pop(ctx); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Скопійовано'))); }),
          ListTile(leading: const Icon(Icons.travel_explore, color: Colors.greenAccent), title: const Text('Відправити в Dorks'), onTap: () { Navigator.pop(ctx); Navigator.push(context, MaterialPageRoute(builder: (_) => DorksScreen(onLog: widget.onLog, initialQuery: val))); }),
          ListTile(leading: const Icon(Icons.psychology, color: Color(0xFF0057B7)), title: const Text('Генерувати нікнейми'), onTap: () { Navigator.pop(ctx); Navigator.push(context, MaterialPageRoute(builder: (_) => NicknameGenScreen(onLog: widget.onLog, initialQuery: val))); }),
          const SizedBox(height: 20),
        ],
      )
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('ЕКСТРАКТОР АРТЕФАКТІВ'),
      actions: [IconButton(icon: const Icon(Icons.file_upload, color: Color(0xFFFFD700)), onPressed: _loadTxt, tooltip: 'Завантажити TXT/DOC')],
    ), 
    body: Column(children: [
      Padding(padding: const EdgeInsets.all(16), child: TextField(controller: _c, maxLines: 5, decoration: const InputDecoration(labelText: 'Вставте текст або завантажте файл'))), 
      ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0057B7), minimumSize: const Size(double.infinity, 50)),
        onPressed: _scan, child: const Text('СКАЙНУВАТИ ТЕКСТ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
      ), 
      const SizedBox(height: 10),
      Expanded(child: ListView.builder(itemCount: _r.length, itemBuilder: (ctx, i) => Card(
        color: Colors.white.withOpacity(0.05), margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: ListTile(
          title: Text(_r[i], style: const TextStyle(fontFamily: 'monospace', color: Colors.greenAccent)),
          onTap: () {
            Clipboard.setData(ClipboardData(text: _r[i].split(': ').last.trim()));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Скопійовано')));
          },
          trailing: IconButton(icon: const Icon(Icons.more_vert, color: Colors.white54), onPressed: () => _showCrossActions(_r[i])),
        )
      )))
    ])
  );
}

// --- EXIF SCREEN ---
class ExifScreen extends StatefulWidget {
  final Function(String) onLog;
  const ExifScreen({super.key, required this.onLog});
  @override
  State<ExifScreen> createState() => _ExifScreenState();
}

class _ExifScreenState extends State<ExifScreen> {
  Map<String, dynamic> _data = {};
  bool _isLoading = false;
  String _error = '';

  void _pick() async {
    setState(() { _isLoading = true; _error = ''; _data.clear(); });

    try {
      FilePickerResult? r = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
      if (r != null) {
        final bytes = r.files.single.bytes ?? await File(r.files.single.path!).readAsBytes();
        final tags = await readExifFromBytes(bytes);

        if (tags.isEmpty) {
          _error = 'Метадані відсутні (можливо, були видалені месенджером або соцмережею)';
        } else {
          _data = tags;
        }
        widget.onLog("EXIF: Аналіз файлу ${r.files.single.name}");
      }
    } catch (e) {
      _error = 'Помилка доступу до файлу. Спробуйте інше фото.';
      widget.onLog("ERR: Помилка EXIF");
    }

    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('EXIF АНАЛІЗАТОР')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0057B7), minimumSize: const Size(double.infinity, 50)),
              onPressed: _isLoading ? null : _pick,
              child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text('ОБРАТИ ФОТО З ГАЛЕРЕЇ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
          if (_error.isNotEmpty) Padding(padding: const EdgeInsets.all(16), child: Text(_error, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
          Expanded(
            child: ListView.builder(
              itemCount: _data.length,
              itemBuilder: (ctx, i) {
                final key = _data.keys.elementAt(i);
                final value = _data[key].toString();
                return Card(
                  color: Colors.white.withOpacity(0.05), margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: ListTile(
                    title: Text(key, style: const TextStyle(fontSize: 12, color: Colors.white70)),
                    subtitle: Text(value, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.greenAccent)),
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: "$key: $value"));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Дані скопійовано')));
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// --- ТАЙМЛАЙН ---
class TimelineScreen extends StatefulWidget {
  final Function(String) onLog;
  const TimelineScreen({super.key, required this.onLog});
  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  List<Map<String, dynamic>> _events = [];

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  void _loadEvents() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('timeline_data');
    if (data != null) {
      setState(() => _events = List<Map<String, dynamic>>.from(json.decode(data)));
    }
  }

  void _saveEvents() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('timeline_data', json.encode(_events));
  }

  void _addEvent() {
    final dC = TextEditingController(), tC = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF0A152F), title: const Text('НОВА ПОДІЯ'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: dC, decoration: const InputDecoration(labelText: 'Дата / Час (напр. 24.02.2026)')),
        const SizedBox(height: 10),
        TextField(controller: tC, decoration: const InputDecoration(labelText: 'Подія / Опис')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('СКАСУВАТИ')),
        ElevatedButton(onPressed: () {
          if (dC.text.isNotEmpty && tC.text.isNotEmpty) {
            setState(() => _events.add({'date': dC.text, 'title': tC.text}));
            _saveEvents();
            widget.onLog("Таймлайн: додано подію");
          }
          Navigator.pop(ctx);
        }, child: const Text('ДОДАТИ'))
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ХРОНОЛОГІЯ')),
      body: _events.isEmpty 
        ? const Center(child: Text('Таймлайн порожній', style: TextStyle(color: Colors.white54)))
        : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _events.length,
            itemBuilder: (ctx, i) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(children: [
                    Container(width: 12, height: 12, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFFFD700))),
                    if (i != _events.length - 1) Container(width: 2, height: 60, color: Colors.white24),
                  ]),
                  const SizedBox(width: 16),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_events[i]['date'], style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0057B7))),
                    const SizedBox(height: 4),
                    Text(_events[i]['title'], style: const TextStyle(color: Colors.white)),
                    const SizedBox(height: 20),
                  ]))
                ],
              );
            },
          ),
      floatingActionButton: FloatingActionButton(backgroundColor: const Color(0xFFFFD700), onPressed: _addEvent, child: const Icon(Icons.add, color: Colors.black)),
    );
  }
}

// --- GEN SCREEN З ТУРБО-АНІМАЦІЄЮ ТА КОЛЬОРОВИМ КОДОМ ---
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
  
  List<TextSpan> _fullSpans = [];
  int _totalChars = 0;
  int _currentChar = 0;
  Timer? _typeTimer;
  
  final List<PromptEnhancer> _enhancers = [
    PromptEnhancer(name: 'CoT (Chain of Thought)', desc: 'Покрокове мислення.', bestWith: 'Складні завдання.', warning: 'Довга відповідь.', payload: 'Пояснюй хід думок крок за кроком (Step-by-step).'),
    PromptEnhancer(name: 'ToT (Tree of Thoughts)', desc: 'Генерація гіпотез.', bestWith: 'Аналітика.', warning: 'Не сумісно з CoT.', payload: 'Розглянь 3 гіпотези та обери найбільш вірогідну.'),
    PromptEnhancer(name: 'Експертна Роль', desc: 'Задає професійний тон.', bestWith: 'OSINT запити.', warning: 'Немає.', payload: 'Дій як старший аналітик розвідки.'),
    PromptEnhancer(name: 'BLUF (Звіт)', desc: 'Головний висновок спочатку.', bestWith: 'Звіти.', warning: 'Скорочує опис.', payload: 'Використовуй формат BLUF (Bottom Line Up Front).'),
    PromptEnhancer(name: 'Саморефлексія', desc: 'Пошук власних помилок.', bestWith: 'Фактчекінг.', warning: 'Довга генерація.', payload: 'Критично оціни відповідь та знайди можливі помилки.'),
    PromptEnhancer(name: 'Жорстке Форматування', desc: 'Видача кодом.', bestWith: 'Екстракція.', warning: 'Тільки JSON.', payload: 'Поверни результат ВИКЛЮЧНО у форматі валідного JSON.'),
  ];

  @override
  void initState() {
    super.initState();
    final reg = RegExp(r'\{([^}]+)\}');
    for (var m in reg.allMatches(widget.p.content)) { _ctrls[m.group(1)!] = TextEditingController(); }
  }

  @override
  void dispose() {
    _typeTimer?.cancel();
    super.dispose();
  }

  void _compileAndType() {
    _fullSpans.clear();
    _totalChars = 0;
    _currentChar = 0;

    String template = widget.p.content;
    int lastIndex = 0;
    final reg = RegExp(r'\{([^}]+)\}');
    
    // Парсинг базового тексту (Зелений) та змінних (Червоний)
    for (var m in reg.allMatches(template)) {
      if (m.start > lastIndex) {
        String text = template.substring(lastIndex, m.start);
        _fullSpans.add(TextSpan(text: text, style: const TextStyle(color: Colors.greenAccent)));
        _totalChars += text.length;
      }
      String key = m.group(1)!;
      String val = _ctrls[key]?.text ?? '';
      if (val.isEmpty) val = '{$key}';
      
      _fullSpans.add(TextSpan(text: val, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)));
      _totalChars += val.length;
      lastIndex = m.end;
    }
    
    if (lastIndex < template.length) {
      String text = template.substring(lastIndex);
      _fullSpans.add(TextSpan(text: text, style: const TextStyle(color: Colors.greenAccent)));
      _totalChars += text.length;
    }

    // Додавання підсилень (Жовтий)
    final selected = _enhancers.where((e) => e.isSelected).toList();
    if (selected.isNotEmpty) {
      String hdr = "\n\n### СИСТЕМНІ ІНСТРУКЦІЇ:\n";
      _fullSpans.add(TextSpan(text: hdr, style: const TextStyle(color: Colors.yellow, fontWeight: FontWeight.bold)));
      _totalChars += hdr.length;
      
      for (var e in selected) {
        String t = "- ${e.payload}\n";
        _fullSpans.add(TextSpan(text: t, style: const TextStyle(color: Colors.yellow)));
        _totalChars += t.length;
      }
    }

    setState(() => _isCompiled = true);
    widget.onLog("Компіляція: ${widget.p.title}");
    FocusScope.of(context).unfocus();

    // ТУРБО-Аніміція (По 5 символів кожні 2 мілісекунди)
    _typeTimer?.cancel();
    _typeTimer = Timer.periodic(const Duration(milliseconds: 2), (t) {
      setState(() {
        _currentChar += 5;
        if (_currentChar >= _totalChars) {
          _currentChar = _totalChars;
          t.cancel();
        }
      });
    });
  }

  // Динамічний білдер кольорового тексту для анімації
  List<TextSpan> _getVisibleSpans() {
    List<TextSpan> result = [];
    int current = 0;
    for (var span in _fullSpans) {
      String text = span.text ?? '';
      if (current + text.length <= _currentChar) {
        result.add(span);
        current += text.length;
      } else {
        int remaining = _currentChar - current;
        if (remaining > 0) result.add(TextSpan(text: text.substring(0, remaining), style: span.style));
        break;
      }
    }
    if (_currentChar < _totalChars) result.add(const TextSpan(text: '_', style: TextStyle(color: Colors.white)));
    return result;
  }

  String get _rawText => _fullSpans.map((s) => s.text).join();

  void _showEnhanceMenu() {
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: const Color(0xFF0A152F),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Container(
          padding: const EdgeInsets.only(top: 20, left: 16, right: 16, bottom: 40),
          height: MediaQuery.of(context).size.height * 0.75,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('ТАКТИЧНЕ ПІДСИЛЕННЯ (PROMPT ENGINEERING)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFFFFD700))),
              const SizedBox(height: 10),
              Expanded(
                child: ListView.builder(
                  itemCount: _enhancers.length,
                  itemBuilder: (ctx, i) {
                    final e = _enhancers[i];
                    return Card(
                      color: Colors.white.withOpacity(0.05), margin: const EdgeInsets.only(bottom: 10),
                      child: CheckboxListTile(
                        activeColor: const Color(0xFF0057B7), checkColor: Colors.white,
                        title: Text(e.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(e.desc, style: const TextStyle(fontSize: 12)),
                          Text('КРАЩЕ ДЛЯ: ${e.bestWith}', style: const TextStyle(fontSize: 10, color: Colors.greenAccent)),
                        ]),
                        value: e.isSelected,
                        onChanged: (val) { setModalState(() => e.isSelected = val!); if (_isCompiled) _compileAndType(); },
                      ),
                    );
                  },
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0057B7), minimumSize: const Size(double.infinity, 50)),
                onPressed: () => Navigator.pop(ctx), child: const Text('АПЛАЙ (ЗАСТОСУВАТИ)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
              )
            ],
          ),
        )
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.p.title)),
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        if (!_isCompiled) ...[
          ..._ctrls.keys.map((k) => Padding(padding: const EdgeInsets.only(bottom: 8.0), child: TextField(controller: _ctrls[k], decoration: InputDecoration(labelText: k)))),
          const SizedBox(height: 10),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0057B7), minimumSize: const Size(double.infinity, 50)),
            onPressed: _compileAndType, child: const Text('КОМПІЛЮВАТИ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
          ),
        ] else ...[
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0A152F), side: const BorderSide(color: Color(0xFFFFD700)), minimumSize: const Size(double.infinity, 50)),
            onPressed: _showEnhanceMenu, icon: const Icon(Icons.flash_on, color: Color(0xFFFFD700)), label: const Text('ТАКТИЧНЕ ПІДСИЛЕННЯ ПРОМПТУ', style: TextStyle(color: Color(0xFFFFD700), fontWeight: FontWeight.bold))
          ),
          const SizedBox(height: 10),
          Expanded(child: Container(
            width: double.infinity, padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8), border: Border.all(color: _enhancers.any((e) => e.isSelected) ? const Color(0xFF0057B7) : Colors.transparent)),
            child: SingleChildScrollView(
              child: SelectableText.rich(TextSpan(children: _getVisibleSpans()), style: const TextStyle(fontFamily: 'monospace'))
            )
          )),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: ElevatedButton(onPressed: () { setState(() { _isCompiled = false; for (var e in _enhancers) { e.isSelected = false; } }); _typeTimer?.cancel(); }, child: const Text('РЕСЕТ'))),
            const SizedBox(width: 10),
            Expanded(child: ElevatedButton(onPressed: () { Clipboard.setData(ClipboardData(text: _rawText)); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Скопійовано'))); }, child: const Text('COPY'))),
            const SizedBox(width: 10),
            Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFD700)), onPressed: () => Share.share(_rawText), child: const Text('SHARE', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold))))
          ])
        ]
      ])
    )
  );
}

// --- PDF ---
class PDFViewerScreen extends StatelessWidget {
  final PDFDoc doc;
  const PDFViewerScreen({super.key, required this.doc});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(doc.name)), body: PDFView(filePath: doc.path));
}
