// lib/features/dashboard/presentation/dashboard_page.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';

/// Modello per rappresentare lo stato di un cliente in dashboard.
///
/// Ogni cliente ha:
/// - [clientId]: identificativo univoco (PK sul DB)
/// - [name]: nome del cliente (ragione sociale / label leggibile)
/// - [worstState]: stato "peggiore" tra tutte le macchine assegnate,
///   normalizzato come stringa (es: 'green', 'yellow', 'red', 'black').
class ClientState {
  /// ID univoco del cliente (deriva da `client_id` nella view `client_states`).
  final String clientId;
  /// Nome leggibile del cliente (deriva da `name` nella view `client_states`).
  final String name;
  /// Stato aggregato peggiore del cliente (es. 'green', 'yellow', 'red', 'black').
  final String worstState;

  ClientState({
    required this.clientId,
    required this.name,
    required this.worstState,
  });

/// Costruttore factory che crea un [ClientState] a partire da una mappa.
///
/// È pensato per essere usato direttamente con il risultato di Supabase,
/// dove ogni riga è una `Map<String, dynamic>`.
  factory ClientState.fromMap(Map<String, dynamic> map) {
    return ClientState(
      clientId: map['client_id'] as String,
      name: map['name'] as String,
      worstState: map['worst_state'] as String,
    );
  }
}
/// Pagina principale di dashboard per l'operatore.
///
/// Mostra la lista dei clienti assegnati all'operatore loggato, con:
/// - stato aggregato peggiore (colore + label)
/// - possibilità di refresh tramite [RefreshIndicator]
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  /// Future che carica la lista dei clienti da mostrare in dashboard.
  ///
  /// Viene inizializzato in [initState] e ricalcolato:
  /// - al primo avvio della pagina
  /// - quando l'utente fa pull-to-refresh
  late Future<List<ClientState>> _futureClients;

  @override
  void initState() {
    super.initState();
    _futureClients = _loadClients();
  }

  /// Legge la view `client_states` da Supabase.
  ///
  /// Grazie alle RLS sulle `machines`, l'operatore vedrà solo i clienti
  /// associati a macchine a lui assegnate.
  ///
  /// La view `client_states` si occupa di:
  /// - aggregare le macchine per cliente
  /// - calcolare lo stato "peggiore" per ogni cliente
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

  /// Forza il ricaricamento della lista clienti.
  ///
  /// Usato dal [RefreshIndicator] per effettuare il pull-to-refresh.
  Future<void> _refresh() async {
    setState(() {
      _futureClients = _loadClients();
    });
  }

  /// Restituisce un colore corrispondente allo stato della macchina/cliente.
  ///
  /// Mappa:
  /// - 'green'  → verde  (OK)
  /// - 'yellow' → arancione (attenzione)
  /// - 'red'    → rosso (critico)
  /// - 'black'  → nero (fermo)
  /// - default  → grigio (sconosciuto / non mappato)
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

  /// Restituisce una descrizione testuale leggibile dello stato.
  ///
  /// Mappa:
  /// - 'green'  → 'OK'
  /// - 'yellow' → 'Attenzione'
  /// - 'red'    → 'Critico'
  /// - 'black'  → 'Fermo'
  /// - default  → 'Sconosciuto'
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
                      final encodedName = Uri.encodeComponent(client.name);
                      context.go('/clients/${client.clientId}?name=$encodedName');
                    
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
