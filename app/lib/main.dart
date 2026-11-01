import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

const dataUrls = [
  'https://cdn.jsdelivr.net/gh/304584987/novel-rank@main/data/latest.json',
  'https://fastly.jsdelivr.net/gh/304584987/novel-rank@main/data/latest.json',
  'https://ghfast.top/https://raw.githubusercontent.com/304584987/novel-rank/main/data/latest.json',
  'https://raw.githubusercontent.com/304584987/novel-rank/main/data/latest.json',
];

Future<dynamic> fetchJson(List<String> urls) async {
  for (final u in urls) {
    try {
      final r = await http.get(Uri.parse(u)).timeout(const Duration(seconds: 8));
      if (r.statusCode == 200) return jsonDecode(utf8.decode(r.bodyBytes));
    } catch (_) {}
  }
  throw 'all';
}
const freedomTemps = {'保守': 0.5, '中度（推荐）': 1.0, '大胆': 1.4};
const elementNames = {
  'protagonist': '① 主角与起点',
  'goldfinger': '② 金手指 / 核心设定',
  'goal': '③ 目标与动机',
  'obstacle': '④ 核心阻力',
  'hook': '⑤ 悬念钩子',
  'mainline': '⑥ 主线走向',
};

const ideaSystemPrompt = '你是资深网文策划。根据给出的同题材榜单作品（书名+故事核），提炼当下流行元素，借鉴但绝不照搬（不得沿用原书名、人名、具体设定组合），'
    '原创 3 个新的写作点子。只输出 JSON：{"ideas":[{"title":"","core":"","protagonist":"","goldfinger":"","goal":"","obstacle":"","hook":"","mainline":""}]}。'
    'core=故事核（必填）：一段话，先明确主角、目标、阻力和故事方向。六要素：protagonist=主角与起点（是谁、什么时代地方、人生节点）；goldfinger=金手指/核心设定；'
    'goal=目标与动机；obstacle=核心阻力（全书级）；hook=悬念钩子（全书谜团）；mainline=主线走向（一句话）。'
    '不适用的要素必须返回空字符串""：如纯爽文打怪升级、单元剧推进无全书悬念则 hook 为空；普通人无金手指则 goldfinger 为空；无全书级对手则 obstacle 为空。'
    '六要素必须与故事核内容一致，不得矛盾。';

void main() => runApp(MaterialApp(
    title: '小说榜单',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: Colors.orange, useMaterial3: true),
    home: const Shell()));

// ---------------- 设置 ----------------
class Settings {
  String baseUrl = 'https://api.deepseek.com';
  String model = 'deepseek-flash';
  String apiKey = '';
  String freedom = '中度（推荐）';
  static Future<Settings> load() async {
    final p = await SharedPreferences.getInstance();
    return Settings()
      ..baseUrl = p.getString('baseUrl') ?? 'https://api.deepseek.com'
      ..model = p.getString('model') ?? 'deepseek-flash'
      ..apiKey = p.getString('apiKey') ?? ''
      ..freedom = p.getString('freedom') ?? '中度（推荐）';
  }
  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('baseUrl', baseUrl);
    await p.setString('model', model);
    await p.setString('apiKey', apiKey);
    await p.setString('freedom', freedom);
  }
}

// ---------------- 点子存储 ----------------
class IdeaStore {
  static Future<List<Map<String, dynamic>>> all() async {
    final p = await SharedPreferences.getInstance();
    return (jsonDecode(p.getString('ideas') ?? '[]') as List).cast<Map<String, dynamic>>();
  }
  static Future<void> saveAll(List<Map<String, dynamic>> list) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('ideas', jsonEncode(list));
  }
  static Future<void> add(List<Map<String, dynamic>> ideas) async {
    final l = await all();
    l.insertAll(0, ideas);
    await saveAll(l);
  }
}

String ideaText(Map<String, dynamic> i) {
  final b = StringBuffer('【${i['title'] ?? ''}】\n故事核：${i['core'] ?? ''}\n');
  elementNames.forEach((k, n) {
    final v = (i[k] ?? '').toString().trim();
    if (v.isNotEmpty) b.write('$n：$v\n');
  });
  return b.toString();
}

