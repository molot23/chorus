import 'package:flutter/material.dart';

import 'api.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.settings, required this.onSaved});

  final Settings settings;
  final VoidCallback onSaved;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _host;
  late final TextEditingController _token;
  var _checking = false;
  String? _result;

  @override
  void initState() {
    super.initState();
    _host = TextEditingController(text: widget.settings.host);
    _token = TextEditingController(text: widget.settings.token);
  }

  @override
  void dispose() {
    _host.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    setState(() {
      _checking = true;
      _result = null;
    });
    await widget.settings.save(_host.text, _token.text);
    try {
      final roles = await ChorusApi(widget.settings).roles();
      final names = roles.map((r) => r.name).join('、');
      setState(() => _result = names.isEmpty ? '连上了，但还没有角色' : '连上了，群里有 $names');
      widget.onSaved();
    } catch (e) {
      setState(() => _result = '连不上：$e');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('连接设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _host,
            decoration: const InputDecoration(
              labelText: '服务器地址',
              hintText: 'https://example.com:8443',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _token,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: '访问口令',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _checking ? null : _test,
            child: Text(_checking ? '正在连接……' : '保存并测试连接'),
          ),
          if (_result != null) ...[
            const SizedBox(height: 12),
            Text(_result!),
          ],
          const SizedBox(height: 24),
          Text(
            '地址和口令由服务器上的框架端提供，填一次即可，存在本机。',
            style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
