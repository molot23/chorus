import 'package:flutter/material.dart';

import 'api.dart';
import 'chat_page.dart';
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
  var _ready = false;

  @override
  void initState() {
    super.initState();
    _settings.load().then((_) {
      if (mounted) setState(() => _ready = true);
    });
  }

  void _openSettings() {
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
    return ChatPage(api: ChorusApi(_settings), onOpenSettings: _openSettings);
  }
}
