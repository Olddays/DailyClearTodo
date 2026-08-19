import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/chat/chat_screen.dart';
import '../../features/history/history_screen.dart';
import '../../features/onboarding/auth_screen.dart';
import '../../features/settings/change_password_screen.dart';
import '../../features/settings/forgot_password_screen.dart';
import '../../features/settings/set_new_password_screen.dart';
import '../../features/today/today_screen.dart';
import 'main_shell.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final auth = Supabase.instance.client.auth;

  return GoRouter(
    initialLocation: '/chat',
    refreshListenable: GoRouterRefreshStream(auth.onAuthStateChange),
    redirect: (context, state) {
      final loggedIn = auth.currentSession != null;
      final path = state.matchedLocation;
      // /forgot-password is reachable while logged out (from the auth screen).
      // /set-new-password is reached via a password-recovery deep link, which
      // supabase_flutter turns into a temporary session before this route is
      // ever hit -- it must NOT get redirected to /chat just because a
      // session now exists.
      final isPublicPath = path == '/auth' || path == '/forgot-password';
      final isRecoveryPath = path == '/set-new-password';
      if (!loggedIn && !isPublicPath && !isRecoveryPath) return '/auth';
      if (loggedIn && isPublicPath) return '/chat';
      return null;
    },
    routes: [
      GoRoute(path: '/auth', builder: (context, state) => const AuthScreen()),
      GoRoute(path: '/forgot-password', builder: (context, state) => const ForgotPasswordScreen()),
      GoRoute(path: '/set-new-password', builder: (context, state) => const SetNewPasswordScreen()),
      GoRoute(path: '/change-password', builder: (context, state) => const ChangePasswordScreen()),
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
