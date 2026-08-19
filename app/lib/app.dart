import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/router/app_router.dart';

class DailyClearApp extends ConsumerStatefulWidget {
  const DailyClearApp({super.key});

  @override
  ConsumerState<DailyClearApp> createState() => _DailyClearAppState();
}

class _DailyClearAppState extends ConsumerState<DailyClearApp> {
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    // supabase_flutter's built-in deep link handling (detectSessionInUri,
    // on by default) turns a password-recovery link into a temporary
    // session and fires this event -- that's our cue to route to the
    // "set a new password" screen rather than dumping the user on /chat.
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.passwordRecovery) {
        ref.read(appRouterProvider).go('/set-new-password');
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: '日清',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.deepOrange, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.deepOrange,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      routerConfig: router,
    );
  }
}
