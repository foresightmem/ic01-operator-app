/// ===============================================================
/// FILE: features/clients/presentation/client_detail_page.dart
///
/// Dettaglio di un cliente:
/// - Riceve clientId (obbligatorio) e clientName (facoltativo) dalla route.
/// - Carica le macchine del cliente (effective assignment).
/// - Permette tap su una macchina per aprire MachineDetailPage.
///
/// NOTA:
/// - Usa `machine_effective_assignment` per rispettare le assegnazioni temporanee.
/// - Calcola lo stato (green/yellow/red/black) da current_fill_percent.
/// ===============================================================
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Modello per rappresentare una macchina di un cliente nella lista
class ClientMachine {
  final String machineId;
  final String code; // machine_code
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

  static String _stateFromFill(double fill) {
    // Stessa logica usata altrove (adatta se hai soglie diverse)
    if (fill <= 10) return 'black';
    if (fill <= 20) return 'red';
    if (fill <= 40) return 'yellow';
    return 'green';
    }

  factory ClientMachine.fromEffectiveMap(Map<String, dynamic> map) {
    final fill = (map['current_fill_percent'] as num?)?.toDouble() ?? 0.0;

    return ClientMachine(
      machineId: map['machine_id'] as String,
      code: (map['machine_code'] as String?) ?? 'N/D',
      siteName: (map['site_name'] as String?) ?? 'Sede',
      currentFillPercent: fill,
      state: _stateFromFill(fill),
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

  /// Carica le macchine dalla view `machine_effective_assignment`.
  /// Filtri:
  ///   - client_id = widget.clientId
  ///   - effective_operator_id = utente corrente
  Future<List<ClientMachine>> _loadMachines() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) return [];

    final data = await supabase
        .from('machine_effective_assignment')
        .select('machine_id, machine_code, current_fill_percent, site_name')
        .eq('client_id', widget.clientId)
        .eq('effective_operator_id', user.id);

    final rows = (data as List).cast<Map<String, dynamic>>();
    return rows.map(ClientMachine.fromEffectiveMap).toList();
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
