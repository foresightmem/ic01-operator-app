// lib/app/router.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/auth/presentation/login_page.dart';
import '../features/dashboard/presentation/dashboard_page.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/dashboard',
  redirect: (BuildContext context, GoRouterState state) {
    final session = Supabase.instance.client.auth.currentSession;
    final bool loggedIn = session != null;

    // Percorso richiesto dall'utente (es. /login, /dashboard)
    final String location = state.uri.toString();
    final bool goingToLogin = location == '/login';

    // Se non sono loggato e non sto andando a /login -> vai a /login
    if (!loggedIn && !goingToLogin) {
      return '/login';
    }

    // Se sono loggato e sto cercando di andare a /login -> vai a /dashboard
    if (loggedIn && goingToLogin) {
      return '/dashboard';
    }

    // Altrimenti nessuna redirezione
    return null;
  },
  routes: <RouteBase>[
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginPage(),
    ),
    GoRoute(
      path: '/dashboard',
      builder: (context, state) => const DashboardPage(),
    ),
  ],
);
