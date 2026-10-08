// 和服务器之间传递的数据结构。字段名跟框架端约定的 JSON 对齐。

class Role {
  Role({required this.name, required this.persona, required this.enabled});

  final String name;
  final String persona;
  final bool enabled;

  factory Role.fromJson(Map<String, dynamic> json) => Role(
        name: json['name'] as String,
        persona: (json['persona'] as String?) ?? '',
        enabled: json['enabled'] != false,
      );
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.speaker,
    required this.content,
    required this.kind,
    this.ts,
  });

  final int id;
  final String speaker;
  final String content;

  /// chat：正常发言；system：系统提示（调度失败之类）。
  final String kind;
  final String? ts;

  bool get isMine => speaker == '我';
  bool get isSystem => kind == 'system';

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as int,
        speaker: json['speaker'] as String,
        content: json['content'] as String,
        kind: (json['kind'] as String?) ?? 'chat',
        ts: json['ts'] as String?,
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
