import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wenwen_tome/app/router.dart';
import 'package:wenwen_tome/features/settings/presentation/settings_screen.dart';
import 'package:wenwen_tome/features/settings/providers/global_settings_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Widget> buildApp(GoRouter router) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    return ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  testWidgets('desktop translation config route falls back to settings', (
    tester,
  ) async {
    final router = buildAppRouter(initialLocation: '/translation-config');

    await tester.pumpWidget(await buildApp(router));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.widgetWithText(AppBar, '设置'), findsOneWidget);
    expect(find.text('API 配置'), findsNothing);
  });

  testWidgets('desktop shell hides webnovel tab', (tester) async {
    final router = buildAppRouter(initialLocation: '/settings');

    await tester.pumpWidget(await buildApp(router));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('书架'), findsWidgets);
    expect(find.text('同步'), findsWidgets);
    expect(find.text('设置'), findsWidgets);
    expect(find.text('网文'), findsNothing);
    expect(find.byIcon(Icons.rss_feed_outlined), findsNothing);
  });
}
