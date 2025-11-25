/// ===============================================================
/// FILE: app/router.dart
///
/// Definisce tutte le route dell'app tramite GoRouter:
/// - Login (/login)
/// - Dashboard refill (/dashboard, /clients)
/// - Dettaglio cliente (/clients/:clientId)
/// - Dettaglio macchina (/machines/:machineId)
/// - Manutenzioni straordinarie:
///     - Lista ticket (/maintenance)
///     - Dettaglio ticket (/maintenance/:ticketId)
///
/// Usa una ShellRoute con MainShell per avere la bottom nav fissa.
///
/// COSA TIPICAMENTE SI MODIFICA:
/// - Aggiunta nuove pagine (nuove GoRoute).
/// - Cambiare il redirect in base allo stato di login.
///
/// COSA È MEGLIO NON TOCCARE:
/// - La logica di redirect login -> dashboard e viceversa.
/// - La struttura della ShellRoute (altrimenti sparisce la bottom nav).
/// ===============================================================
library;

// lib/app/router.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/auth/presentation/login_page.dart';
import '../features/auth/presentation/reset_password_page.dart';
import '../features/dashboard/presentation/dashboard_page.dart';
import '../features/clients/presentation/client_detail_page.dart';
import '../features/machines/presentation/machine_detail_page.dart';
import '../features/maintenance/presentation/maintenance_tickets_page.dart';
import 'main_shell.dart';
import '../features/maintenance/presentation/ticket_detail_page.dart';


/// Router principale dell'app IC-01.
///
/// Usa una ShellRoute con MainShell per avere una bottom nav fissa
/// su dashboard, clienti e manutenzioni.
final GoRouter appRouter = GoRouter(
  initialLocation: '/dashboard',
  redirect: (BuildContext context, GoRouterState state) {
    final session = Supabase.instance.client.auth.currentSession;
    final bool loggedIn = session != null;

    final String location = state.uri.toString();
    final bool goingToLogin = location == '/login';

    if (!loggedIn && !goingToLogin) {
      return '/login';
    }

    if (loggedIn && goingToLogin) {
      return '/dashboard';
    }

    return null;
  },
  routes: <RouteBase>[
    // Login fuori dalla shell
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginPage(),
    ),

    // ShellRoute con bottom nav persistente
    ShellRoute(
      builder: (context, state, child) {
        final location = state.uri.toString();
        int index = 0;

        if (location.startsWith('/dashboard')) {
          index = 0;
        } else if (location.startsWith('/clients')) {
          index = 1;
        } else if (location.startsWith('/maintenance')) {
          index = 2;
        }

        return MainShell(
          currentIndex: index,
          child: child,
        );
      },
      routes: <RouteBase>[
        GoRoute(
          path: '/dashboard',
          builder: (context, state) =>
              const DashboardPage(initialTab: 0), // Oggi/Domani
        ),
        GoRoute(
          path: '/clients',
          builder: (context, state) =>
              const DashboardPage(initialTab: 1), // Tutti
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
          path: '/machines/:machineId',
          builder: (context, state) {
            final machineId = state.pathParameters['machineId']!;
            return MachineDetailPage(machineId: machineId);
          },
        ),
        GoRoute(
          path: '/maintenance',
          builder: (context, state) => const MaintenanceTicketsPage(),
        ),
        GoRoute(
          path: '/maintenance/:ticketId',
          builder: (context, state) {
            final id = state.pathParameters['ticketId']!;
            return TicketDetailPage(ticketId: id);
          },
        ),
        GoRoute(
          path: '/reset-password',
          builder: (context, state) => const ResetPasswordPage(),
        ),
      ],
    ),
  ],
);
