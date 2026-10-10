import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chorus/main.dart';

void main() {
  testWidgets('unconfigured app opens server settings', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ChorusApp());
    await tester.pumpAndSettle();
    expect(find.text('服务器地址'), findsWidgets);
  });
}
