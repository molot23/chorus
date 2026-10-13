import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chorus/api.dart';
import 'package:chorus/chat_page.dart';
import 'package:chorus/models.dart';

class FakeApi extends ChorusApi {
  FakeApi() : super(Settings());
  int reads = 0;
  bool offline = false;
  @override
  Future<List<ChatMessage>> messages({int? afterId}) async {
    reads++;
    if (offline) throw StateError('offline');
    return [
      ChatMessage(
        id: reads,
        speaker: 'Anan',
        content: 'report $reads',
        kind: 'chat',
      ),
    ];
  }
}

void main() {
  testWidgets(
    'incoming report refreshes without user send; offline retains chat',
    (tester) async {
      final api = FakeApi();
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
      expect(find.text('report 1'), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
      expect(find.text('report 2'), findsOneWidget);
      api.offline = true;
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
      expect(find.text('report 2'), findsOneWidget);
      api.offline = false;
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
      expect(find.text('report 4'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      api.close();
    },
  );
}
