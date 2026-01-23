/// ===============================================================
/// FILE: app/router.dart
///
/// Definisce tutte le route dell'app tramite GoRouter:
/// - Login (/login)
/// - Reset password (/reset-password)
/// - Area operatori (con bottom nav via ShellRoute + MainShell):
///     - Dashboard (/dashboard, /clients)
///     - Dettaglio cliente (/clients/:clientId)
///     - Dettaglio macchina (/machines/:machineId)
///     - Manutenzioni straordinarie:
///         - Lista ticket (/maintenance)
///         - Dettaglio ticket (/maintenance/:ticketId)
/// - Area admin (SENZA bottom nav):
///     - Dashboard admin (/admin)
///     - Clienti admin (/admin/clients, /admin/clients/:clientId)
///     - Coverage (/admin/coverage, /admin/coverage/:unavailabilityId)
///     - Config serbatoi (/admin/machine-config)
///     - Attività (/admin/activities)
///
/// Usa una ShellRoute con MainShell SOLO per l'area operatori.
/// ===============================================================
library;

// lib/app/router.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ic01_operator_app/features/admin/presentation/admin_activities_page.dart';
import 'package:ic01_operator_app/features/admin/presentation/admin_client_detail_page.dart';
import 'package:ic01_operator_app/features/admin/presentation/admin_clients_overview_page.dart';
import 'package:ic01_operator_app/features/admin/presentation/admin_coverage_page.dart';
import 'package:ic01_operator_app/features/admin/presentation/admin_coverage_plan_page.dart';
import 'package:ic01_operator_app/features/admin/presentation/admin_dashboard_page.dart';
import 'package:ic01_operator_app/features/admin/presentation/admin_machine_config_page.dart';
import 'package:ic01_operator_app/models/admin_event.dart';

import '../features/auth/presentation/login_page.dart';
import '../features/auth/presentation/reset_password_page.dart';
import '../features/dashboard/presentation/dashboard_page.dart';
import '../features/clients/presentation/client_detail_page.dart';
import '../features/machines/presentation/machine_detail_page.dart';
import '../features/maintenance/presentation/maintenance_tickets_page.dart';
import '../features/maintenance/presentation/ticket_detail_page.dart';
import 'main_shell.dart';

/// Router principale dell'app IC-01.
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
    // =========================
    // AUTH (fuori dalla shell)
    // =========================
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginPage(),
    ),
    GoRoute(
      path: '/reset-password',
      builder: (context, state) => const ResetPasswordPage(),
    ),

    // =========================
    // ADMIN (fuori dalla shell)
    // =========================
    GoRoute(
      path: '/admin',
      name: 'adminDashboard',
      builder: (context, state) => const AdminDashboardPage(),
    ),
    GoRoute(
      path: '/admin/clients',
      builder: (context, state) => const AdminClientsOverviewPage(),
    ),
    GoRoute(
      path: '/admin/clients/:clientId',
      builder: (context, state) {
        final clientId = state.pathParameters['clientId']!;
        return AdminClientDetailPage(clientId: clientId);
      },
    ),
    GoRoute(
      path: '/admin/coverage',
      builder: (context, state) => const AdminCoveragePage(),
    ),
    GoRoute(
      path: '/admin/coverage/:unavailabilityId',
      builder: (context, state) {
        final id = state.pathParameters['unavailabilityId']!;
        return AdminCoveragePlanPage(unavailabilityId: id);
      },
    ),
    GoRoute(
      path: '/admin/machine-config',
      builder: (context, state) => const AdminMachineConfigPage(),
    ),
    GoRoute(
      path: '/admin/activities',
      builder: (context, state) {
        final raw = state.extra;

        if (raw == null) {
          return const AdminActivitiesPage(events: <AdminEvent>[]);
        }

        if (raw is List) {
          final converted = <AdminEvent>[];

          for (final item in raw) {
            final d = item as dynamic; // runtime: _AdminEvent
            converted.add(
              AdminEvent(
                timestamp: d.timestamp as DateTime,
                type: d.type as String,
                title: d.title as String,
                subtitle: d.subtitle as String,
                icon: d.icon as IconData,
              ),
            );
          }

          return AdminActivitiesPage(events: converted);
        }

        return const AdminActivitiesPage(events: <AdminEvent>[]);
      },
    ),

    // =========================
    // SHELL OPERATORI
    // =========================
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
          builder: (context, state) => const DashboardPage(initialTab: 0),
        ),
        GoRoute(
          path: '/clients',
          builder: (context, state) => const DashboardPage(initialTab: 1),
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
      ],
    ),
  ],
);
