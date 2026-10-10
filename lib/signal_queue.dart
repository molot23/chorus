import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// A single durable queue shared by every Collector in this isolate.
class SignalQueue {
  static final shared = SignalQueue();
  final _random = Random.secure();
  Future<void> _writes = Future.value();
  Future<void>? _flushing;

  String _newId() => List.generate(16, (_) => _random.nextInt(256))
      .map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

  Future<T> _mutate<T>(Future<T> Function(SharedPreferences) action) {
    final result = _writes.then((_) async => action(await SharedPreferences.getInstance()));
    _writes = result.then<void>((_) {}, onError: (Object error, StackTrace stack) {});
    return result;
  }

  Future<void> _save(SharedPreferences prefs, List<String> values) async {
    if (!await prefs.setStringList('signals', values)) {
      throw StateError('无法保存待上报信号');
    }
  }

  Future<void> enqueue(String kind, Map<String, dynamic> data) {
    final raw = jsonEncode({
      'ts': DateTime.now().toUtc().toIso8601String(),
      'kind': kind,
      'data': data,
      'source': 'phone',
      'event_id': _newId(),
    });
    return _mutate((prefs) async {
      final values = List<String>.of(prefs.getStringList('signals') ?? [])..add(raw);
      await _save(prefs, values);
    });
  }

  Future<int> pendingCount() => _mutate(
      (prefs) async => prefs.getStringList('signals')?.length ?? 0);

  Future<void> flush(Future<void> Function(Map<String, dynamic>) send,
      {Future<bool> Function(String)? enabled}) {
    return _flushing ??= _flush(send, enabled).whenComplete(() => _flushing = null);
  }

  Future<void> _flush(Future<void> Function(Map<String, dynamic>) send,
      Future<bool> Function(String)? enabled) async {
    final snapshot = await _mutate((prefs) async {
      final values = List<String>.of(prefs.getStringList('signals') ?? []);
      for (var i = 0; i < values.length; i++) {
        try {
          final item = jsonDecode(values[i]) as Map<String, dynamic>;
          item.putIfAbsent('source', () => 'phone');
          item.putIfAbsent('event_id', _newId);
          item['ts'] = DateTime.parse(item['ts'] as String).toUtc().toIso8601String();
          values[i] = jsonEncode(item);
        } catch (_) {}
      }
      await _save(prefs, values);
      return values;
    });
    for (final raw in snapshot) {
      try {
        final item = jsonDecode(raw) as Map<String, dynamic>;
        final kind = item['kind'] as String;
        if (enabled != null && !await enabled(kind)) continue;
        await send(item);
      } catch (_) {
        continue;
      }
      await _mutate((prefs) async {
        final values = List<String>.of(prefs.getStringList('signals') ?? [])..remove(raw);
        await _save(prefs, values);
      });
    }
  }
}
