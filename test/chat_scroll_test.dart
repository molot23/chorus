import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chorus/api.dart';
import 'package:chorus/chat_page.dart';
import 'package:chorus/models.dart';

class HistoryApi extends ChorusApi {
  HistoryApi() : super(Settings());
  int reads = 0;
  @override
  Future<List<ChatMessage>> messages({int? afterId}) async {
    reads++;
    return afterId == null
        ? List.generate(
            80,
            (i) => ChatMessage(
              id: i + 1,
              speaker: 'A',
              content: 'message ${i + 1}',
              kind: 'chat',
            ),
          )
        : [
            ChatMessage(
              id: 81,
              speaker: 'A',
              content: 'new arrival',
              kind: 'chat',
            ),
          ];
  }
}

void main() {
  testWidgets(
    'latest history is lazy and polling does not move older-reading position',
    (tester) async {
      final api = HistoryApi();
      await tester.pumpWidget(
        MaterialApp(
          home: ChatPage(
            api: api,
            onOpenSettings: (_) {},
            onOpenConnection: () {},
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('message 80'), findsOneWidget);
      expect(find.text('message 1'), findsNothing);
      final list = tester.widget<ListView>(find.byType(ListView));
      expect(list.reverse, isTrue);
      final position = list.controller!;
      expect(position.offset, 0);
      await tester.drag(find.byType(ListView), const Offset(0, 400));
      await tester.pumpAndSettle();
      final offset = position.offset;
      expect(offset, greaterThan(100));
      final reads = api.reads;
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
      expect(api.reads, reads);
      expect(position.offset, offset);
      await tester.pumpWidget(const SizedBox());
      api.close();
    },
  );
}
