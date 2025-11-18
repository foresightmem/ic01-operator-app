// lib/app/router.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/auth/presentation/login_page.dart';
import '../features/dashboard/presentation/dashboard_page.dart';
import '../features/clients/presentation/client_detail_page.dart';
import '../features/machines/presentation/machine_detail_page.dart';
import '../features/maintenance/presentation/maintenance_tickets_page.dart';


/// Router principale dell'app IC-01.
///
/// Gestisce:
/// - la navigazione tra login e dashboard;
/// - le regole di redirezione in base allo stato di autenticazione.

final GoRouter appRouter = GoRouter(
  // Se l'utente è loggato lo mandiamo alla dashboard,
  // altrimenti il redirect lo porterà al /login.
  
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
    GoRoute(
      path: '/clients/:clientId',
      builder: (context, state) {
        final clientId = state.pathParameters['clientId']!;
        final clientName = state.uri.queryParameters['name'];
        return ClientDetailPage(
          clientId: clientId,
          clientName: clientName,
        );
      },
    ),    
    GoRoute(
      path: '/maintenance',
      builder: (context, state) => const MaintenanceTicketsPage(),
    ),

    GoRoute(
      path: '/machines/:machineId',
      builder: (context, state) {
        final machineId = state.pathParameters['machineId']!;
        return MachineDetailPage(machineId: machineId);
      },
    ),


  ],
);
