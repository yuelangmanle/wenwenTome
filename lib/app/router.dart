import 'package:go_router/go_router.dart';
import '../features/library/presentation/library_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const LibraryScreen(),
    ),
  ],
);
