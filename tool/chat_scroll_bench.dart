// ignore_for_file: avoid_print, prefer_interpolation_to_compose_strings
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:chorus/api.dart';
import 'package:chorus/chat_page.dart';
import 'package:chorus/models.dart';

class BenchApi extends ChorusApi {
  BenchApi() : super(Settings());
  int reads = 0;
  @override
  Future<List<ChatMessage>> messages({int? afterId}) async {
    reads++;
    if (afterId != null) return const [];
    return List.generate(
      80,
      (i) => ChatMessage(
        id: i + 1,
        speaker: ['??', '??', '??', '?'][i % 4],
        content: '?? ${i + 1}?${i % 7 == 0 ? ('????????????' * 8) : '?????'}',
        kind: 'chat',
      ),
    );
  }
}

void main() {
  final controller = ScrollController();
  final api = BenchApi();
  final timings = <FrameTiming>[];
  runApp(
    MaterialApp(
      home: ChatPage(
        api: api,
        onOpenSettings: (_) {},
        onOpenConnection: () {},
        scrollController: controller,
      ),
    ),
  );
  SchedulerBinding.instance.addTimingsCallback(timings.addAll);
  Timer(const Duration(seconds: 1), () {
    if (!controller.hasClients) return;
    controller.animateTo(
      controller.position.maxScrollExtent,
      duration: const Duration(seconds: 6),
      curve: Curves.linear,
    );
  });
  Timer(const Duration(seconds: 9), () {
    final micros = timings.map((x) => x.totalSpan.inMicroseconds).toList()
      ..sort();
    final jank = micros.where((x) => x > 16667).length;
    print(
      'CHAT_BENCH ' +
          jsonEncode({
            'frames': micros.length,
            'over16ms': jank,
            'over33ms': micros.where((x) => x > 33333).length,
            'p50_ms': micros.isEmpty ? 0 : micros[micros.length ~/ 2] / 1000,
            'p95_ms': micros.isEmpty
                ? 0
                : micros[(micros.length * 95 ~/ 100).clamp(
                        0,
                        micros.length - 1,
                      )] /
                      1000,
            'api_reads': api.reads,
            'messages': 80,
          }),
    );
    api.close();
    SystemNavigator.pop();
  });
}
