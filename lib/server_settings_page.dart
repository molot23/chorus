import 'package:flutter/material.dart';

import 'api.dart';
import 'models.dart';
import 'collector.dart';
import 'settings_page.dart';
import 'update.dart';

/// 设置页：左边分类，右边内容。加新设置项就是加一个分类。
class ServerSettingsPage extends StatefulWidget {
  const ServerSettingsPage({super.key, required this.api, required this.connection});

  final ChorusApi api;
  final Settings connection;

  @override
  State<ServerSettingsPage> createState() => _ServerSettingsPageState();
}

class _ServerSettingsPageState extends State<ServerSettingsPage> {
  static const _categories = ['连接', '模型', '对话', '角色', '记忆', '归档', '本机', '关于'];

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
      case 5:
        return _ArchivePage(api: widget.api);
      case 6:
        return _LocalDebugPage(api: widget.api);
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
          leading: const Icon(Icons.archive_outlined),
          title: const Text('归档这段对话'),
          subtitle: const Text('从界面收起，数据还在，可在「归档」里查看'),
          onTap: _archive,
        ),
        if (_error != null) _errorText(),
      ],
    );
  }

  Future<void> _archive() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('归档这段对话？'),
        content: const Text('当前对话会从界面收起，保存到「归档」里，随时可以回看。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('归档')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.archive();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = '归档失败：$e');
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
      children: [
        const Text('Chorus'),
        const SizedBox(height: 8),
        const Text('版本 0.3.7', style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 8),
        UpdateButton(api: widget.api),
        const SizedBox(height: 8),
        const Text('一个真人和安安、桃桃、点点的群聊。', style: TextStyle(fontSize: 13)),
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

/// 已归档的对话段：列表、回看、真删除。
class _ArchivePage extends StatefulWidget {
  const _ArchivePage({required this.api});

  final ChorusApi api;

  @override
  State<_ArchivePage> createState() => _ArchivePageState();
}

class _ArchivePageState extends State<_ArchivePage> {
  List<Map<String, dynamic>>? _segments;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await widget.api.segments();
      if (mounted) setState(() => _segments = list);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _delete(int segment) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('彻底删除这段？'),
        content: const Text('删除后无法恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.deleteSegment(segment);
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = '删除失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Center(child: Text(_error!));
    if (_segments == null) return const Center(child: CircularProgressIndicator());
    if (_segments!.isEmpty) {
      return const Center(child: Text('还没有归档的对话', style: TextStyle(color: Colors.grey)));
    }
    return ListView.builder(
      itemCount: _segments!.length,
      itemBuilder: (context, index) {
        final s = _segments![index];
        final segment = s['segment'] as int;
        final ts = (s['ts'] as String?) ?? '';
        final n = s['n'];
        return ListTile(
          title: Text(ts.isEmpty ? '第 $segment 段' : ts),
          subtitle: Text('$n 条消息'),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => _SegmentPage(api: widget.api, segment: segment, title: ts)),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '彻底删除',
            onPressed: () => _delete(segment),
          ),
        );
      },
    );
  }
}

class _SegmentPage extends StatefulWidget {
  const _SegmentPage({required this.api, required this.segment, required this.title});

  final ChorusApi api;
  final int segment;
  final String title;

  @override
  State<_SegmentPage> createState() => _SegmentPageState();
}

class _SegmentPageState extends State<_SegmentPage> {
  List<ChatMessage>? _list;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.api.segmentMessages(widget.segment).then((list) {
      if (mounted) setState(() => _list = list);
    }).catchError((e) {
      if (mounted) setState(() => _error = '$e');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title.isEmpty ? '第 ${widget.segment} 段' : widget.title)),
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


/// 本机调试：权限状态、立即采集、上报队列、服务端收到的信号。
class _LocalDebugPage extends StatefulWidget {
  const _LocalDebugPage({required this.api});

  final ChorusApi api;

  @override
  State<_LocalDebugPage> createState() => _LocalDebugPageState();
}

class _LocalDebugPageState extends State<_LocalDebugPage> with WidgetsBindingObserver {
  bool? _accessibility;
  Map<String, bool> _permissions = {};
  int? _pending;
  Map<String, dynamic>? _server;
  String? _error;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 从系统设置页回来时重新读权限，省得手动刷新。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    try {
      final results = await Future.wait([
        Collector.accessibilityEnabled(),
        Collector.permissions(),
        Collector.pendingCount(),
        widget.api.debugInfo(),
      ]);
      if (!mounted) return;
      setState(() {
        _accessibility = results[0] as bool;
        _permissions = results[1] as Map<String, bool>;
        _pending = results[2] as int;
        _server = results[3] as Map<String, dynamic>;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _collectNow() async {
    setState(() => _busy = true);
    try {
      await Collector.collectNow();
      await _refresh();
    } catch (e) {
      if (mounted) setState(() => _error = '采集失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _stateText(String key) {
    final state = (_server?['state'] as Map?) ?? {};
    final value = state[key];
    if (value == null) return '未知';
    if (value is bool) return value ? '是' : '否';
    if (value is Map) return value.entries.map((e) => '${e.key} ${e.value}').join('，');
    return '$value';
  }

  @override
  Widget build(BuildContext context) {
    final signals = ((_server?['signals'] as List?) ?? []).cast<Map>();
    return ListView(
      children: [
        ListTile(
          leading: Icon(
            _accessibility == true ? Icons.check_circle : Icons.error_outline,
            color: _accessibility == true ? Colors.green : Colors.orange,
          ),
          title: Text('无障碍服务：${_accessibility == null ? '读取中' : _accessibility! ? '已开启' : '未开启'}'),
          subtitle: const Text('解锁、亮灭屏和前台应用都靠它，只能手动开启'),
          trailing: TextButton(
            onPressed: Collector.openAccessibilitySettings,
            child: const Text('去开启'),
          ),
        ),
        ListTile(
          title: Text('定位权限：${_permissions['location'] == true ? '已授予' : '未授予'}'),
          subtitle: Text('通知权限：${_permissions['notification'] == true ? '已授予' : '未授予'}'),
          trailing: TextButton(
            onPressed: Collector.openAppSettings,
            child: const Text('去设置'),
          ),
        ),
        ListTile(
          title: Text('待上报 ${_pending ?? '-'} 条'),
          subtitle: const Text('连不上服务器时攒在本机，连上自动补发'),
          trailing: TextButton(
            onPressed: _busy ? null : _collectNow,
            child: Text(_busy ? '采集中' : '立即采集'),
          ),
        ),
        const Divider(),
        ListTile(title: const Text('服务端看到的状态'), subtitle: Text('更新于 ${_stateText('updated_at')}')),
        ListTile(dense: true, title: Text('起床时间：${_stateText('woke_at')}')),
        ListTile(dense: true, title: Text('手机在用：${_stateText('phone_in_use')}，电脑在用：${_stateText('computer_in_use')}')),
        ListTile(dense: true, title: Text('位置：${_stateText('location')}')),
        const Divider(),
        const ListTile(title: Text('最近上报的信号'), subtitle: Text('服务端收到的最近 30 条')),
        for (final item in signals)
          ListTile(
            dense: true,
            title: Text('${item['kind']}  ${item['data']}'),
            subtitle: Text('${item['ts']}', style: const TextStyle(fontSize: 11)),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          ),
      ],
    );
  }
}
