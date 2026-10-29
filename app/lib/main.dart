import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

const dataUrl = 'https://raw.githubusercontent.com/304584987/novel-rank/main/data/latest.json';

void main() => runApp(const MaterialApp(title: '小说榜单', home: HomePage(), debugShowCheckedModeBanner: false));

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Map<String, dynamic>? data;
  String? error;
  int site = 0;

  @override
  void initState() { super.initState(); load(); }

  Future<void> load() async {
    try {
      final r = await http.get(Uri.parse('$dataUrl?t=${DateTime.now().millisecondsSinceEpoch}'));
      if (r.statusCode != 200) throw 'HTTP ${r.statusCode}';
      setState(() { data = jsonDecode(utf8.decode(r.bodyBytes)); error = null; });
    } catch (e) { setState(() => error = '加载失败：$e'); }
  }

  @override
  Widget build(BuildContext context) {
    final sites = (data?['sites'] as List?) ?? [];
    final s = sites.isEmpty ? null : sites[site.clamp(0, sites.length - 1)];
    final lists = (s?['lists'] as List?) ?? [];
    return Scaffold(
      appBar: AppBar(title: Text(s == null ? '小说榜单' : '${s['name']}'),
        bottom: data == null ? null : PreferredSize(preferredSize: const Size.fromHeight(20),
          child: Text('更新：${data!['updated']}', style: const TextStyle(fontSize: 12)))),
      drawer: Drawer(child: ListView(children: [
        const DrawerHeader(child: Text('选择网站', style: TextStyle(fontSize: 20))),
        for (var i = 0; i < sites.length; i++)
          ListTile(title: Text(sites[i]['name']), selected: i == site,
            onTap: () { setState(() => site = i); Navigator.pop(context); }),
      ])),
      body: RefreshIndicator(onRefresh: load, child: ListView(children: [
        if (error != null) Padding(padding: const EdgeInsets.all(16), child: Text(error!, style: const TextStyle(color: Colors.red))),
        if (data == null && error == null) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
        for (final l in lists) ExpansionTile(
          initiallyExpanded: true,
          title: Text('${l['name']}', style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: l['error'] != null ? Text('抓取失败', style: const TextStyle(color: Colors.red)) : null,
          children: [ for (final b in (l['books'] as List).take(l['books'].length > 10 && s?['key'] != 'jjwxc' ? 10 : 100)) ListTile(
            leading: CircleAvatar(radius: 14, child: Text('${b['rank']}', style: const TextStyle(fontSize: 12))),
            title: Text('${b['title']}${b['author'] != null ? '  · ${b['author']}' : ''}${b['cat'] != null && s?['key'] == 'jjwxc' ? '  [${b['cat']}]' : ''}'),
            subtitle: Text(b['core'] ?? (b['intro'] ?? '').toString().replaceAll('<br>', ' '), maxLines: b['core'] != null ? 4 : 2, overflow: TextOverflow.ellipsis),
            onTap: b['url'] == null ? null : () => launchUrl(Uri.parse(b['url']), mode: LaunchMode.externalApplication),
          )],
        ),
      ])),
    );
  }
}
