import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// 服务器地址和访问口令存在本地，不写进代码。
class Settings {
  static const _hostKey = 'host';
  static const _tokenKey = 'token';

  String host = '';
  String token = '';

  bool get isConfigured => host.isNotEmpty && token.isNotEmpty;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    host = prefs.getString(_hostKey) ?? '';
    token = prefs.getString(_tokenKey) ?? '';
  }

  Future<void> save(String newHost, String newToken) async {
    host = newHost.trim().replaceAll(RegExp(r'/+$'), '');
    token = newToken.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_hostKey, host);
    await prefs.setString(_tokenKey, token);
  }
}

class ApiException implements Exception {
  ApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// 跟 Chorus 框架端通信。所有接口都约定在 /api 下，用 Bearer 口令鉴权。
class ChorusApi {
  ChorusApi(this.settings)
      : _client = IOClient(HttpClient()
          ..badCertificateCallback = (cert, host, port) => true);

  final Settings settings;

  /// 服务器用的是自签证书，这里允许它。只连自己的服务器，风险可接受。
  final http.Client _client;

  Map<String, String> get _headers => {
        'Authorization': 'Bearer ${settings.token}',
        'Content-Type': 'application/json',
      };

  Uri _uri(String path) => Uri.parse('${settings.host}$path');

  Never _fail(http.Response response) {
    var message = '服务器返回 ${response.statusCode}';
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['error'] is String) message = body['error'] as String;
    } catch (_) {}
    throw ApiException(message);
  }

  Future<List<ChatMessage>> messages() async {
    final response = await _client.get(_uri('/api/messages'), headers: _headers);
    if (response.statusCode != 200) _fail(response);
    final list = jsonDecode(utf8.decode(response.bodyBytes)) as List;
    return [
      for (final item in list) ChatMessage.fromJson(item as Map<String, dynamic>),
    ];
  }

  Future<List<Role>> roles() async {
    final response = await _client.get(_uri('/api/roles'), headers: _headers);
    if (response.statusCode != 200) _fail(response);
    final list = jsonDecode(utf8.decode(response.bodyBytes)) as List;
    return [for (final item in list) Role.fromJson(item as Map<String, dynamic>)];
  }

  /// 发送一条消息，返回这一轮的事件流：plan、speaking、message、error、done。
  Stream<TurnEvent> send(String text) => _streamPost('/api/send', {'text': text});

  /// 重新生成最后一轮回复。
  Stream<TurnEvent> regenerate() => _streamPost('/api/regenerate', {});

  /// 全部设置。
  Future<Map<String, dynamic>> getSettings() async {
    final response = await _client.get(_uri('/api/settings'), headers: _headers);
    if (response.statusCode != 200) _fail(response);
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }

  /// 改一个或几个设置，只更新给的键。
  Future<void> updateSettings(Map<String, dynamic> values) async {
    final response = await _client.post(
      _uri('/api/settings'),
      headers: _headers,
      body: jsonEncode(values),
    );
    if (response.statusCode != 200) _fail(response);
  }

  /// 可选的模型后端，不含密钥。
  Future<List<Backend>> backends() async {
    final response = await _client.get(_uri('/api/backends'), headers: _headers);
    if (response.statusCode != 200) _fail(response);
    final list = jsonDecode(utf8.decode(response.bodyBytes)) as List;
    return [for (final item in list) Backend.fromJson(item as Map<String, dynamic>)];
  }

  /// 关于主人的事实文本。
  Future<String> facts() async {
    final response = await _client.get(_uri('/api/facts'), headers: _headers);
    if (response.statusCode != 200) _fail(response);
    final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    return (body['facts'] as String?) ?? '';
  }

  /// 清空全部群聊记录。
  Future<void> clearMessages() async {
    final response = await _client.post(_uri('/api/messages/clear'), headers: _headers, body: '{}');
    if (response.statusCode != 200) _fail(response);
  }

  /// 全部历史记录。
  Future<List<ChatMessage>> history() async {
    final response = await _client.get(_uri('/api/history'), headers: _headers);
    if (response.statusCode != 200) _fail(response);
    final list = jsonDecode(utf8.decode(response.bodyBytes)) as List;
    return [for (final item in list) ChatMessage.fromJson(item as Map<String, dynamic>)];
  }

  /// 上报一条采集信号。ts 是采集发生的时间，不是上报时间。
  Future<void> signal(String ts, String kind, Map<String, dynamic> data) async {
    final response = await _client.post(
      _uri('/api/signal'),
      headers: _headers,
      body: jsonEncode({'ts': ts, 'kind': kind, 'data': data}),
    );
    if (response.statusCode != 200) _fail(response);
  }

  Stream<TurnEvent> _streamPost(String path, Map<String, dynamic> body) async* {
    final request = http.Request('POST', _uri(path))
      ..headers.addAll(_headers)
      ..body = jsonEncode(body);
    final response = await _client.send(request);
    if (response.statusCode != 200) {
      final text = await response.stream.bytesToString();
      _fail(http.Response(text, response.statusCode));
    }
    final lines = response.stream.toStringStream().transform(const LineSplitter());
    await for (final line in lines) {
      if (line.trim().isEmpty) continue;
      yield TurnEvent.fromJson(jsonDecode(line) as Map<String, dynamic>);
    }
  }
}
