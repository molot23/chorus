import 'package:flutter/material.dart';

import 'api.dart';
import 'models.dart';
import 'settings_page.dart';

/// 设置页：左边分类，右边内容。加新设置项就是加一个分类。
class ServerSettingsPage extends StatefulWidget {
  const ServerSettingsPage({super.key, required this.api, required this.connection});

  final ChorusApi api;
  final Settings connection;

  @override
  State<ServerSettingsPage> createState() => _ServerSettingsPageState();
}

class _ServerSettingsPageState extends State<ServerSettingsPage> {
  static const _categories = ['连接', '模型', '对话', '角色', '记忆', '关于'];

  var _index = 0;
  Map<String, dynamic>? _settings;
  List<Backend> _backends = [];
  List<Role> _roles = [];
  String _facts = '';
  var _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        widget.api.getSettings(),
        widget.api.backends(),
        widget.api.roles(),
        widget.api.facts(),
      ]);
      if (!mounted) return;
      setState(() {
        _settings = results[0] as Map<String, dynamic>;
        _backends = results[1] as List<Backend>;
        _roles = results[2] as List<Role>;
        _facts = results[3] as String;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _save(Map<String, dynamic> values) async {
    try {
      await widget.api.updateSettings(values);
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = '保存失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('设置 · ${_categories[_index]}')),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            labelType: NavigationRailLabelType.all,
            destinations: [
              for (final name in _categories) NavigationRailDestination(icon: const Icon(Icons.circle), label: Text(name)),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _settings == null) return Center(child: Text(_error!));
    switch (_index) {
      case 0:
        return SettingsPage(settings: widget.connection, onSaved: () => setState(() {}));
      case 1:
        return _modelPage();
      case 2:
        return _talkPage();
      case 3:
        return _rolePage();
      case 4:
        return _memoryPage();
      default:
        return _aboutPage();
    }
  }

  Widget _modelPage() {
    return ListView(
      children: [
        _backendTile('生成用', 'complete_backend'),
        _backendTile('判断用', 'judge_backend', allowEmpty: true),
        if (_error != null) _errorText(),
      ],
    );
  }

  Widget _backendTile(String label, String key, {bool allowEmpty = false}) {
    final current = _settings?[key];
    final value = (current == null || current.toString().isEmpty) ? '' : current.toString();
    return ListTile(
      title: Text(label),
      subtitle: DropdownButton<String>(
        isExpanded: true,
        value: value,
        items: [
          if (allowEmpty) const DropdownMenuItem(value: '', child: Text('跟生成用同一个')),
          for (final b in _backends) DropdownMenuItem(value: '${b.id}', child: Text(b.label)),
        ],
        onChanged: (v) {
          if (v != null) _save({key: v.isEmpty ? '' : int.parse(v)});
        },
      ),
    );
  }

  Widget _talkPage() {
    return ListView(
      children: [
        SwitchListTile(
          title: const Text('反思'),
          subtitle: const Text('停顿一段时间后，角色自己决定记什么'),
          value: _settings?['reflect_enabled'] == true,
          onChanged: (v) => _save({'reflect_enabled': v}),
        ),
        ListTile(
          title: Text('每轮最多 ${_settings?['max_responders'] ?? 1} 个角色响应'),
          subtitle: Slider(
            min: 1,
            max: 5,
            divisions: 4,
            value: ((_settings?['max_responders'] ?? 1) as num).toDouble(),
            onChanged: (v) => setState(() => _settings?['max_responders'] = v.round()),
            onChangeEnd: (v) => _save({'max_responders': v.round()}),
          ),
        ),
        ListTile(
          title: Text('停顿 ${_settings?['reflect_after_seconds'] ?? 45} 秒后反思'),
          subtitle: Slider(
            min: 10,
            max: 300,
            divisions: 29,
            value: ((_settings?['reflect_after_seconds'] ?? 45) as num).toDouble(),
            onChanged: (v) => setState(() => _settings?['reflect_after_seconds'] = v.round()),
            onChangeEnd: (v) => _save({'reflect_after_seconds': v.round()}),
          ),
        ),
        ListTile(
          title: const Text('调度用'),
          trailing: DropdownButton<String>(
            value: (_settings?['director'] as String?) ?? 'llm',
            items: const [
              DropdownMenuItem(value: 'llm', child: Text('原来的导演')),
              DropdownMenuItem(value: 'clef', child: Text('Clef 决策')),
            ],
            onChanged: (v) {
              if (v != null) _save({'director': v});
            },
          ),
        ),
        ListTile(
          leading: const Icon(Icons.delete_outline),
          title: const Text('清空群记录'),
          onTap: _clear,
        ),
        if (_error != null) _errorText(),
      ],
    );
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空所有对话记录？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('清空')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.clearMessages();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = '清空失败：$e');
    }
  }

  Widget _rolePage() {
    return ListView(
      children: [
        for (final role in _roles)
          ExpansionTile(
            title: Text(role.enabled ? role.name : '${role.name}（停用）'),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(role.persona.trim()),
                    if (role.memories.trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text('日记', style: TextStyle(color: Colors.grey)),
                      const SizedBox(height: 4),
                      Text(role.memories.trim(), style: const TextStyle(fontSize: 13)),
                    ],
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _memoryPage() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('关于主人', style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 8),
        Text(_facts.trim().isEmpty ? '还没有记下关于主人的事实。' : _facts.trim()),
        const SizedBox(height: 16),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.history),
          title: const Text('查看全部记录'),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => _HistoryPage(api: widget.api)),
          ),
        ),
      ],
    );
  }

  Widget _aboutPage() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        Text('Chorus'),
        SizedBox(height: 8),
        Text('版本 0.3.1', style: TextStyle(color: Colors.grey)),
        SizedBox(height: 8),
        Text('一个真人和安安、桃桃、点点的群聊。', style: TextStyle(fontSize: 13)),
      ],
    );
  }

  Widget _errorText() => Padding(
        padding: const EdgeInsets.all(16),
        child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
      );
}

class _HistoryPage extends StatefulWidget {
  const _HistoryPage({required this.api});

  final ChorusApi api;

  @override
  State<_HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<_HistoryPage> {
  List<ChatMessage>? _list;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.api.history().then((list) {
      if (mounted) setState(() => _list = list);
    }).catchError((e) {
      if (mounted) setState(() => _error = '$e');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('全部记录')),
      body: _error != null
          ? Center(child: Text(_error!))
          : _list == null
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  itemCount: _list!.length,
                  itemBuilder: (context, index) {
                    final m = _list![index];
                    return ListTile(
                      dense: true,
                      title: Text('${m.speaker}：${m.content}'),
                      subtitle: m.ts == null ? null : Text(m.ts!, style: const TextStyle(fontSize: 11)),
                    );
                  },
                ),
    );
  }
}
