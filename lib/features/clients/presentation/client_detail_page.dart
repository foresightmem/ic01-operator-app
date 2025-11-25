/// ===============================================================
/// FILE: features/clients/presentation/client_detail_page.dart
///
/// Dettaglio di un cliente:
/// - Riceve clientId (obbligatorio) e clientName (facoltativo) dalla route.
/// - Carica le macchine del cliente (view client_machines).
/// - Permette tap su una macchina per aprire MachineDetailPage.
///
/// COSA TIPICAMENTE SI MODIFICA:
/// - Come vengono visualizzate le macchine (card, lista, stati colore).
/// - Aggiunta di azioni per cliente (es. "Segna cliente completato oggi").
///
/// COSA È MEGLIO NON TOCCARE:
/// - Il modo in cui legge clientId dalla route (pathParameters).
/// - Il mapping dei campi provenienti da client_machines.
/// ===============================================================
library;

// lib/features/clients/presentation/client_detail_page.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Modello per rappresentare una macchina di un cliente nella lista
class ClientMachine {
  final String machineId;
  final String code;
  final String siteName;
  final double currentFillPercent;
  final String state;

  ClientMachine({
    required this.machineId,
    required this.code,
    required this.siteName,
    required this.currentFillPercent,
    required this.state,
  });

  factory ClientMachine.fromMap(Map<String, dynamic> map) {
    return ClientMachine(
      machineId: map['machine_id'] as String,
      code: map['code'] as String,
      siteName: map['site_name'] as String,
      currentFillPercent:
          (map['current_fill_percent'] as num).toDouble(),
      state: map['state'] as String,
    );
  }
}

/// Pagina di dettaglio cliente: mostra le macchine di quel cliente
class ClientDetailPage extends StatefulWidget {
  final String clientId;
  final String? clientName;

  const ClientDetailPage({
    super.key,
    required this.clientId,
    this.clientName,
  });

  @override
  State<ClientDetailPage> createState() => _ClientDetailPageState();
}

class _ClientDetailPageState extends State<ClientDetailPage> {
  late Future<List<ClientMachine>> _futureMachines;

  @override
  void initState() {
    super.initState();
    _futureMachines = _loadMachines();
  }

  /// Carica le macchine dalla view `client_machines`.
  /// Ora filtrate per:
  ///   - client_id = widget.clientId
  ///   - assigned_operator_id = utente corrente
  Future<List<ClientMachine>> _loadMachines() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user == null) {
      return [];
    }

    final data = await supabase
        .from('client_machines')
        .select()
        .eq('client_id', widget.clientId)
        .eq('assigned_operator_id', user.id)
        .order('code', ascending: true);

    return (data as List<dynamic>)
        .map((row) => ClientMachine.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  Future<void> _refreshMachines() async {
    setState(() {
      _futureMachines = _loadMachines();
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
    final title = widget.clientName ?? 'Dettaglio cliente';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: FutureBuilder<List<ClientMachine>>(
        future: _futureMachines,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text('Errore nel caricamento: ${snapshot.error}'),
            );
          }

          final machines = snapshot.data ?? [];

          if (machines.isEmpty) {
            return const Center(
              child: Text('Nessuna macchina trovata per questo cliente.'),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: machines.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final m = machines[index];
              final color = _stateColor(m.state);
              final label = _stateLabel(m.state);

              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: color,
                    child: Text(
                      '${m.currentFillPercent.toStringAsFixed(0)}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  title: Text(m.code),
                  subtitle: Text(
                    '${m.siteName}\nStato: $label (${m.state})',
                  ),
                  isThreeLine: true,
                  onTap: () async {
                    // Vai al dettaglio macchina, poi al ritorno ricarica la lista
                    await context.push('/machines/${m.machineId}');
                    if (mounted) {
                      _refreshMachines();
                    }
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
