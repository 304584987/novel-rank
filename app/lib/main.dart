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
    'core=故事核（必填）：一段话，讲清主角、想要什么、难在哪、故事往哪走。protagonist=主角与起点（必填）；mainline=主线走向（必填，一句话）。'
    'goldfinger=金手指/核心设定、goal=目标与动机、obstacle=核心阻力、hook=悬念钩子，这四项是可选的：按故事实际需要，可以全有、部分有、或者全都没有，不需要就返回空字符串""。'
    '绝不要硬塞金手指、系统、异能、重生外挂；现实向、情感向、轻日常、纯爽文单元剧都完全可以没有金手指；没有全书谜团就不写 hook；没有全书级对手就不写 obstacle。'
    '3 个点子必须彼此差异明显：故事类型与基调不同，且至少 1 个完全没有金手指/超自然设定，各点子包含的可选要素组合也尽量不同。'
    '所有要素必须与故事核一致，不得矛盾。';

void main() => runApp(MaterialApp(
    title: '小说榜单',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: Colors.orange, useMaterial3: true),
    home: const Shell()));

// ---------------- 模型厂商预设 ----------------
class ModelChoice {
  final String id;
  final String label;
  const ModelChoice(this.id, this.label);
}

class VendorPreset {
  final String id;
  final String name;
  final String baseUrl;
  final String keyHint;
  final List<ModelChoice> models;
  final String tip;
  const VendorPreset({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.keyHint,
    required this.models,
    required this.tip,
  });
}

const vendorPresets = [
  VendorPreset(
    id: 'deepseek',
    name: 'DeepSeek',
    baseUrl: 'https://api.deepseek.com',
    keyHint: '在 deepseek.com 开通 API Key',
    models: [
      ModelChoice('deepseek-flash', 'DeepSeek Flash（推荐，便宜快）'),
      ModelChoice('deepseek-v4-pro', 'DeepSeek V4 Pro（更强）'),
    ],
    tip: '默认推荐。模型名一般直接填 deepseek-flash 即可。',
  ),
  VendorPreset(
    id: 'doubao',
    name: '豆包（火山方舟）',
    baseUrl: 'https://ark.cn-beijing.volces.com/api/v3',
    keyHint: '在火山方舟控制台开通 API Key',
    models: [
      ModelChoice('doubao-seed-2-1-lite-260915', '豆包 Lite（便宜）'),
      ModelChoice('doubao-seed-2-1-turbo-260628', '豆包 Turbo'),
      ModelChoice('doubao-seed-2-1-pro-260915', '豆包 Pro'),
      ModelChoice('doubao-seed-evolving', '豆包 Evolving'),
      ModelChoice('doubao-seed-character-260628', '豆包 Character（角色向）'),
    ],
    tip: '若控制台要求填「推理接入点 ID」，把那个 ID 填到下面的「模型名」里即可（可覆盖预设）。',
  ),
  VendorPreset(
    id: 'custom',
    name: '自定义',
    baseUrl: '',
    keyHint: '任意兼容 OpenAI 格式的 Key',
    models: [],
    tip: '自己填接口地址和模型名，例如智谱、千问等。',
  ),
];

String detectVendorId(String baseUrl) {
  final u = baseUrl.toLowerCase();
  if (u.contains('deepseek.com')) return 'deepseek';
  if (u.contains('volces.com') || u.contains('ark.cn-beijing')) return 'doubao';
  return 'custom';
}

