/// ===============================================================
/// FILE: features/maintenance/presentation/maintenance_tickets_page.dart
///
/// Lista chiamate di manutenzione straordinaria:
/// - Legge dalla view ticket_list:
///     - ticket_id, status, description, created_at
///     - client_name, site_name, machine_code
/// - Mostra tutti i ticket con stato 'open' o 'assigned'.
/// - Azioni rapide:
///     - "Prendo in carico" -> assegna il ticket all'utente corrente.
/// - Tap sulla card -> apre TicketDetailPage (/maintenance/:ticketId).
/// - AppBar mostra email utente + icona logout.
///
/// COSA TIPICAMENTE SI MODIFICA:
/// - Filtri sui ticket (aggiungere 'in_progress', filtrare per tecnico, ecc.).
/// - Layout delle card, testi, colori.
/// - Logica di assegnazione (es. evitare double-assign).
///
/// COSA È MEGLIO NON TOCCARE:
/// - La query base su ticket_list (nome dei campi ticket_id, client_name...).
/// - La costruzione di TicketItem.fromMap (deve restare allineata alla view).
/// ===============================================================
library;

// lib/features/maintenance/presentation/maintenance_tickets_page.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/app_role_service.dart';
import '../../../core/navigation/navigation_action_sheet.dart';
import '../../../core/navigation/navigation_launcher.dart';
import '../../../core/navigation/navigation_permissions.dart';
import '../../../core/ui/app_design_system.dart';
import '../../public_support/presentation/public_support_page.dart';

/// ===============================================================
/// TicketItem
///
/// Modello per rappresentare un ticket nella lista
/// ===============================================================
class TicketItem {
  final String ticketId;
  final String status;
  final String? reason;
  final String? description;
  final DateTime createdAt;
  final DateTime? resolvedAt;
  final int? resolutionTimeSeconds;
  final String clientName;
  final String? siteId;
  final String? siteName;
  final String? siteAddress;
  final String? siteCity;
  final String machineCode;
  final String? assignedTechnicianId;
  final String? assignedTechnicianName;
  final String? assignedOperatorId;
  final String? assignedOperatorName;

  TicketItem({
    required this.ticketId,
    required this.status,
    required this.reason,
    required this.description,
    required this.createdAt,
    required this.resolvedAt,
    required this.resolutionTimeSeconds,
    required this.clientName,
    required this.siteId,
    required this.siteName,
    required this.siteAddress,
    required this.siteCity,
    required this.machineCode,
    required this.assignedTechnicianId,
    required this.assignedTechnicianName,
    required this.assignedOperatorId,
    required this.assignedOperatorName,
  });

  factory TicketItem.fromMap(Map<String, dynamic> map) {
    return TicketItem(
      ticketId: map['ticket_id'] as String,
      status: map['status'] as String,
      reason: map['reason'] as String?,
      description: map['description'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      resolvedAt: map['resolved_at'] == null
          ? null
          : DateTime.tryParse(map['resolved_at'] as String),
      resolutionTimeSeconds: (map['resolution_time_seconds'] as num?)?.toInt(),
      clientName: map['client_name'] as String? ?? 'Cliente',
      siteId: map['site_id'] as String?,
      siteName: map['site_name'] as String?,
      siteAddress: map['site_address'] as String?,
      siteCity: map['site_city'] as String?,
      machineCode: map['machine_code'] as String? ?? 'N/D',
      assignedTechnicianId: map['assigned_technician_id'] as String?,
      assignedTechnicianName: map['assigned_technician_name'] as String?,
      assignedOperatorId: map['assigned_operator_id'] as String?,
      assignedOperatorName: map['assigned_operator_name'] as String?,
    );
  }

  SiteNavigationDestination get siteDestination => SiteNavigationDestination(
    siteId: siteId,
    siteName: siteName ?? 'Sede',
    address: siteAddress,
    city: siteCity,
  );
}

enum _TicketSortMode { newest, oldest, resolutionDesc, resolutionAsc }

/// ===============================================================
/// MaintenanceTicketsPage
///
/// Lista chiamate di manutenzione straordinaria:
/// - Legge dalla view `ticket_list`.
/// - Mostra ticket con stato 'open' o 'assigned'.
/// - Permette:
///     - "Prendo in carico" → assegna il ticket all'utente corrente.
/// - Tap sulla card → apre TicketDetailPage (/maintenance/:ticketId).
/// - AppBar con email utente + logout.
/// ===============================================================
class MaintenanceTicketsPage extends StatefulWidget {
  const MaintenanceTicketsPage({super.key});

