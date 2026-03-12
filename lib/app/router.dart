import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/library/data/book_model.dart';
import '../features/library/presentation/library_screen.dart';
import '../features/reader/presentation/local_tts_manager_screen.dart';
import '../features/reader/presentation/reader_screen.dart';
import '../features/search/presentation/search_screen.dart';
import '../features/settings/presentation/about_screen.dart';
import '../features/settings/presentation/book_source_files_screen.dart';
import '../features/settings/presentation/runtime_log_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/settings/presentation/translation_config_screen.dart';
import '../features/sync/presentation/sync_screen.dart';
import '../features/webnovel/presentation/webnovel_cache_screen.dart';
import '../features/webnovel/presentation/webnovel_screen.dart';
import 'runtime_platform.dart';

GoRouter buildAppRouter({String initialLocation = '/'}) {
  final isDesktop =
      detectLocalRuntimePlatform() == LocalRuntimePlatform.windows;

  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            _AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => const LibraryScreen(),
              ),
            ],
          ),
          if (!isDesktop)
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/webnovel',
                  builder: (context, state) => WebNovelScreen(
                    initialBrowserUrl:
                        state.extra is String ? state.extra as String : null,
                  ),
                ),
              ],
            ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/sync',
                builder: (context, state) => const SyncScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (context, state) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/search',
        builder: (context, state) => const SearchScreen(),
      ),
      GoRoute(path: '/about', builder: (context, state) => const AboutScreen()),
      GoRoute(
        path: '/reader',
        builder: (context, state) {
          final book = state.extra;
          if (book is! Book) {
            return const _RouteErrorScreen(message: '缺少书籍参数，无法打开阅读器。');
          }
          return ReaderScreen(book: book);
        },
      ),
      GoRoute(
        path: '/translation-config',
        builder: (context, state) => isDesktop
            ? const SettingsScreen()
            : const TranslationConfigScreen(),
      ),
      GoRoute(
        path: '/runtime-logs',
        builder: (context, state) => const RuntimeLogScreen(),
      ),
      GoRoute(
        path: '/local-tts',
        builder: (context, state) =>
            isDesktop ? const SettingsScreen() : const LocalTtsManagerScreen(),
      ),
      GoRoute(
        path: '/source-files',
        builder: (context, state) => BookSourceFilesScreen(),
      ),
      GoRoute(
        path: '/webnovel-cache',
        builder: (context, state) => WebNovelCacheScreen(),
      ),
      if (isDesktop)
        GoRoute(
          path: '/webnovel',
          builder: (context, state) => BookSourceFilesScreen(),
        ),
    ],
  );
}

final appRouter = buildAppRouter();

class _AppShell extends StatelessWidget {
  const _AppShell({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final isDesktop =
        detectLocalRuntimePlatform() == LocalRuntimePlatform.windows;
    final tabs = isDesktop
        ? const <_ShellTab>[
            _ShellTab(
              icon: Icons.library_books_outlined,
              selectedIcon: Icons.library_books,
              label: '书架',
            ),
            _ShellTab(
              icon: Icons.sync_outlined,
              selectedIcon: Icons.sync,
              label: '同步',
            ),
            _ShellTab(
              icon: Icons.settings_outlined,
              selectedIcon: Icons.settings,
              label: '设置',
            ),
          ]
        : const <_ShellTab>[
            _ShellTab(
              icon: Icons.library_books_outlined,
              selectedIcon: Icons.library_books,
              label: '书架',
            ),
            _ShellTab(
              icon: Icons.rss_feed_outlined,
              selectedIcon: Icons.rss_feed,
              label: '网文',
            ),
            _ShellTab(
              icon: Icons.sync_outlined,
              selectedIcon: Icons.sync,
              label: '同步',
            ),
            _ShellTab(
              icon: Icons.settings_outlined,
              selectedIcon: Icons.settings,
              label: '设置',
            ),
          ];

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) =>
            navigationShell.goBranch(index, initialLocation: index == navigationShell.currentIndex),
        destinations: [
          for (final tab in tabs)
            NavigationDestination(
              icon: Icon(tab.icon),
              selectedIcon: Icon(tab.selectedIcon),
              label: tab.label,
            ),
        ],
      ),
    );
  }
}

class _ShellTab {
  const _ShellTab({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

class _RouteErrorScreen extends StatelessWidget {
  const _RouteErrorScreen({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(message, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}
