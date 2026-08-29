/// ===============================================================
/// FILE: features/dashboard/presentation/dashboard_page.dart
///
/// Dashboard refill operator:
/// - Mostra stato dei clienti assegnati usando la view client_states.
/// - Gestisce due modalità:
///     - initialTab = 0: "Oggi/Domani"
///     - initialTab = 1: "Tutti i clienti"
/// - Calcola internamente:
///     - quali clienti sono oggi
///     - quali sono domani
///     in base alla severità (black > red > yellow > green).
/// - Permette tap su un cliente per aprire ClientDetailPage.
/// - Mostra KPI (clienti oggi, clienti domani, macchine da refillare).
/// - Se role == 'technician' blocca l’accesso e propone di andare
///   alla pagina manutenzioni.
///
/// COSA TIPICAMENTE SI MODIFICA:
/// - Logica di split Oggi/Domani.
/// - KPI mostrati in alto.
/// - Layout delle card cliente.
///
/// COSA È MEGLIO NON TOCCARE:
/// - La query base su client_states (mapping dei campi deve restare coerente).
/// - La gestione di initialTab (usata dal router per /dashboard vs /clients).
/// ===============================================================
library;

// lib/features/dashboard/presentation/dashboard_page.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/ui/app_design_system.dart';
import '../../onboarding/presentation/onboarding_dialogs.dart';

/// ===============================================================
/// DashboardPage
///
/// Dashboard refill operator:
/// - Mostra lo stato dei clienti assegnati usando la view `client_states`.
/// - Due modalità:
///     - initialTab = 0: "Oggi/Domani"
///     - initialTab = 1: "Tutti i clienti"
/// - Calcola internamente quali clienti sono oggi/domani
///   in base alla severità dello stato (black > red > yellow > green).
/// - Permette tap su un cliente per aprire ClientDetailPage.
/// - Mostra KPI rapidi (clienti oggi, domani, macchine da refillare).
/// - Se role == 'technician' blocca l’accesso e invita a usare /maintenance.
/// ===============================================================

/// Modello per rappresentare lo stato di un cliente
class ClientState {
  final String clientId;
  final String name;
  final String worstState;
  final int totalMachines;
  final int machinesToRefill;

  ClientState({
    required this.clientId,
    required this.name,
    required this.worstState,
    required this.totalMachines,
    required this.machinesToRefill,
  });

  factory ClientState.fromMap(Map<String, dynamic> map) {
    String stringOrEmpty(dynamic value) =>
        value == null ? '' : value.toString();
    int intOrZero(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    String stateFromRank(int rank) {
      switch (rank) {
        case 4:
          return 'black';
        case 3:
          return 'red';
        case 2:
          return 'yellow';
        case 1:
          return 'green';
        default:
          return '';
      }
    }

    final rawWorstState = stringOrEmpty(map['worst_state']);
    final worstStateRank = intOrZero(map['worst_state_rank']);
    final computedWorstState = rawWorstState.isNotEmpty
        ? rawWorstState
        : stateFromRank(worstStateRank);

    return ClientState(
      clientId: stringOrEmpty(map['client_id']),
      name: stringOrEmpty(map['name']),
      worstState: computedWorstState.isEmpty ? 'unknown' : computedWorstState,
      totalMachines: intOrZero(map['total_machines']),
      machinesToRefill: intOrZero(map['machines_to_refill']),
    );
  }
}

class DashboardPage extends StatefulWidget {
  /// initialTab: 0 = Oggi/Domani, 1 = Tutti
  final int initialTab;

  const DashboardPage({super.key, this.initialTab = 0});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late Future<List<ClientState>> _futureClients;

  // 0 = Oggi/Domani, 1 = Tutti i clienti
  int _bottomIndex = 0;

  // ruolo utente (refill_operator, technician, admin)
  String? _userRole;
  bool _roleLoading = true;

  @override
  void initState() {
    super.initState();
    _bottomIndex = widget.initialTab;
    _futureClients = _loadClients();
    _loadUserRole();
  }

  Future<List<ClientState>> _loadClients() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    // se non c'è utente loggato, non mostriamo nulla
    if (user == null) {
      return [];
    }

    final data = await supabase
        .from('client_states_effective')
        .select()
        .eq('assigned_operator_id', user.id) // 👈 filtro per operatore corrente
        .order('name', ascending: true);

    final clientsById = <String, ClientState>{
      for (final client in (data as List<dynamic>).map(
        (row) => ClientState.fromMap(row as Map<String, dynamic>),
      ))
        client.clientId: client,
    };

