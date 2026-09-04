/// ===============================================================
/// FILE: features/maintenance/presentation/ticket_detail_page.dart
///
/// Dettaglio singolo ticket di manutenzione:
/// - Route: /maintenance/:ticketId
/// - Carica i dati del ticket dalla view ticket_list (eq ticket_id).
/// - Mostra:
///     - stato (open/assigned/in_progress/closed)
///     - cliente, sede, macchina
///     - descrizione
///     - date principali (created_at, ecc.)
/// - Azioni sul ticket:
///     - open       -> "Prendi in carico"    -> status = assigned
///     - assigned   -> "Avvia intervento"    -> status = in_progress
///     - in_progress-> "Chiudi ticket"       -> status = closed
///
/// COSA TIPICAMENTE SI MODIFICA:
/// - Workflow degli stati (aggiungere 'on_hold', 'canceled', ecc.).
/// - Dettagli mostrati (es. note interne, tempo intervento).
/// - Testi dei bottoni.
///
/// COSA È MEGLIO NON TOCCARE:
/// - La logica che inserisce la visita su chiusura ticket.
/// - L'uso di ticket_id dalla route (pathParameters).
/// ===============================================================
library;

// lib/features/maintenance/presentation/ticket_detail_page.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/app_role_service.dart';
import '../../../core/navigation/navigation_action_sheet.dart';
import '../../../core/navigation/navigation_launcher.dart';
import '../../../core/navigation/navigation_permissions.dart';
import '../../../core/ui/app_design_system.dart';
import '../../public_support/presentation/public_support_page.dart';

class TicketDetailPage extends StatefulWidget {
  final String ticketId;
  const TicketDetailPage({super.key, required this.ticketId});

  @override
  State<TicketDetailPage> createState() => _TicketDetailPageState();
}

class _TicketDetailPageState extends State<TicketDetailPage> {
  Map<String, dynamic>? _ticket;
  bool _loading = true;
  bool _actionLoading = false;

  // Ruolo utente per sola-lettura admin
  String? _role;
  bool _loadingRole = true;

  @override
  void initState() {
    super.initState();
    _loadTicket();
    _loadRole();
  }

