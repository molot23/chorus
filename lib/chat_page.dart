import 'package:flutter/material.dart';

import 'api.dart';
import 'models.dart';

/// 三个角色的固定配色。新角色按名字哈希取一个备用色。
const _roleColors = {
  '安安': Color(0xFF7BA17D),
  '桃桃': Color(0xFFE09A9A),
  '点点': Color(0xFF7FA1C4),
};

const _fallbackColors = [
  Color(0xFFB39DDB),
  Color(0xFFE0B080),
  Color(0xFF80CBC4),
];

Color colorOf(String name) =>
    _roleColors[name] ?? _fallbackColors[name.hashCode.abs() % _fallbackColors.length];

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.api,
    required this.onOpenSettings,
    required this.onOpenConnection,
  });

  final ChorusApi api;
  final void Function(BuildContext context) onOpenSettings;
  final VoidCallback onOpenConnection;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  List<ChatMessage> _messages = [];
  var _loading = true;
  var _sending = false;
  var _debug = false;
  String? _error;
  String? _status;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final messages = await widget.api.messages();
      if (!mounted) return;
      setState(() {
        _messages = messages;
        _loading = false;
      });
      _scrollToEnd();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '连接不上服务器：$e';
        _loading = false;
      });
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    _input.clear();
    setState(() {
      _sending = true;
      _status = '她们在想……';
      _error = null;
      _messages = [
        ..._messages,
        ChatMessage(id: -1, speaker: '我', content: text, kind: 'chat'),
      ];
    });
    _scrollToEnd();
    try {
      await for (final event in widget.api.send(text)) {
        if (!mounted) return;
        _apply(event);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '发送失败：$e');
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _status = null;
        });
      }
    }
  }

  Future<void> _regenerate() async {
    setState(() {
      _sending = true;
      _status = '重新生成……';
      _error = null;
    });
    try {
      await for (final event in widget.api.regenerate()) {
        if (!mounted) return;
        if (event.type == 'redo') {
          setState(() => _messages.removeWhere((m) => m.id == -1));
          await _load();
        } else {
          _apply(event);
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = '重来失败：$e');
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _status = null;
        });
      }
    }
  }

  void _apply(TurnEvent event) {
    switch (event.type) {
      case 'plan':
        final speakers = event.data['speakers'] as List? ?? [];
        setState(() {
          _status = speakers.isEmpty
              ? '这轮没有人接话'
              : '${speakers.map((s) => (s as Map)['name']).join('、')} 准备说话';
        });
      case 'speaking':
        setState(() => _status = '${event.speaker} 正在说……');
      case 'message':
        setState(() {
          _messages = [
            ..._messages,
            ChatMessage(
              id: -1,
              speaker: event.speaker ?? '',
              content: event.content ?? '',
              kind: 'chat',
              debug: (event.data['debug'] as String?) ?? '',
            ),
          ];
        });
        _scrollToEnd();
      case 'error':
        setState(() {
          _messages = [
            ..._messages,
            ChatMessage(
              id: -1,
              speaker: '系统',
              content: event.content ?? '出错了',
              kind: 'system',
            ),
          ];
        });
        _scrollToEnd();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('Chorus'),
        actions: [
          IconButton(
            onPressed: _sending ? null : _regenerate,
            icon: const Icon(Icons.replay),
            tooltip: '重来',
          ),
          IconButton(
            onPressed: () => setState(() => _debug = !_debug),
            icon: Icon(Icons.bug_report_outlined,
                color: _debug ? Theme.of(context).colorScheme.primary : null),
            tooltip: '调试',
          ),
          IconButton(
            onPressed: widget.onOpenConnection,
            icon: const Icon(Icons.link),
            tooltip: '连接',
          ),
          IconButton(
            onPressed: () => widget.onOpenSettings(context),
            icon: const Icon(Icons.settings_outlined),
            tooltip: '设置',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildBody()),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                _status!,
                style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12),
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
            ),
          _InputBar(controller: _input, sending: _sending, onSend: _send),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_messages.isEmpty) {
      return const Center(
        child: Text('还没有消息，跟她们打个招呼吧', style: TextStyle(color: Colors.grey)),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _messages.length,
      itemBuilder: (context, index) => _Bubble(message: _messages[index], debug: _debug),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.debug});

  final ChatMessage message;
  final bool debug;

  @override
  Widget build(BuildContext context) {
    if (message.isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(
          child: Text(
            message.content,
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ),
      );
    }
    final mine = message.isMine;
    final color = mine ? Theme.of(context).colorScheme.primaryContainer : colorOf(message.speaker);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!mine) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: color,
              child: Text(
                message.speaker.characters.first,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!mine)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 2),
                    child: Text(
                      message.speaker,
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: mine ? color : color.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(message.content),
                ),
                if (debug) _DebugInfo(message: message),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DebugInfo extends StatelessWidget {
  const _DebugInfo({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    if (message.debug.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(message.debug, style: const TextStyle(fontSize: 11, color: Colors.grey)),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({required this.controller, required this.sending, required this.onSend});

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: const InputDecoration(
                  hintText: '说点什么……',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 4),
            sending
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    onPressed: onSend,
                    icon: const Icon(Icons.send),
                    tooltip: '发送',
                  ),
          ],
        ),
      ),
    );
  }
}
