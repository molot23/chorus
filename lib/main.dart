import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'chat_page.dart';
import 'collector.dart';
import 'server_settings_page.dart';
import 'settings_page.dart';

void main() {
  runApp(const ChorusApp());
}

class ChorusApp extends StatelessWidget {
  const ChorusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chorus',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF7BA17D)),
        useMaterial3: true,
      ),
      home: const Home(),
    );
  }
}

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final _settings = Settings();
  Collector? _collector;
  var _ready = false;

  @override
  void initState() {
    super.initState();
    _settings.load().then((_) async {
      if (!mounted) return;
      setState(() => _ready = true);
      if (_settings.isConfigured) {
        _startCollector();
        // 无障碍没开时提醒一次，解锁和前台应用采集都靠它。
        if (!await Collector.accessibilityEnabled() && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('解锁和前台应用采集需要开启无障碍服务'),
            action: SnackBarAction(label: '去开启', onPressed: Collector.openAccessibilitySettings),
          ));
        }
      }
    });
  }

  void _startCollector() {
    if (_collector != null || !_settings.isConfigured) return;
    final collector = Collector(_settings);
    _collector = collector;
    unawaited(collector.start());
  }

  void _onConnectionSaved() {
    if (!mounted) return;
    _startCollector();
    setState(() {});
  }

  @override
  void dispose() {
    final collector = _collector;
    if (collector != null) unawaited(collector.dispose());
    super.dispose();
  }

  void _openConnection() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsPage(
          settings: _settings,
          onSaved: _onConnectionSaved,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_settings.isConfigured) {
      return SettingsPage(settings: _settings, onSaved: _onConnectionSaved);
    }
    return ChatPage(
      api: ChorusApi(_settings),
      onOpenSettings: (context) => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ServerSettingsPage(api: ChorusApi(_settings), connection: _settings),
        ),
      ),
      onOpenConnection: _openConnection,
    );
  }
}
