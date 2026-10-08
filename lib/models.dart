// 和服务器之间传递的数据结构。字段名跟框架端约定的 JSON 对齐。

class Role {
  Role({
    required this.id,
    required this.name,
    required this.persona,
    required this.enabled,
    this.memories = '',
  });

  final int id;
  final String name;
  final String persona;
  final bool enabled;

  /// 角色的私有日记文本。
  final String memories;

  factory Role.fromJson(Map<String, dynamic> json) => Role(
        id: (json['id'] as int?) ?? 0,
        name: json['name'] as String,
        persona: (json['persona'] as String?) ?? '',
        enabled: json['enabled'] != false,
        memories: (json['memories'] as String?) ?? '',
      );
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.speaker,
    required this.content,
    required this.kind,
    this.ts,
    this.trace = '',
    this.turn,
  });

  final int id;
  final String speaker;
  final String content;

  /// chat：正常发言；system：系统提示（调度失败之类）。
  final String kind;
  final String? ts;

  /// 角色发言的调试信息（意图、耗时、工具调用），没有就是空字符串。
  final String trace;

  /// 触发这一轮的用户消息附带的调度记录，没有就是 null。
  final Map<String, dynamic>? turn;

  bool get isMine => speaker == '我';
  bool get isSystem => kind == 'system';

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as int,
        speaker: json['speaker'] as String,
        content: json['content'] as String,
        kind: (json['kind'] as String?) ?? 'chat',
        ts: json['ts'] as String?,
        trace: (json['trace'] as String?) ?? '',
        turn: json['turn'] as Map<String, dynamic>?,
      );
}

/// 发一条消息后，服务器流式推回来的事件。
class TurnEvent {
  TurnEvent(this.type, this.data);

  final String type;
  final Map<String, dynamic> data;

  String? get speaker => data['speaker'] as String?;
  String? get content => data['content'] as String?;

  factory TurnEvent.fromJson(Map<String, dynamic> json) =>
      TurnEvent(json['type'] as String, json);
}

/// 一个模型后端。只有名字和模型名，不含密钥。
class Backend {
  Backend({required this.id, required this.name, required this.model});

  final int id;
  final String name;
  final String model;

  String get label => '$name · $model';

  factory Backend.fromJson(Map<String, dynamic> json) => Backend(
        id: json['id'] as int,
        name: json['name'] as String,
        model: json['model'] as String,
      );
}
