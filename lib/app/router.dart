import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../features/library/presentation/library_screen.dart';
import '../features/sync/presentation/sync_screen.dart';
import '../features/search/presentation/search_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/webnovel/presentation/webnovel_screen.dart';

// Shell 路由用于持久化底部导航栏
final _shellNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    // ── 底部导航 Shell ──
    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      builder: (context, state, child) => _AppShell(child: child),
      routes: [
        GoRoute(path: '/', builder: (context, state) => const LibraryScreen()),
        GoRoute(path: '/webnovel', builder: (context, state) => const WebNovelScreen()),
        GoRoute(path: '/sync', builder: (context, state) => const SyncScreen()),
        GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
      ],
    ),
    // ── 全屏路由（不包含底部导航栏）──
    GoRoute(path: '/search', builder: (context, state) => const SearchScreen()),
  ],
);

/// 底部导航 Shell 容器
class _AppShell extends StatefulWidget {
  final Widget child;
  const _AppShell({required this.child});
  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  static const _tabs = ['/', '/webnovel', '/sync', '/settings'];
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: widget.child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) {
          setState(() => _currentIndex = i);
          context.go(_tabs[i]);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.library_books_outlined),
              selectedIcon: Icon(Icons.library_books), label: '书架'),
          NavigationDestination(icon: Icon(Icons.rss_feed_outlined),
              selectedIcon: Icon(Icons.rss_feed), label: '网文'),
          NavigationDestination(icon: Icon(Icons.sync_outlined),
              selectedIcon: Icon(Icons.sync), label: '同步'),
          NavigationDestination(icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings), label: '设置'),
        ],
      ),
    );
  }
}
