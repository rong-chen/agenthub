import 'package:flutter_test/flutter_test.dart';
import 'package:agenthub/main.dart';

void main() {
  testWidgets('App basic initialization test', (WidgetTester tester) async {
    await tester.pumpWidget(const OpenClawApp());
    await tester.pumpAndSettle(const Duration(seconds: 1));
  });
}
