import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

const _repo = 'molot23/chorus';

/// 对比版本号，remote 比 local 新就返回 true。
bool _isNewer(String remote, String local) {
  final r = remote.split('.').map(int.tryParse).toList();
  final l = local.split('.').map(int.tryParse).toList();
  for (var i = 0; i < 3; i++) {
    final rv = i < r.length ? (r[i] ?? 0) : 0;
    final lv = i < l.length ? (l[i] ?? 0) : 0;
    if (rv != lv) return rv > lv;
  }
  return false;
}

/// 检查 GitHub 上的最新版本，比当前新就下载并拉起安装。
class UpdateButton extends StatefulWidget {
  const UpdateButton({super.key});

  @override
  State<UpdateButton> createState() => _UpdateButtonState();
}

class _UpdateButtonState extends State<UpdateButton> {
  String _text = '检查更新';
  var _busy = false;

  Future<void> _check() async {
    setState(() {
      _busy = true;
      _text = '正在检查……';
    });
    try {
      final info = await PackageInfo.fromPlatform();
      final response = await http.get(Uri.parse('https://api.github.com/repos/$_repo/releases'));
      if (response.statusCode != 200) {
        setState(() => _text = '检查失败：${response.statusCode}');
        return;
      }
      final releases = jsonDecode(response.body) as List;
      String? newest;
      String? url;
      for (final release in releases) {
        final tag = (release['tag_name'] as String).replaceFirst(RegExp(r'^v'), '');
        if (newest == null || _isNewer(tag, newest)) {
          final assets = release['assets'] as List;
          final apk = assets.cast<Map<String, dynamic>>().where((a) => (a['name'] as String).endsWith('.apk'));
          if (apk.isNotEmpty) {
            newest = tag;
            url = apk.first['browser_download_url'] as String;
          }
        }
      }
      if (newest == null || !_isNewer(newest, info.version)) {
        setState(() => _text = '已是最新版本 ${info.version}');
        return;
      }
      setState(() => _text = '正在下载 $newest ……');
      final bytes = await http.readBytes(Uri.parse(url!));
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/chorus-$newest.apk');
      await file.writeAsBytes(bytes);
      setState(() => _text = '下载完成，正在安装');
      await OpenFilex.open(file.path);
    } catch (e) {
      setState(() => _text = '更新失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.system_update),
      title: Text(_text),
      enabled: !_busy,
      onTap: _check,
    );
  }
}
