import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

/// 采集手机上能拿到的状态，离线时攒在本地，连上再逐条补发。
///
/// 解锁和前台应用靠无障碍服务（需要用户手动开启），其余靠前台服务在后台持续跑。
/// 前台服务让通知栏常驻一条，系统就不容易杀进程。
class Collector with WidgetsBindingObserver {
  Collector(this.settings);

  final Settings settings;
  static const _accessChannel = EventChannel('dev.chorus.chorus/access');
  static const _deviceChannel = MethodChannel('dev.chorus.chorus/device');
  var _started = false;
  String _lastApp = '';

  /// 无障碍服务是否已开启。解锁和前台应用采集依赖它，只能用户手动开。
  static Future<bool> accessibilityEnabled() async {
    final enabled = await _deviceChannel.invokeMethod<bool>('accessibilityEnabled');
    return enabled ?? false;
  }

  /// 跳到系统的无障碍设置页。
  static Future<void> openAccessibilitySettings() =>
      _deviceChannel.invokeMethod('openAccessibilitySettings');

  /// 跳到本应用的系统设置页。
  static Future<void> openAppSettings() => _deviceChannel.invokeMethod('openAppSettings');

  /// 定位和通知权限的授予情况。
  static Future<Map<String, bool>> permissions() async => {
        'location': await _deviceChannel.invokeMethod<bool>('locationGranted') ?? false,
        'notification': await _deviceChannel.invokeMethod<bool>('notificationGranted') ?? false,
      };

  Future<void> start() async {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'chorus_collect',
        channelName: '采集',
        channelDescription: '保持 Chorus 在后台采集',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(eventAction: ForegroundTaskEventAction.nothing()),
    );
    if (await FlutterForegroundTask.isRunningService == false) {
      await FlutterForegroundTask.startService(
        notificationTitle: 'Chorus',
        notificationText: '在记录手机状态',
      );
    }

    _startLocation();
    _startBattery();
    _startNetwork();
    _startAccess();
    unawaited(_reportDevice());
    unawaited(flush());

    // 定位每 5 分钟记一次，不管动没动，用来判断停留。
    Timer.periodic(const Duration(minutes: 5), (_) => _locate());
  }

  Future<void> _startLocation() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
      Geolocator.getPositionStream(
        locationSettings: const LocationSettings(distanceFilter: 100),
      ).listen((position) => _saveLocation(position));
    }
  }

  Future<void> _locate() async {
    try {
      final position = await Geolocator.getCurrentPosition();
      _saveLocation(position);
    } catch (_) {}
  }

  void _saveLocation(Position position) {
    _record('location', {'lat': position.latitude, 'lon': position.longitude});
  }

  void _startBattery() {
    final battery = Battery();
    battery.onBatteryStateChanged.listen((_) => _recordBattery(battery));
    _recordBattery(battery);
  }

  Future<void> _recordBattery(Battery battery) async {
    final level = await battery.batteryLevel;
    final state = await battery.batteryState;
    _record('battery', {'level': level, 'charging': state == BatteryState.charging});
  }

  void _startNetwork() {
    Connectivity().onConnectivityChanged.listen((results) {
      final kind = results.contains(ConnectivityResult.wifi)
          ? 'wifi'
          : results.contains(ConnectivityResult.mobile)
              ? 'mobile'
              : 'none';
      _record('network', {'type': kind});
    });
  }

  /// 立刻采集一轮当前状态，调试用。不依赖后台服务是否在跑。
  static Future<void> collectNow() async {
    final settings = Settings();
    await settings.load();
    final collector = Collector(settings);
    await collector._locate();
    await collector._recordBattery(Battery());
    await collector._reportDevice();
    await collector.flush();
  }

  /// 还没发出去的信号条数。
  static Future<int> pendingCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('signals')?.length ?? 0;
  }

  /// 无障碍服务推过来的事件：解锁、亮灭屏、前台应用切换。服务没开时这里收不到任何东西。
  void _startAccess() {
    _accessChannel.receiveBroadcastStream().listen((event) {
      final data = Map<String, dynamic>.from(event as Map);
      switch (data['kind']) {
        case 'unlock':
          _record('unlock', {});
        case 'screen':
          _record('screen', {'state': data['state']});
        case 'app':
          final name = data['name'] as String? ?? '';
          if (name == _lastApp) return;
          _lastApp = name;
          _record('app', {'name': name});
      }
    });
  }

  /// 上报一次手机品牌和型号。
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
    if (state == AppLifecycleState.resumed) unawaited(flush());
  }

  Future<void> _record(String kind, Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getStringList('signals') ?? [];
    pending.add(jsonEncode({'ts': DateTime.now().toIso8601String(), 'kind': kind, 'data': data}));
    await prefs.setStringList('signals', pending);
  }

  /// 把积攒的信号逐条发出去，失败的留着下次再发。
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
        // 服务器明确拒绝的丢掉，避免一条坏数据堵住后面的。
      }
    }
    await prefs.setStringList('signals', left);
  }
}
