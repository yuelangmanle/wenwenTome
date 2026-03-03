import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wenwen_tome/main.dart'; // import app

void main() {
  testWidgets('App starts at Library screen', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: MyApp()));
    // GoRouter requires a frame pump to resolve initial route
    await tester.pumpAndSettle();
    expect(find.text('我的书架'), findsOneWidget);
    expect(find.text('书架空空如也'), findsOneWidget);
  });
}
