// lib/features/dashboard/presentation/dashboard_page.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Modello per rappresentare lo stato di un cliente
class ClientState {
  final String clientId;
  final String name;
  final String worstState;

  ClientState({
    required this.clientId,
    required this.name,
    required this.worstState,
  });

  factory ClientState.fromMap(Map<String, dynamic> map) {
    return ClientState(
      clientId: map['client_id'] as String,
      name: map['name'] as String,
      worstState: map['worst_state'] as String,
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

  @override
  void initState() {
    super.initState();
    _futureClients = _loadClients();
  }

  /// Legge la view `client_states` da Supabase.
  /// Grazie alle RLS sulle machines, l'operatore vedrà solo i clienti
  /// con macchine a lui assegnate.
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

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Clienti da gestire'),
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

            if (clients.isEmpty) {
              return const Center(
                child: Text(
                  'Nessun cliente da mostrare.\n'
                  'Verifica di aver creato macchine e assegnato l’operatore.',
                  textAlign: TextAlign.center,
                ),
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

                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: color,
                    ),
                    title: Text(client.name),
                    subtitle: Text('Stato: $label (${client.worstState})'),
                    onTap: () {
                      // TODO: passo successivo -> dettaglio cliente con lista macchine
                    },
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