Future<List<Map<String, dynamic>>> generateIdeas(Settings s, String site, String genre, List books) async {
  final user = StringBuffer('网站：$site\n题材：$genre\n榜单作品：\n');
  for (final b in books.take(30)) {
    final core = (b['core'] ?? b['intro'] ?? '').toString();
    user.write('- 《${b['title']}》：${core.length > 120 ? core.substring(0, 120) : core}\n');
  }
  final url = '${s.baseUrl.replaceAll(RegExp(r'/+$'), '')}/chat/completions';
  final r = await http.post(Uri.parse(url),
      headers: {'Authorization': 'Bearer ${s.apiKey}', 'Content-Type': 'application/json'},
      body: jsonEncode({
        'model': s.model,
        'temperature': freedomTemps[s.freedom] ?? 1.0,
        'response_format': {'type': 'json_object'},
        'messages': [
          {'role': 'system', 'content': ideaSystemPrompt},
          {'role': 'user', 'content': user.toString()},
        ],
      })).timeout(const Duration(seconds: 180));
  if (r.statusCode != 200) throw 'HTTP ${r.statusCode}: ${utf8.decode(r.bodyBytes)}';
  var content = jsonDecode(utf8.decode(r.bodyBytes))['choices'][0]['message']['content'] as String;
  final m = RegExp(r'\{[\s\S]*\}').firstMatch(content); // 兼容带 ```json 包裹的返回
  if (m != null) content = m.group(0)!;
  final ideas = (jsonDecode(content)['ideas'] as List).cast<Map<String, dynamic>>();
  final now = DateTime.now().toString().substring(0, 16);
  for (final i in ideas) { i['_site'] = site; i['_genre'] = genre; i['_time'] = now; }
  return ideas;
}

// ---------------- 主框架 ----------------
class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int tab = 0;
  final favKey = GlobalKey<_FavPageState>();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: tab, children: [const RankPage(), FavPage(key: favKey), const SettingsPage()]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) { setState(() => tab = i); if (i == 1) favKey.currentState?.reload(); },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.leaderboard), label: '榜单'),
          NavigationDestination(icon: Icon(Icons.lightbulb), label: '我的点子'),
          NavigationDestination(icon: Icon(Icons.settings), label: '设置'),
        ],
      ),
    );
  }
}

// ---------------- 榜单页 ----------------
class RankPage extends StatefulWidget {
  const RankPage({super.key});
  @override
  State<RankPage> createState() => _RankPageState();
}

class _RankPageState extends State<RankPage> {
  Map<String, dynamic>? data;
  String? error;
  int site = 0;
  String? genre; // null = 全部（按榜单展示）

  @override
  void initState() { super.initState(); load(); }

  Future<void> load() async {
    try {
      final d = await fetchJson(dataUrls);
      setState(() { data = d; error = null; });
    } catch (e) { setState(() => error = '榜单数据暂时加载不了 😢\n请检查网络（可以试试切换 WiFi / 流量），然后下拉或点重试。'); }
  }

  String g(b) => (b['genre'] ?? b['cat'] ?? '其他').toString();

  List genreBooks(Map s, String gen) {
    final seen = <String>{};
    final out = [];
    for (final l in s['lists'] as List) {
      for (final b in l['books'] as List) {
        if (g(b) == gen && seen.add('${b['title']}')) out.add({...b, '_list': l['name']});
      }
    }
    return out;
  }

  Widget bookTile(b, {String? extra}) => ListTile(
        leading: CircleAvatar(radius: 14, child: Text('${b['rank']}', style: const TextStyle(fontSize: 12))),
        title: Text('${b['title']}${b['author'] != null ? '  · ${b['author']}' : ''}'),
        subtitle: Text('${extra != null ? '[$extra] ' : ''}${b['core'] ?? (b['intro'] ?? '').toString().replaceAll('<br>', ' ')}',
            maxLines: 4, overflow: TextOverflow.ellipsis),
        onTap: b['url'] == null ? null : () => launchUrl(Uri.parse(b['url']), mode: LaunchMode.externalApplication),
      );

