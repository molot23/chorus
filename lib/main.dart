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
    _settings.load().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
      if (_settings.isConfigured) {
        _collector = Collector(_settings)..start();
      }
    });
  }

  void _openConnection() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsPage(
          settings: _settings,
          onSaved: () => setState(() {}),
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
      return SettingsPage(settings: _settings, onSaved: () => setState(() {}));
    }
    return ChatPage(
      api: ChorusApi(_settings),
      onOpenSettings: (context) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ServerSettingsPage(api: ChorusApi(_settings))),
      ),
      onOpenConnection: _openConnection,
    );
  }
}
