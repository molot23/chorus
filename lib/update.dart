import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';

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
  const UpdateButton({super.key, required this.api});

  final ChorusApi api;

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
      // 手机直连 GitHub 经常被拦，发布列表由服务器代查。
      final releases = await widget.api.releases();
      String? newest;
      for (final release in releases) {
        final tag = (release['tag_name'] as String).replaceFirst(RegExp(r'^v'), '');
        if (newest != null && !_isNewer(tag, newest)) continue;
        final assets = release['assets'] as List;
        final hasApk = assets.cast<Map<String, dynamic>>().any((a) => (a['name'] as String).endsWith('.apk'));
        if (hasApk) newest = tag;
      }
      if (newest == null || !_isNewer(newest, info.version)) {
        setState(() => _text = '已是最新版本 ${info.version}');
        return;
      }
      // 不代下载。服务器带宽太小，手机直连又常被拦，打开发布页自己下。
      setState(() => _text = '发现新版本 $newest，正在打开发布页');
      await launchUrl(
        Uri.parse('https://github.com/molot23/chorus/releases/tag/v$newest'),
        mode: LaunchMode.externalApplication,
      );
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