  @override
  Widget build(BuildContext context) {
    final sites = (data?['sites'] as List?) ?? [];
    final s = sites.isEmpty ? null : sites[site.clamp(0, sites.length - 1)];
    final lists = (s?['lists'] as List?) ?? [];
    final counts = <String, int>{};
    if (s != null) {
      final seen = <String>{};
      for (final l in lists) {
        for (final b in l['books'] as List) {
          if (seen.add('${b['title']}')) counts[g(b)] = (counts[g(b)] ?? 0) + 1;
        }
      }
    }
    final genres = counts.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    final gBooks = (s != null && genre != null) ? genreBooks(s, genre!) : [];
    return Scaffold(
      appBar: AppBar(
          title: Text(s == null ? '小说榜单' : '${s['name']}'),
          bottom: data == null ? null : PreferredSize(preferredSize: const Size.fromHeight(20),
              child: Text('更新：${data!['updated']}', style: const TextStyle(fontSize: 12)))),
      drawer: Drawer(child: ListView(children: [
        const DrawerHeader(child: Text('选择网站', style: TextStyle(fontSize: 20))),
        for (var i = 0; i < sites.length; i++)
          ListTile(title: Text(sites[i]['name']), selected: i == site,
              onTap: () { setState(() { site = i; genre = null; }); Navigator.pop(context); }),
      ])),
      floatingActionButton: genre == null ? null : FloatingActionButton.extended(
          icon: const Icon(Icons.auto_awesome),
          label: const Text('一键生成 3 个写作点子'),
          onPressed: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => IdeasPage(site: s['name'], genre: genre!, books: gBooks)))),
      body: RefreshIndicator(onRefresh: load, child: ListView(children: [
        if (error != null) Padding(padding: const EdgeInsets.all(16), child: Text(error!, style: const TextStyle(color: Colors.red))),
        if (data == null && error == null) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
        if (s != null) Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Wrap(spacing: 6, runSpacing: 4, children: [
            ChoiceChip(label: const Text('全部榜单'), selected: genre == null, onSelected: (_) => setState(() => genre = null)),
            for (final x in genres) ChoiceChip(label: Text('$x ${counts[x]}'), selected: genre == x,
                onSelected: (_) => setState(() => genre = x)),
          ]),
        ),
        if (s != null && genre == null) const Padding(padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text('💡 点上面任意一个题材，右下角会出现「一键生成 3 个写作点子」按钮', style: TextStyle(color: Colors.brown))),
        if (genre != null) ...[
          Padding(padding: const EdgeInsets.all(12),
              child: Text('「$genre」共 ${gBooks.length} 本（已合并本站各榜单去重）', style: const TextStyle(fontWeight: FontWeight.bold))),
          for (final b in gBooks) bookTile(b, extra: b['_list']),
          const SizedBox(height: 80),
        ] else
          for (final l in lists) ExpansionTile(
            initiallyExpanded: true,
            title: Text('${l['name']}', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: l['error'] != null ? const Text('抓取失败', style: TextStyle(color: Colors.red)) : null,
            children: [for (final b in (l['books'] as List).take(s?['key'] == 'jjwxc' ? 100 : 10)) bookTile(b)],
          ),
      ])),
    );
  }
}

// ---------------- 点子卡片 ----------------
class IdeaCard extends StatelessWidget {
  final Map<String, dynamic> idea;
  final VoidCallback? onDelete;
  const IdeaCard({super.key, required this.idea, this.onDelete});
  @override
  Widget build(BuildContext context) {
    final els = elementNames.entries.where((e) => (idea[e.key] ?? '').toString().trim().isNotEmpty);
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('${idea['title'] ?? ''}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
            IconButton(icon: const Icon(Icons.copy), tooltip: '复制全文', onPressed: () {
              Clipboard.setData(ClipboardData(text: ideaText(idea)));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制')));
            }),
            if (onDelete != null) IconButton(icon: const Icon(Icons.delete_outline), onPressed: onDelete),
          ]),
          if (idea['_genre'] != null) Text('${idea['_site']} · ${idea['_genre']} · ${idea['_time']}',
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 6),
          const Text('故事核', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
          SelectableText('${idea['core'] ?? ''}'),
          const Divider(),
          const Text('六要素引导卡', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
          for (final e in els) Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.value, style: const TextStyle(fontWeight: FontWeight.w600)),
              SelectableText('${idea[e.key]}'),
            ])),
        ]),
      ),
    );
  }
}

// ---------------- 生成页 ----------------
class IdeasPage extends StatefulWidget {
  final String site, genre;
  final List books;
  const IdeasPage({super.key, required this.site, required this.genre, required this.books});
  @override
  State<IdeasPage> createState() => _IdeasPageState();
}

class _IdeasPageState extends State<IdeasPage> {
  List<Map<String, dynamic>> ideas = [];
  bool loading = false;
  String? error;
  bool needKey = false;

  @override
  void initState() { super.initState(); run(); }

