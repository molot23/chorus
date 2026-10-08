import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

/// 采集解锁和定位，离线时攒在本地，连上再逐条补发。
///
/// 安卓没有解锁的直接回调，用"屏幕点亮后进入前台"来近似一次解锁。
/// 保活靠前台服务：通知栏常驻一条，系统就不容易把进程杀掉。
class Collector with WidgetsBindingObserver {
  Collector(this.settings);

  final Settings settings;
  var _started = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'chorus_collect',
        channelName: '采集',
        channelDescription: '保持 Chorus 在后台采集解锁和定位',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(eventAction: ForegroundTaskEventAction.nothing()),
    );

    if (await FlutterForegroundTask.isRunningService == false) {
      await FlutterForegroundTask.startService(
        notificationTitle: 'Chorus',
        notificationText: '在记录解锁和定位',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
      Geolocator.getPositionStream(
        locationSettings: const LocationSettings(distanceFilter: 100),
      ).listen((position) {
        _record('location', {'lat': position.latitude, 'lon': position.longitude});
      });
    }
    unawaited(flush());
    unawaited(_reportDevice());
  }

  /// 上报一次手机品牌和型号，服务端据此决定推送通道。
  Future<void> _reportDevice() async {
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      await _record('device', {
        'brand': info.brand,
        'manufacturer': info.manufacturer,
        'model': info.model,
        'version': info.version.release,
      });
      await flush();
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _record('unlock', {});
      unawaited(flush());
    }
  }

  Future<void> _record(String kind, Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getStringList('signals') ?? [];
    pending.add(jsonEncode({'ts': DateTime.now().toIso8601String(), 'kind': kind, 'data': data}));
    await prefs.setStringList('signals', pending);
  }

  /// 把积攒的信号逐条发出去，发出去的删掉，失败的留着下次再发。
  Future<void> flush() async {
    if (!settings.isConfigured) return;
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getStringList('signals') ?? [];
    if (pending.isEmpty) return;
    final api = ChorusApi(settings);
    final left = <String>[];
    for (final raw in pending) {
      try {
        final item = jsonDecode(raw) as Map<String, dynamic>;
        await api.signal(
          item['ts'] as String,
          item['kind'] as String,
          (item['data'] as Map?)?.cast<String, dynamic>() ?? {},
        );
      } on SocketException {
        left.add(raw);
      } catch (_) {
        // 服务器明确拒绝的（比如格式不对）丢掉，避免一条坏数据堵住后面的。
      }
    }
    await prefs.setStringList('signals', left);
  }
}