    final accessibleClients = await supabase
        .from('clients')
        .select('id, name')
        .order('name', ascending: true);

    for (final row
        in (accessibleClients as List).cast<Map<String, dynamic>>()) {
      final clientId = (row['id'] as String?) ?? '';
      if (clientId.isEmpty || clientsById.containsKey(clientId)) continue;
      clientsById[clientId] = ClientState(
        clientId: clientId,
        name: (row['name'] as String?) ?? 'Senza nome',
        worstState: 'unknown',
        totalMachines: 0,
        machinesToRefill: 0,
      );
    }

    final clients = clientsById.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return clients;
  }

  Future<void> _loadUserRole() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user == null) {
      setState(() {
        _userRole = null;
        _roleLoading = false;
      });
      return;
    }

    try {
      final data = await supabase
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .limit(1);

      String? role;
      if (data.isNotEmpty) {
        final row = data.first;
        role = row['role'] as String?;
      }

      setState(() {
        _userRole = role;
        _roleLoading = false;
      });
    } catch (_) {
      setState(() {
        _userRole = null;
        _roleLoading = false;
      });
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _futureClients = _loadClients();
    });
  }

  Color _stateColor(String state) {
    switch (state) {
      case 'green':
        return AppColors.success;
      case 'yellow':
        return AppColors.warning;
      case 'red':
        return AppColors.danger;
      case 'black':
        return AppColors.stopped;
      default:
        return AppColors.muted;
    }
  }

  String _stateLabel(String state) {
    switch (state) {
      case 'green':
        return 'OK';
      case 'yellow':
        return 'Attenzione';
      case 'red':
        return 'Critico';
      case 'black':
        return 'Fermo';
      default:
        return 'Sconosciuto';
    }
  }

  int _severity(String state) {
    switch (state) {
      case 'black':
        return 3;
      case 'red':
        return 2;
      case 'yellow':
        return 1;
      case 'green':
      default:
        return 0;
    }
  }

  /// Divide i clienti tra "oggi" e "domani" seguendo la logica:
  /// - se esistono red/black: oggi = red/black, domani = yellow
  /// - altrimenti: oggi = peggiori, domani = livello subito sotto (se esiste)
  (List<ClientState> today, List<ClientState> tomorrow) _splitTodayTomorrow(
    List<ClientState> all,
  ) {
    if (all.isEmpty) return (<ClientState>[], <ClientState>[]);

    final withSeverity = all
        .map((c) => (client: c, sev: _severity(c.worstState)))
        .toList();

    final hasCritical = withSeverity.any((e) => e.sev >= 2);
    if (hasCritical) {
      final today = withSeverity
          .where((e) => e.sev >= 2) // red o black
          .map((e) => e.client)
          .toList();
      final tomorrow = withSeverity
          .where((e) => e.sev == 1) // yellow
          .map((e) => e.client)
          .toList();
      return (today, tomorrow);
    }

    // nessun red/black: usiamo il livello peggiore disponibile
    final maxSev = withSeverity
        .map((e) => e.sev)
        .reduce((a, b) => a > b ? a : b);
    final today = withSeverity
        .where((e) => e.sev == maxSev)
        .map((e) => e.client)
        .toList();

    final levelsBelow = withSeverity
        .map((e) => e.sev)
        .where((sev) => sev < maxSev)
        .toSet();
    if (levelsBelow.isEmpty) {
      return (today, <ClientState>[]);
    }
    final nextSev = levelsBelow.reduce(
      (a, b) => a > b ? a : b,
    ); // migliore tra i peggiori sotto
    final tomorrow = withSeverity
        .where((e) => e.sev == nextSev)
        .map((e) => e.client)
        .toList();

    return (today, tomorrow);
  }

  Widget _buildClientList(List<ClientState> clients) {
    if (clients.isEmpty) {
      return const AppEmptyState(
        title: 'Nessun cliente in questa sezione',
        message: 'Quando ci sono priorita operative le trovi qui.',
        icon: Icons.storefront_outlined,
      );
    }

    return ListView.separated(
      padding: context.responsive.pagePadding,
      itemCount: clients.length,
      separatorBuilder: (context, index) =>
          const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        final client = clients[index];
        final color = _stateColor(client.worstState);
        final label = _stateLabel(client.worstState);

        final refillInfo = client.machinesToRefill > 0
            ? '${client.machinesToRefill} macchina/e su ${client.totalMachines} da refillare'
            : 'Tutte OK (${client.totalMachines} macchine)';

        return Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadii.md),
            onTap: () async {
              final encodedName = Uri.encodeComponent(client.name);
              await context.push(
                '/clients/${client.clientId}?name=$encodedName',
              );
              if (mounted) {
                _refresh();
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: ListTile(
                leading: CircleAvatar(
                  radius: 18,
                  backgroundColor: color.withValues(alpha: 0.12),
                  child: Icon(Icons.storefront, color: color, size: 20),
                ),
                title: Text(
                  client.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xxs),
                  child: Text(
                    'Stato: $label (${client.worstState})\n$refillInfo',
                    style: const TextStyle(fontSize: 13, height: 1.3),
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Box KPI riusabile
  Widget _buildKpiBox({
    required String title,
    required String value,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(title, style: theme.textTheme.bodySmall)),
            Icon(icon, size: 18, color: AppColors.petroleum),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          value,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  /// KPI operativi (no storici): clienti oggi/domani + macchine da refillare oggi
  Widget _buildKpiRow(
    List<ClientState> all,
    List<ClientState> today,
    List<ClientState> tomorrow,
  ) {
    final todayClients = today.length;
    final tomorrowClients = tomorrow.length;
    final machinesToRefillToday = today.fold<int>(
      0,
      (sum, c) => sum + c.machinesToRefill,
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        context.responsive.pagePadding.left,
        AppSpacing.sm,
        context.responsive.pagePadding.right,
        AppSpacing.xs,
      ),
      child: AppAdaptiveGrid(
        minTileWidth: 160,
        maxColumns: 3,
        childAspectRatio: 1.8,
        children: [
          AppSectionCard(
            child: _buildKpiBox(
              title: 'Clienti oggi',
              value: '$todayClients',
              icon: Icons.today_outlined,
            ),
          ),
          AppSectionCard(
            child: _buildKpiBox(
              title: 'Clienti domani',
              value: '$tomorrowClients',
              icon: Icons.event_available_outlined,
            ),
          ),
          AppSectionCard(
            child: _buildKpiBox(
              title: 'Macchine da refillare',
              value: '$machinesToRefillToday',
              icon: Icons.inventory_2_outlined,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(List<ClientState> clients) {
    final (today, tomorrow) = _splitTodayTomorrow(clients);

    if (_bottomIndex == 0) {
      // Tab "Oggi/Domani"
      return DefaultTabController(
        length: 2,
        child: Column(
          children: [
            _buildKpiRow(clients, today, tomorrow),
            const TabBar(
              tabs: [
                Tab(text: 'Oggi'),
                Tab(text: 'Domani'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [_buildClientList(today), _buildClientList(tomorrow)],
              ),
            ),
          ],
        ),
      );
    } else {
      // Tab "Tutti i clienti" (inclusi i verdi)
      return Column(
        children: [
          _buildKpiRow(clients, today, tomorrow),
          Expanded(child: _buildClientList(clients)),
        ],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;

    if (_roleLoading) {
      return const Scaffold(body: AppLoading());
    }

    // Se è un tecnico, non deve usare la dashboard refill
    if (_userRole == 'technician') {
      return Scaffold(
        appBar: AppBar(title: const Text('Accesso non consentito')),
        body: Center(
          child: AppPage(
            maxWidth: context.responsive.operatorMaxWidth,
            child: AppEmptyState(
              icon: Icons.lock_outline,
              title: 'Sezione refill non disponibile',
              message:
                  'Il tuo ruolo e Tecnico specializzato. Usa la sezione manutenzioni straordinarie.',
              action: ElevatedButton.icon(
                onPressed: () {
                  context.go('/maintenance');
                },
                icon: const Icon(Icons.build_outlined),
                label: const Text('Vai alle manutenzioni straordinarie'),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _bottomIndex == 0
              ? 'Clienti da gestire'
              : 'Tutti i clienti assegnati',
        ),
        actions: [
          IconButton(
            tooltip: 'Nuovo cliente',
            icon: const Icon(Icons.person_add_alt_1),
            onPressed: () async {
              final created = await showCreateClientDialog(context);
              if (created && mounted) {
                _refresh();
              }
            },
          ),
          IconButton(
            tooltip: 'Nuova macchina',
            icon: const Icon(Icons.add_business),
            onPressed: () async {
              final created = await showCreateMachineDialog(context);
              if (created && mounted) {
                _refresh();
              }
            },
          ),
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
        child: FutureBuilder<List<ClientState>>(
          future: _futureClients,
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

            final clients = snapshot.data ?? [];
            return _buildBody(clients);
          },
        ),
      ),
    );
  }
}