  @override
  State<MaintenanceTicketsPage> createState() => _MaintenanceTicketsPageState();
}

class _MaintenanceTicketsPageState extends State<MaintenanceTicketsPage> {
  late Future<List<TicketItem>> _futureTickets;
  bool _loadingAction = false;
  bool _queryInitialized = false;

  // Ruolo utente (per differenziare admin / technician)
  String? _role;
  bool _loadingRole = true;

  String _statusFilter = 'all';
  String _reasonFilter = 'all';
  String _clientFilter = 'all';
  String _operatorFilter = 'all';
  String _periodFilter = 'all';
  _TicketSortMode _sortMode = _TicketSortMode.newest;

  @override
  void initState() {
    super.initState();
    _futureTickets = _loadTickets();
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

  Future<List<TicketItem>> _loadTickets() async {
    final supabase = Supabase.instance.client;

    final data = await supabase
        .from('ticket_list')
        .select()
        .order('created_at', ascending: false);

    return (data as List<dynamic>)
        .map((row) => TicketItem.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  Future<void> _refresh() async {
    setState(() {
      _futureTickets = _loadTickets();
    });
  }

  Future<void> _assignTicket(TicketItem ticket) async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) return;

    setState(() => _loadingAction = true);

    try {
      final updated = await supabase
          .from('tickets')
          .update({
            'assigned_technician_id': user.id,
            'status': 'assigned',
            'assigned_at': DateTime.now().toIso8601String(),
          })
          .eq('id', ticket.ticketId)
          .select('id')
          .maybeSingle();

      if (updated == null) {
        throw Exception(
          'Ticket non aggiornato: permessi insufficienti o ticket non più disponibile.',
        );
      }

      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Errore assegnazione ticket: $e')));
    } finally {
      if (mounted) setState(() => _loadingAction = false);
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

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    return local.toString().split('.').first;
  }

  String _formatDurationSeconds(int? seconds) {
    if (seconds == null || seconds < 0) return '-';
    final minutes = seconds ~/ 60;
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final restMinutes = minutes % 60;
    if (hours < 24) return '$hours h $restMinutes min';
    final days = hours ~/ 24;
    final restHours = hours % 24;
    return '$days g $restHours h';
  }

  List<TicketItem> _applyFilters(List<TicketItem> input, bool isAdmin) {
    var tickets = input;

    if (!isAdmin) {
      tickets = tickets
          .where((t) => ['open', 'assigned', 'in_progress'].contains(t.status))
          .toList();
    }

    if (_statusFilter != 'all') {
      tickets = tickets.where((t) => t.status == _statusFilter).toList();
    }
    if (_reasonFilter != 'all') {
      tickets = tickets.where((t) => t.reason == _reasonFilter).toList();
    }
    if (_clientFilter != 'all') {
      tickets = tickets.where((t) => t.clientName == _clientFilter).toList();
    }
    if (_operatorFilter != 'all') {
      tickets = tickets
          .where(
            (t) =>
                (t.assignedTechnicianName ??
                    t.assignedOperatorName ??
                    'Non assegnato') ==
                _operatorFilter,
          )
          .toList();
    }
    if (_periodFilter != 'all') {
      final days = int.tryParse(_periodFilter);
      if (days != null) {
        final since = DateTime.now().subtract(Duration(days: days));
        tickets = tickets.where((t) => t.createdAt.isAfter(since)).toList();
      }
    }

    tickets = [...tickets];
    switch (_sortMode) {
      case _TicketSortMode.newest:
        tickets.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case _TicketSortMode.oldest:
        tickets.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        break;
      case _TicketSortMode.resolutionDesc:
        tickets.sort(
          (a, b) => (b.resolutionTimeSeconds ?? -1).compareTo(
            a.resolutionTimeSeconds ?? -1,
          ),
        );
        break;
      case _TicketSortMode.resolutionAsc:
        tickets.sort(
          (a, b) => (a.resolutionTimeSeconds ?? 1 << 60).compareTo(
            b.resolutionTimeSeconds ?? 1 << 60,
          ),
        );
        break;
    }

    return tickets;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_queryInitialized) return;
    _queryInitialized = true;

    final status = GoRouterState.of(context).uri.queryParameters['status'];
    if (status != null && status.isNotEmpty) {
      _statusFilter = status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;

    // Finché non so il ruolo, non mostro niente (così l'admin non vede bottoni attivi)
    if (_loadingRole) {
      return const Scaffold(body: AppLoading());
    }

    final bool isAdmin = _role == 'admin';

    return Scaffold(
      appBar: AppBar(
        // L'admin ha il tasto indietro verso la dashboard admin
        leading: isAdmin
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.go('/admin'),
              )
            : null,
        title: const Text('Manutenzioni straordinarie'),
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
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<TicketItem>>(
          future: _futureTickets,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const AppLoading();
            }

            if (snapshot.hasError) {
              return AppErrorState(
                message: 'Errore nel caricamento: ${snapshot.error}',
                onRetry: _refresh,
              );
            }

            final rawTickets = snapshot.data ?? [];
            final tickets = _applyFilters(rawTickets, isAdmin);

            if (tickets.isEmpty) {
              return ListView(
                padding: context.responsive.pagePadding,
                children: [
                  if (isAdmin) _buildAdminFilters(rawTickets),
                  const SizedBox(height: AppSpacing.lg),
                  const AppEmptyState(
                    title: 'Nessuna manutenzione trovata',
                    icon: Icons.build_outlined,
                  ),
                ],
              );
            }

            return ListView.separated(
              padding: context.responsive.pagePadding,
              itemCount: tickets.length + (isAdmin ? 1 : 0),
              separatorBuilder: (context, index) =>
                  const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, index) {
                if (isAdmin && index == 0) {
                  return _buildAdminFilters(rawTickets);
                }

                final ticketIndex = isAdmin ? index - 1 : index;
                final t = tickets[ticketIndex];
                final userId = user?.id;
                final isAssignedToMe = t.assignedTechnicianId == userId;
                final isUnassigned = t.assignedTechnicianId == null;
                final statusColor = _statusColor(t.status);

                return Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    onTap: () {
                      // Admin può aprire il dettaglio ma in sola lettura
                      context.push('/maintenance/${t.ticketId}');
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // CLIENTE + STATO
                          Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.xs,
                            children: [
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  minWidth: 160,
                                  maxWidth: 520,
                                ),
                                child: Text(
                                  t.clientName,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                              ),
                              AppStatusPill(
                                label: _statusLabel(t.status),
                                color: statusColor,
                              ),
                            ],
                          ),

                          const SizedBox(height: AppSpacing.xs),

                          // SEDE + MACCHINA
                          Text(
                            [
                              if (t.siteName != null) t.siteName!,
                              'Macchina: ${t.machineCode}',
                            ].join(' • '),
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),

                          const SizedBox(height: AppSpacing.xs),

                          // DESCRIZIONE
                          if (t.description != null &&
                              t.description!.trim().isNotEmpty)
                            Text(
                              t.description!,
                              style: const TextStyle(fontSize: 13, height: 1.3),
                            ),

                          if (t.reason != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              'Motivo: ${publicTicketReasonLabel(t.reason!)}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],

                          if (isAdmin) ...[
                            const SizedBox(height: 6),
                            Text(
                              [
                                'Tecnico: ${t.assignedTechnicianName ?? 'Non assegnato'}',
                                'Operatore: ${t.assignedOperatorName ?? 'N/D'}',
                                'Risoluzione: ${_formatDurationSeconds(t.resolutionTimeSeconds)}',
                              ].join(' • '),
                              style: const TextStyle(fontSize: 12),
                            ),
                            if (t.resolvedAt != null)
                              Text(
                                'Risolto il ${_formatDate(t.resolvedAt!)}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                              ),
                          ],

                          const SizedBox(height: AppSpacing.sm),

                          // FOOTER: data + azione
                          Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.xs,
                            children: [
                              Text(
                                'Aperto il ${_formatDate(t.createdAt)}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.muted,
                                ),
                              ),
                              if (canUseExternalNavigation(
                                    AppRole.fromValue(_role),
                                  ) &&
                                  t.siteDestination.canNavigate)
                                SiteNavigationButton(
                                  destination: t.siteDestination,
                                ),
                              _buildActionsForTicket(
                                t,
                                isAdmin: isAdmin,
                                isAssignedToMe: isAssignedToMe,
                                isUnassigned: isUnassigned,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildActionsForTicket(
    TicketItem ticket, {
    required bool isAdmin,
    required bool isAssignedToMe,
    required bool isUnassigned,
  }) {
    if (_loadingAction) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    // 🔒 ADMIN: sola lettura, nessun bottone
    if (isAdmin) {
      if (ticket.status == 'closed') {
        return const Text(
          'Ticket chiuso',
          style: TextStyle(fontSize: 12, color: AppColors.success),
        );
      }

      if (isAssignedToMe) {
        return const Text(
          'Assegnato a te',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.success,
          ),
        );
      }

      if (isUnassigned) {
        return const Text(
          'Non assegnato',
          style: TextStyle(fontSize: 12, color: AppColors.muted),
        );
      }

      return const Text(
        'Assegnato ad altro tecnico',
        style: TextStyle(fontSize: 12, color: AppColors.warning),
      );
    }

    // 👷 Tecnico: logica originale
    if (isAssignedToMe) {
      return const Text(
        'Assegnato a te',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.success,
        ),
      );
    }

    if (isUnassigned) {
      return TextButton(
        onPressed: () => _assignTicket(ticket),
        child: const Text('Prendo in carico'),
      );
    }

    return const Text(
      'Assegnato ad altro tecnico',
      style: TextStyle(fontSize: 12, color: AppColors.warning),
    );
  }

  Widget _buildAdminFilters(List<TicketItem> tickets) {
    final clients = {for (final ticket in tickets) ticket.clientName}.toList()
      ..sort();
    final operators = {
      for (final ticket in tickets)
        ticket.assignedTechnicianName ??
            ticket.assignedOperatorName ??
            'Non assegnato',
    }.toList()..sort();

    return AppSectionCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Filtri ticket', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              _FilterDropdown(
                label: 'Stato',
                value: _statusFilter,
                items: const {
                  'all': 'Tutti',
                  'open': 'Aperti',
                  'assigned': 'Assegnati',
                  'in_progress': 'In corso',
                  'resolved': 'Risolti',
                  'closed': 'Chiusi storico',
                  'cancelled': 'Annullati',
                },
                onChanged: (value) =>
                    setState(() => _statusFilter = value ?? 'all'),
              ),
              _FilterDropdown(
                label: 'Motivo',
                value: _reasonFilter,
                items: const {
                  'all': 'Tutti',
                  'out_of_stock': 'Scorte finite',
                  'malfunction': 'Malfunzionamento',
                },
                onChanged: (value) =>
                    setState(() => _reasonFilter = value ?? 'all'),
              ),
              _FilterDropdown(
                label: 'Cliente',
                value: _clientFilter,
                items: {
                  'all': 'Tutti',
                  for (final client in clients) client: client,
                },
                onChanged: (value) =>
                    setState(() => _clientFilter = value ?? 'all'),
              ),
              _FilterDropdown(
                label: 'Operatore',
                value: _operatorFilter,
                items: {
                  'all': 'Tutti',
                  for (final operator in operators) operator: operator,
                },
                onChanged: (value) =>
                    setState(() => _operatorFilter = value ?? 'all'),
              ),
              _FilterDropdown(
                label: 'Periodo',
                value: _periodFilter,
                items: const {
                  'all': 'Sempre',
                  '7': 'Ultimi 7 giorni',
                  '30': 'Ultimi 30 giorni',
                  '90': 'Ultimi 90 giorni',
                },
                onChanged: (value) =>
                    setState(() => _periodFilter = value ?? 'all'),
              ),
              SizedBox(
                width: _filterWidth(context),
                child: DropdownButtonFormField<_TicketSortMode>(
                  initialValue: _sortMode,
                  decoration: const InputDecoration(labelText: 'Ordina per'),
                  items: const [
                    DropdownMenuItem(
                      value: _TicketSortMode.newest,
                      child: Text('Apertura recente'),
                    ),
                    DropdownMenuItem(
                      value: _TicketSortMode.oldest,
                      child: Text('Apertura meno recente'),
                    ),
                    DropdownMenuItem(
                      value: _TicketSortMode.resolutionDesc,
                      child: Text('Risoluzione maggiore'),
                    ),
                    DropdownMenuItem(
                      value: _TicketSortMode.resolutionAsc,
                      child: Text('Risoluzione minore'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _sortMode = value);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  double _filterWidth(BuildContext context) => context.responsive.isCompact
      ? context.responsive.width - (AppSpacing.md * 4)
      : 220;
}

class _FilterDropdown extends StatelessWidget {
  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final String value;
  final Map<String, String> items;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final safeValue = items.containsKey(value) ? value : 'all';
    final width = context.responsive.isCompact
        ? context.responsive.width - (AppSpacing.md * 4)
        : 220.0;

    return SizedBox(
      width: width,
      child: DropdownButtonFormField<String>(
        initialValue: safeValue,
        decoration: InputDecoration(labelText: label),
        items: [
          for (final entry in items.entries)
            DropdownMenuItem(
              value: entry.key,
              child: Text(entry.value, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: onChanged,
      ),
    );
  }
}