// ---------------- 设置 ----------------
class Settings {
  String vendor = 'deepseek';
  String baseUrl = 'https://api.deepseek.com';
  String model = 'deepseek-flash';
  String apiKey = '';
  String freedom = '中度（推荐）';
  static Future<Settings> load() async {
    final p = await SharedPreferences.getInstance();
    final base = p.getString('baseUrl') ?? 'https://api.deepseek.com';
    final vendor = p.getString('vendor') ?? detectVendorId(base);
    return Settings()
      ..vendor = vendor
      ..baseUrl = base
      ..model = p.getString('model') ?? 'deepseek-flash'
      ..apiKey = p.getString('apiKey') ?? ''
      ..freedom = p.getString('freedom') ?? '中度（推荐）';
  }
  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('vendor', vendor);
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
  final decoded = jsonDecode(content);
  final rawList = decoded is List ? decoded : ((decoded is Map ? decoded['ideas'] : null) as List? ?? const []);
  final ideas = <Map<String, dynamic>>[];
  for (final x in rawList) {
    if (x is! Map) continue;
    final m = <String, dynamic>{};
    x.forEach((k, v) => m['$k'] = v == null ? '' : (v is String ? v.trim() : '$v'));
    for (final k in ['title', 'core', ...elementNames.keys]) { m.putIfAbsent(k, () => ''); }
    if ((m['core'] as String).isEmpty && (m['title'] as String).isEmpty) continue;
    ideas.add(m);
  }
  if (ideas.isEmpty) throw '模型没返回可用的点子，请再生成一次';
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
    final raw = (data?['sites'] as List?) ?? [];
    final sites = raw.isEmpty ? [] : [
      {'name': '全站合并', 'key': 'all', 'lists': [
        for (final x in raw) for (final l in x['lists'] as List) {...l, 'name': '${x['name']}·${l['name']}'}
      ]},
      ...raw,
    ];
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
              child: Text('「$genre」共 ${gBooks.length} 本（已合并${s?['key'] == 'all' ? '全部网站' : '本站各'}榜单去重）', style: const TextStyle(fontWeight: FontWeight.bold))),
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
  bool testing = false;
  String? testResult;

  Future<void> testKey() async {
    final b = base.text.trim().replaceAll(RegExp(r'/+$'), '');
    final m = model.text.trim();
    final k = key.text.trim();
    if (b.isEmpty || m.isEmpty || k.isEmpty) { setState(() => testResult = '❌ 请先把接口地址、模型名、API Key 都填上'); return; }
    setState(() { testing = true; testResult = '测试中…'; });
    final sw = Stopwatch()..start();
    String res;
    try {
      final r = await http.post(Uri.parse('$b/chat/completions'),
          headers: {'Authorization': 'Bearer $k', 'Content-Type': 'application/json'},
          body: jsonEncode({'model': m, 'max_tokens': 5, 'messages': [{'role': 'user', 'content': '你好'}]}))
          .timeout(const Duration(seconds: 15));
      final secs = (sw.elapsedMilliseconds / 1000).toStringAsFixed(1);
      final body = utf8.decode(r.bodyBytes);
      if (r.statusCode == 200) {
        String used = m;
        try { used = (jsonDecode(body)['model'] ?? m).toString(); } catch (_) {}
        res = '✅ 可以用（模型：$used，耗时 $secs 秒）';
      } else {
        String msg = body;
        try { final j = jsonDecode(body); msg = (j['error']?['message'] ?? j['message'] ?? body).toString(); } catch (_) {}
        if (msg.length > 150) msg = '${msg.substring(0, 150)}…';
        final low = msg.toLowerCase();
        String why;
        if (r.statusCode == 402 || low.contains('insufficient') || low.contains('balance') || msg.contains('余额') || low.contains('arrearage')) {
          why = '账户余额不足，请先充值';
        } else if (r.statusCode == 401 || r.statusCode == 403) {
          why = 'Key 不对，或者这个 Key 没有权限';
        } else if (r.statusCode == 404) {
          why = '模型名或接口地址不对';
          if (detectVendorId(b) == 'doubao') why += '（豆包可能要填「推理接入点 ID」，或先在火山方舟控制台开通这个模型）';
        } else if (r.statusCode == 429) {
          why = '请求太频繁，或者额度用完了，稍后再试';
        } else if (r.statusCode == 400 && detectVendorId(b) == 'doubao' && (low.contains('model') || low.contains('endpoint'))) {
          why = '模型名不对（豆包可能要填「推理接入点 ID」，或先开通这个模型）';
        } else {
          why = '服务器返回错误（状态码 ${r.statusCode}）';
        }
        res = '❌ $why\n服务器说：$msg';
      }
    } catch (e) {
      res = '❌ 网络连不上或超时（15 秒），请检查网络和接口地址';
    }
    if (!mounted) return;
    setState(() { testing = false; testResult = res; });
  }

  VendorPreset get preset {
    final id = s?.vendor ?? 'deepseek';
    return vendorPresets.firstWhere((v) => v.id == id, orElse: () => vendorPresets.first);
  }

  void applyVendor(String id) {
    final v = vendorPresets.firstWhere((x) => x.id == id, orElse: () => vendorPresets.first);
    setState(() {
      s!.vendor = v.id;
      if (v.baseUrl.isNotEmpty) {
        base.text = v.baseUrl;
        s!.baseUrl = v.baseUrl;
      }
      if (v.models.isNotEmpty) {
        final keep = v.models.any((m) => m.id == model.text.trim());
        if (!keep) {
          model.text = v.models.first.id;
          s!.model = v.models.first.id;
        }
      }
    });
  }

  @override
  void initState() {
    super.initState();
    Settings.load().then((v) => setState(() {
      s = v;
      base.text = v.baseUrl;
      model.text = v.model;
      key.text = v.apiKey;
    }));
  }

  @override
  void dispose() {
    base.dispose();
    model.dispose();
    key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('设置 · 模型接入')),
        body: s == null
            ? const SizedBox()
            : ListView(padding: const EdgeInsets.all(16), children: [
                const Text('先选厂商，再选模型。也可以自己改接口地址和模型名。', style: TextStyle(fontSize: 14)),
                const SizedBox(height: 12),
                const Text('厂商 / 预设', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final v in vendorPresets)
                    ChoiceChip(
                      label: Text(v.name),
                      selected: s!.vendor == v.id,
                      onSelected: (_) => applyVendor(v.id),
                    ),
                ]),
                const SizedBox(height: 8),
                Text(preset.tip, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                if (preset.models.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text('推荐模型（点一下填入）', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final m in preset.models)
                      FilterChip(
                        label: Text(m.label),
                        selected: model.text.trim() == m.id,
                        onSelected: (_) => setState(() {
                          model.text = m.id;
                          s!.model = m.id;
                        }),
                      ),
                  ]),
                ],
                const SizedBox(height: 16),
                TextField(
                  controller: base,
                  decoration: InputDecoration(
                    labelText: '接口地址（Base URL）',
                    hintText: preset.baseUrl.isEmpty ? 'https://...' : preset.baseUrl,
                    helperText: '一般不用改；选厂商后会自动填好',
                  ),
                  onChanged: (t) {
                    final id = detectVendorId(t);
                    if (id != s!.vendor && id != 'custom') {
                      setState(() => s!.vendor = id);
                    } else if (id == 'custom' && s!.vendor != 'custom' && t.trim().isNotEmpty) {
                      // 用户手改成未知地址时，切到自定义，但不清模型
                      setState(() => s!.vendor = 'custom');
                    }
                  },
                ),
                TextField(
                  controller: model,
                  decoration: InputDecoration(
                    labelText: '模型名',
                    hintText: preset.models.isNotEmpty ? preset.models.first.id : '模型 ID 或接入点 ID',
                    helperText: s!.vendor == 'doubao'
                        ? '豆包也可填火山方舟「推理接入点 ID」'
                        : '例如 deepseek-flash',
                  ),
                ),
                TextField(
                  controller: key,
                  obscureText: hide,
                  decoration: InputDecoration(
                    labelText: 'API Key',
                    hintText: preset.keyHint,
                    helperText: '密钥只保存在你这台手机里',
                    suffixIcon: IconButton(
                      icon: Icon(hide ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => hide = !hide),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: s!.freedom,
                  decoration: const InputDecoration(labelText: '发挥自由度'),
                  items: [
                    for (final k in freedomTemps.keys)
                      DropdownMenuItem(value: k, child: Text('$k（temperature ${freedomTemps[k]}）'))
                  ],
                  onChanged: (v) => s!.freedom = v!,
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: testing ? null : testKey,
                  icon: testing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.wifi_tethering),
                  label: const Text('测试 Key（用上面填的内容，不用先保存）'),
                ),
                if (testResult != null) Padding(padding: const EdgeInsets.only(top: 8), child: SelectableText(testResult!)),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () async {
                    final chosen = vendorPresets.firstWhere((x) => x.id == s!.vendor, orElse: () => vendorPresets.first);
                    final defaultBase = chosen.baseUrl.isNotEmpty ? chosen.baseUrl : 'https://api.deepseek.com';
                    final defaultModel = chosen.models.isNotEmpty ? chosen.models.first.id : 'deepseek-flash';
                    final nextBase = base.text.trim().isEmpty ? defaultBase : base.text.trim();
                    final nextModel = model.text.trim().isEmpty ? defaultModel : model.text.trim();
                    final detected = detectVendorId(nextBase);
                    s!
                      ..baseUrl = nextBase
                      ..model = nextModel
                      ..apiKey = key.text.trim()
                      ..vendor = detected != 'custom' ? detected : 'custom';
                    base.text = s!.baseUrl;
                    model.text = s!.model;
                    await s!.save();
                    if (!mounted) return;
                    final saved = vendorPresets.firstWhere((x) => x.id == s!.vendor, orElse: () => vendorPresets.last);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('已保存：${saved.name} · ${s!.model}'),
                    ));
                    setState(() {});
                    if (widget.standalone) Navigator.pop(context);
                  },
                  child: const Text('保存'),
                ),
                const SizedBox(height: 12),
                const Text(
                  '说明：豆包用火山方舟接口；DeepSeek 继续可用。换厂商后记得换对应的 API Key。',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ]),
      );
}
