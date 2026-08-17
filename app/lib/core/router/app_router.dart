import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/chat/chat_screen.dart';
import '../../features/history/history_screen.dart';
import '../../features/onboarding/auth_screen.dart';
import '../../features/today/today_screen.dart';
import 'main_shell.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final auth = Supabase.instance.client.auth;

  return GoRouter(
    initialLocation: '/chat',
    refreshListenable: GoRouterRefreshStream(auth.onAuthStateChange),
    redirect: (context, state) {
      final loggedIn = auth.currentSession != null;
      final goingToAuth = state.matchedLocation == '/auth';
      if (!loggedIn && !goingToAuth) return '/auth';
      if (loggedIn && goingToAuth) return '/chat';
      return null;
    },
    routes: [
      GoRoute(path: '/auth', builder: (context, state) => const AuthScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => MainShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/chat', builder: (context, state) => const ChatScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/today', builder: (context, state) => const TodayScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/history', builder: (context, state) => const HistoryScreen())]),
        ],
      ),
    ],
  );
});

/// Bridges a Stream (Supabase's auth state changes) into a Listenable so go_router
/// re-evaluates its redirect logic whenever sign-in/sign-out happens.
class GoRouterRefreshStream extends ChangeNotifier {
  late final Stream<dynamic> _subscription;

  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream();
    _subscription.listen((_) => notifyListeners());
  }
}
