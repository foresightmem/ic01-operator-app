// lib/features/dashboard/presentation/dashboard_page.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

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
    _futureClients = _loadClients();
    _loadUserRole();
  }

  Future<List<ClientState>> _loadClients() async {
    final supabase = Supabase.instance.client;

    final data = await supabase
        .from('client_states')
        .select()
        .order('name', ascending: true);

    return (data as List<dynamic>)
        .map((row) => ClientState.fromMap(row as Map<String, dynamic>))
        .toList();
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
      if (data is List && data.isNotEmpty) {
        final row = data.first as Map<String, dynamic>;
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
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: color,
            ),
            title: Text(client.name),
            subtitle:
                Text('Stato: $label (${client.worstState})\n$refillInfo'),
            onTap: () async {
              final encodedName = Uri.encodeComponent(client.name);
              await context
                  .push('/clients/${client.clientId}?name=$encodedName');
              if (mounted) {
                _refresh();
              }
            },
          ),
        );
      },
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Clienti oggi',
                      style: TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$todayClients',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: Card(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Clienti domani',
                      style: TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$tomorrowClients',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: Card(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Macchine da refillare',
                      style: TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$machinesToRefillToday',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
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
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<ClientState>>(
          future: _futureClients,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
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
      bottomNavigationBar: NavigationBar(
        selectedIndex: _bottomIndex,
        onDestinationSelected: (index) {
          setState(() {
            _bottomIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: 'Oggi/Domani',
          ),
          NavigationDestination(
            icon: Icon(Icons.list_alt_outlined),
            selectedIcon: Icon(Icons.list_alt),
            label: 'Tutti',
          ),
        ],
      ),
    );
  }
}