  Future<void> _loadRole() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user == null) {
      setState(() {
        _role = null;
        _loadingRole = false;
      });
      return;
    }

    try {
      final data = await supabase
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();

      setState(() {
        _role = data?['role'] as String?;
        _loadingRole = false;
      });
    } catch (_) {
      setState(() {
        _role = null;
        _loadingRole = false;
      });
    }
  }

  Future<void> _loadTicket() async {
    final supabase = Supabase.instance.client;

    try {
      final data = await supabase
          .from('ticket_list')
          .select()
          .eq('ticket_id', widget.ticketId)
          .maybeSingle();

      setState(() {
        _ticket = data;
        _loading = false;
      });
    } catch (e) {
      // ignore: avoid_print
      print("Errore load ticket: $e");
      setState(() => _loading = false);
    }
  }

  Future<void> _updateStatus(String newStatus) async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user == null) return;

    setState(() => _actionLoading = true);

    try {
      final updated = await supabase
          .from('tickets')
          .update({
            'status': newStatus,
            if (newStatus == 'in_progress') 'assigned_technician_id': user.id,
            if (newStatus == 'assigned') 'assigned_technician_id': user.id,
            if (newStatus == 'in_progress')
              'assigned_at': DateTime.now().toIso8601String(),
            if (newStatus == 'resolved')
              'resolved_at': DateTime.now().toIso8601String(),
            if (newStatus == 'resolved')
              'closed_at': DateTime.now().toIso8601String(),
          })
          .eq('id', widget.ticketId)
          .select('id')
          .maybeSingle();

      if (updated == null) {
        throw Exception(
          'Ticket non aggiornato: permessi insufficienti o ticket non più disponibile.',
        );
      }

      // Se risolto -> crea una visita
      if (newStatus == 'resolved') {
        await supabase.from('visits').insert({
          'operator_id': user.id,
          'client_id': _ticket!['client_id'],
          'site_id': _ticket!['site_id'],
          'ticket_id': widget.ticketId,
          'visit_type': 'maintenance',
          'notes': 'Ticket chiuso tramite app',
        });
      }

      await _loadTicket();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore aggiornamento ticket: $e')),
      );
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'open':
        return AppColors.danger;
      case 'assigned':
        return AppColors.warning;
      case 'in_progress':
        return AppColors.info;
      case 'resolved':
      case 'closed':
        return AppColors.success;
      case 'cancelled':
        return AppColors.muted;
      default:
        return AppColors.muted;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'open':
        return 'Aperto';
      case 'assigned':
        return 'Assegnato';
      case 'in_progress':
        return 'In corso';
      case 'resolved':
      case 'closed':
        return 'Risolto';
      case 'cancelled':
        return 'Annullato';
      default:
        return status;
    }
  }

  String _formatDurationSeconds(dynamic seconds) {
    final value = (seconds as num?)?.toInt();
    if (value == null || value < 0) return '-';
    final minutes = value ~/ 60;
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final restMinutes = minutes % 60;
    if (hours < 24) return '$hours h $restMinutes min';
    final days = hours ~/ 24;
    final restHours = hours % 24;
    return '$days g $restHours h';
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final bool isAdmin = _role == 'admin';

    return Scaffold(
      appBar: AppBar(
        // Admin: back esplicito verso la lista manutenzioni
        leading: isAdmin
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.go('/maintenance'),
              )
            : null,
        title: const Text('Dettaglio ticket'),
        actions: [
          if (user != null) AppUserEmailAction(email: user.email),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await Supabase.instance.client.auth.signOut();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
      body: (_loading || _loadingRole)
          ? const AppLoading()
          : _ticket == null
          ? const AppEmptyState(
              title: 'Ticket non trovato',
              icon: Icons.confirmation_number_outlined,
            )
          : _buildDetail(),
    );
  }

  Widget _buildDetail() {
    final t = _ticket!;
    final statusColor = _statusColor(t['status']);
    final canOpenNavigator = canUseExternalNavigation(AppRole.fromValue(_role));
    final siteDestination = _siteDestinationFromTicket(t);

    return ListView(
      padding: context.responsive.pagePadding,
      children: [
        AppSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  Text(
                    t['client_name'] as String? ?? 'Cliente',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  AppStatusPill(
                    label: _statusLabel(t['status']),
                    color: statusColor,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              _detailLine('Sede', t['site_name'] as String?),
              _detailLine('Macchina', t['machine_code'] as String?),
              if (t['reason'] != null)
                _detailLine(
                  'Motivo',
                  publicTicketReasonLabel(t['reason'] as String),
                ),
              if (canOpenNavigator && siteDestination.canNavigate) ...[
                const SizedBox(height: AppSpacing.sm),
                SiteNavigationButton(destination: siteDestination),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        if (t['description'] != null &&
            (t['description'] as String).trim().isNotEmpty)
          AppSectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Descrizione',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  t['description'],
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        if (t['description'] != null &&
            (t['description'] as String).trim().isNotEmpty)
          const SizedBox(height: AppSpacing.md),

        AppSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tempi', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.xs),
              _detailLine(
                'Aperto il',
                DateTime.parse(
                  t['created_at'],
                ).toLocal().toString().split('.').first,
              ),
              if (t['resolved_at'] != null)
                _detailLine(
                  'Risolto il',
                  DateTime.parse(
                    t['resolved_at'],
                  ).toLocal().toString().split('.').first,
                ),
              _detailLine(
                'Tempo risoluzione',
                _formatDurationSeconds(t['resolution_time_seconds']),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        // AZIONI
        AppSectionCard(
          child: _actionLoading
              ? const AppLoading(label: 'Aggiornamento ticket')
              : _buildActions(t),
        ),
      ],
    );
  }

  SiteNavigationDestination _siteDestinationFromTicket(Map<String, dynamic> t) {
    return SiteNavigationDestination(
      siteId: t['site_id'] as String?,
      siteName: t['site_name'] as String? ?? 'Sede',
      address: t['site_address'] as String?,
      city: t['site_city'] as String?,
    );
  }

  Widget _detailLine(String label, String? value) {
    final safeValue = (value ?? '').trim().isEmpty ? '-' : value!.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: context.responsive.isCompact ? 108 : 150,
            child: Text(
              '$label:',
              style: const TextStyle(
                color: AppColors.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(child: Text(safeValue)),
        ],
      ),
    );
  }

  Widget _buildActions(Map<String, dynamic> t) {
    final status = t['status'];
    final assignedTech = t['assigned_technician_id'];
    final currentUser = Supabase.instance.client.auth.currentUser;

    final bool assignedToMe = assignedTech == currentUser?.id;
    final bool isAdmin = _role == 'admin';

    if (isAdmin) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton(
            onPressed: status == 'open' ? null : () => _updateStatus('open'),
            child: const Text('Riapri'),
          ),
          OutlinedButton(
            onPressed: status == 'in_progress'
                ? null
                : () => _updateStatus('in_progress'),
            child: const Text('In corso'),
          ),
          ElevatedButton(
            onPressed: status == 'resolved' || status == 'closed'
                ? null
                : () => _updateStatus('resolved'),
            child: const Text('Risolvi'),
          ),
          OutlinedButton(
            onPressed: status == 'cancelled'
                ? null
                : () => _updateStatus('cancelled'),
            child: const Text('Annulla'),
          ),
        ],
      );
    }

    // 👷 Tecnico: logica originale
    if (status == 'resolved' || status == 'closed') {
      return const Text(
        'Ticket risolto',
        style: TextStyle(fontSize: 16, color: AppColors.success),
      );
    }

    if (status == 'cancelled') {
      return const Text(
        'Ticket annullato',
        style: TextStyle(fontSize: 16, color: AppColors.muted),
      );
    }

    if (status == 'open') {
      return ElevatedButton(
        onPressed: () => _updateStatus('assigned'),
        child: const Text('Prendi in carico'),
      );
    }

    if (status == 'assigned' && assignedToMe) {
      return ElevatedButton(
        onPressed: () => _updateStatus('in_progress'),
        child: const Text('Avvia intervento'),
      );
    }

    if (status == 'in_progress' && assignedToMe) {
      return ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
        onPressed: () => _updateStatus('resolved'),
        child: const Text('Risolvi ticket'),
      );
    }

    return const Text(
      'Assegnato ad altro tecnico',
      style: TextStyle(color: AppColors.warning),
    );
  }
}
