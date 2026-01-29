/// ===============================================================
/// FILE: features/dashboard/presentation/dashboard_page.dart
///
/// Dashboard refill operator:
/// - Mostra stato dei clienti assegnati aggregando i consumabili per macchina.
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
/// - La query base sui consumabili (mapping dei campi deve restare coerente).
/// - La gestione di initialTab (usata dal router per /dashboard vs /clients).
/// ===============================================================
library;

// lib/features/dashboard/presentation/dashboard_page.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// ===============================================================
/// DashboardPage
///
/// Dashboard refill operator:
/// - Mostra lo stato dei clienti assegnati aggregando `machine_effective_consumables`.
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
    return ClientState(
      clientId: map['client_id'] as String,
      name: map['name'] as String,
      worstState: map['worst_state'] as String,
      totalMachines: map['total_machines'] as int,
      machinesToRefill: map['machines_to_refill'] as int,
    );
  }
}

class _MachineAggregate {
  final String machineId;
  final String clientId;
  final String clientName;
  double minPercent;
  bool hasEnabledConsumable;

  _MachineAggregate({
    required this.machineId,
    required this.clientId,
    required this.clientName,
    required this.minPercent,
    required this.hasEnabledConsumable,
  });
}

class _ClientAggregate {
  final String clientId;
  String name;
  int totalMachines;
  int machinesToRefill;
  String worstState;

  _ClientAggregate({
    required this.clientId,
    required this.name,
    required this.totalMachines,
    required this.machinesToRefill,
    required this.worstState,
  });
}

class DashboardPage extends StatefulWidget {
  /// initialTab: 0 = Oggi/Domani, 1 = Tutti
  final int initialTab;

  const DashboardPage({
    super.key,
    this.initialTab = 0,
  });

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
        .from('machine_effective_consumables')
        .select(
          'machine_id, machine_code, client_id, client_name, effective_operator_id, consumable_type, capacity_units, current_units, is_enabled',
        )
        .eq('effective_operator_id', user.id);

    final rows = (data as List).cast<Map<String, dynamic>>();
    if (rows.isEmpty) {
      return [];
    }

    final machines = <String, _MachineAggregate>{};
    for (final row in rows) {
      final machineId = row['machine_id'] as String?;
      final clientId = row['client_id'] as String?;
      if (machineId == null || clientId == null) {
        continue;
      }

      final clientName = row['client_name'] as String? ?? 'Cliente';
      final enabled = (row['is_enabled'] as bool?) ?? true;
      final capacity = (row['capacity_units'] as num?)?.toDouble() ?? 0.0;
      final current = (row['current_units'] as num?)?.toDouble() ?? 0.0;

      final aggregate = machines.putIfAbsent(
        machineId,
        () => _MachineAggregate(
          machineId: machineId,
          clientId: clientId,
          clientName: clientName,
          minPercent: 100,
          hasEnabledConsumable: false,
        ),
      );

      if (!enabled) {
        continue;
      }

      final percent = _percentFromUnits(current, capacity);
      aggregate.hasEnabledConsumable = true;
      if (percent < aggregate.minPercent) {
        aggregate.minPercent = percent;
      }
    }

    final clients = <String, _ClientAggregate>{};
    for (final machine in machines.values) {
      final percent = machine.hasEnabledConsumable ? machine.minPercent : 100.0;
      final state = _stateFromPercent(percent);
      final client = clients.putIfAbsent(
        machine.clientId,
        () => _ClientAggregate(
          clientId: machine.clientId,
          name: machine.clientName,
          totalMachines: 0,
          machinesToRefill: 0,
          worstState: 'green',
        ),
      );

      client.totalMachines += 1;
      client.name = machine.clientName;
      if (_severity(state) > _severity(client.worstState)) {
        client.worstState = state;
      }
      if (percent <= 40) {
        client.machinesToRefill += 1;
      }
    }

    final result = clients.values
        .map(
          (client) => ClientState(
            clientId: client.clientId,
            name: client.name,
            worstState: client.worstState,
            totalMachines: client.totalMachines,
            machinesToRefill: client.machinesToRefill,
          ),
        )
        .toList();

    result.sort((a, b) => a.name.compareTo(b.name));
    return result;
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
        return Colors.green;
      case 'yellow':
        return Colors.orange;
      case 'red':
        return Colors.red;
      case 'black':
        return Colors.black;
      default:
        return Colors.grey;
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

  double _percentFromUnits(double current, double capacity) {
    if (capacity <= 0) return 0;
    final percent = (current / capacity) * 100;
    if (percent.isNaN || percent.isInfinite) return 0;
    return percent.clamp(0, 100);
  }

  String _stateFromPercent(double percent) {
    if (percent <= 10) return 'black';
    if (percent <= 20) return 'red';
    if (percent <= 40) return 'yellow';
    return 'green';
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
    final maxSev =
        withSeverity.map((e) => e.sev).reduce((a, b) => a > b ? a : b);
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
    final nextSev =
        levelsBelow.reduce((a, b) => a > b ? a : b); // migliore tra i peggiori sotto
    final tomorrow = withSeverity
        .where((e) => e.sev == nextSev)
        .map((e) => e.client)
        .toList();

    return (today, tomorrow);
  }

  Widget _buildClientList(List<ClientState> clients) {
    if (clients.isEmpty) {
      return const Center(
        child: Text('Nessun cliente in questa sezione.'),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: clients.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final client = clients[index];
        final color = _stateColor(client.worstState);
        final label = _stateLabel(client.worstState);

        final refillInfo = client.machinesToRefill > 0
            ? '${client.machinesToRefill} macchina/e su ${client.totalMachines} da refillare'
            : 'Tutte OK (${client.totalMachines} macchine)';

        return Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () async {
              final encodedName = Uri.encodeComponent(client.name);
              await context
                  .push('/clients/${client.clientId}?name=$encodedName');
              if (mounted) {
                _refresh();
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: ListTile(
                leading: CircleAvatar(
                  radius: 18,
                  backgroundColor: color.withValues(alpha: 0.12),
                  child: Icon(
                    Icons.storefront,
                    color: color,
                    size: 20,
                  ),
                ),
                title: Text(
                  client.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text(
                    'Stato: $label (${client.worstState})\n$refillInfo',
                    style: const TextStyle(fontSize: 13, height: 1.3),
                  ),
                ),
                trailing: const Icon(
                  Icons.chevron_right,
                  color: Colors.grey,
                ),
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
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
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
    final machinesToRefillToday =
        today.fold<int>(0, (sum, c) => sum + c.machinesToRefill);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Card(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                child: _buildKpiBox(
                  title: 'Clienti oggi',
                  value: '$todayClients',
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Card(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                child: _buildKpiBox(
                  title: 'Clienti domani',
                  value: '$tomorrowClients',
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Card(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                child: _buildKpiBox(
                  title: 'Macchine da refillare',
                  value: '$machinesToRefillToday',
                ),
              ),
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
                children: [
                  _buildClientList(today),
                  _buildClientList(tomorrow),
                ],
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
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // Se è un tecnico, non deve usare la dashboard refill
    if (_userRole == 'technician') {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Accesso non consentito'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Il tuo ruolo è Tecnico specializzato.\n'
                  'La sezione refill non è disponibile.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    context.go('/maintenance');
                  },
                  child: const Text('Vai alle manutenzioni straordinarie'),
                ),
              ],
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
          if (user != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Text(
                  user.email ?? '',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
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
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(
                child: Text('Errore nel caricamento: ${snapshot.error}'),
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