  Future<void> run() async {
    final s = await Settings.load();
    if (s.apiKey.trim().isEmpty) { setState(() => needKey = true); return; }
    setState(() { loading = true; error = null; needKey = false; });
    try {
      final r = await generateIdeas(s, widget.site, widget.genre, widget.books);
      await IdeaStore.add(r);
      setState(() => ideas = r);
    } catch (e) {
      setState(() => error = '生成失败：$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.genre} · 写作点子'), actions: [
        TextButton.icon(onPressed: loading ? null : run, icon: const Icon(Icons.refresh), label: const Text('再生成')),
      ]),
      body: needKey
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('还没有填写模型 API Key'),
              const SizedBox(height: 12),
              FilledButton(onPressed: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage(standalone: true)));
                run();
              }, child: const Text('去设置')),
            ]))
          : loading
              ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  CircularProgressIndicator(), SizedBox(height: 12), Text('AI 正在构思，约 10-60 秒…')]))
              : ListView(children: [
                  if (error != null) Padding(padding: const EdgeInsets.all(16), child: Text(error!, style: const TextStyle(color: Colors.red))),
                  if (ideas.isNotEmpty) const Padding(padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: Text('已自动保存到「我的点子」', style: TextStyle(color: Colors.grey))),
                  for (final i in ideas) IdeaCard(idea: i),
                ]),
    );
  }
}

// ---------------- 我的点子 ----------------
class FavPage extends StatefulWidget {
  const FavPage({super.key});
  @override
  State<FavPage> createState() => _FavPageState();
}

class _FavPageState extends State<FavPage> {
  List<Map<String, dynamic>> list = [];
  @override
  void initState() { super.initState(); reload(); }
  Future<void> reload() async { final l = await IdeaStore.all(); if (mounted) setState(() => list = l); }
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('我的点子（${list.length}）')),
        body: RefreshIndicator(onRefresh: reload, child: list.isEmpty
            ? ListView(children: const [Padding(padding: EdgeInsets.all(40), child: Center(child: Text('还没有点子，去榜单页选个题材生成吧')))])
            : ListView(children: [
                for (var i = 0; i < list.length; i++) IdeaCard(idea: list[i], onDelete: () async {
                  list.removeAt(i); await IdeaStore.saveAll(list); setState(() {});
                }),
              ])),
      );
}

// ---------------- 设置页 ----------------
class SettingsPage extends StatefulWidget {
  final bool standalone;
  const SettingsPage({super.key, this.standalone = false});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Settings? s;
  final base = TextEditingController(), model = TextEditingController(), key = TextEditingController();
  bool hide = true;
  @override
  void initState() {
    super.initState();
    Settings.load().then((v) => setState(() { s = v; base.text = v.baseUrl; model.text = v.model; key.text = v.apiKey; }));
  }
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('设置 · 模型接入')),
        body: s == null ? const SizedBox() : ListView(padding: const EdgeInsets.all(16), children: [
          const Text('兼容 OpenAI 格式（/chat/completions）的任意模型服务'),
          const SizedBox(height: 12),
          TextField(controller: base, decoration: const InputDecoration(labelText: 'Base URL', hintText: 'https://api.deepseek.com')),
          TextField(controller: model, decoration: const InputDecoration(labelText: '模型名', hintText: 'deepseek-flash')),
          TextField(controller: key, obscureText: hide, decoration: InputDecoration(labelText: 'API Key',
              suffixIcon: IconButton(icon: Icon(hide ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => hide = !hide)))),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: s!.freedom,
            decoration: const InputDecoration(labelText: '发挥自由度'),
            items: [for (final k in freedomTemps.keys) DropdownMenuItem(value: k, child: Text('$k（temperature ${freedomTemps[k]}）'))],
            onChanged: (v) => s!.freedom = v!,
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: () async {
            s!..baseUrl = base.text.trim().isEmpty ? 'https://api.deepseek.com' : base.text.trim()
              ..model = model.text.trim().isEmpty ? 'deepseek-flash' : model.text.trim()
              ..apiKey = key.text.trim();
            await s!.save();
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存')));
            if (widget.standalone) Navigator.pop(context);
          }, child: const Text('保存')),
          const SizedBox(height: 8),
          const Text('Key 仅保存在本机（shared_preferences）。', style: TextStyle(color: Colors.grey, fontSize: 12)),
        ]),
      );
}
