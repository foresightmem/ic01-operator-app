/// ===============================================================
/// FILE: features/clients/presentation/client_detail_page.dart
///
/// Dettaglio di un cliente:
/// - Riceve clientId (obbligatorio) e clientName (facoltativo) dalla route.
/// - Carica le macchine del cliente (effective assignment).
/// - Permette tap su una macchina per aprire MachineDetailPage.
///
/// NOTA:
/// - Usa `machine_effective_consumables` per rispettare le assegnazioni temporanee.
/// - Calcola lo stato (green/yellow/red/black) dal livello minimo dei consumabili.
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
}

class _MachineAggregate {
  final String machineId;
  final String machineCode;
  final String siteName;
  double minPercent;
  bool hasEnabledConsumable;

  _MachineAggregate({
    required this.machineId,
    required this.machineCode,
    required this.siteName,
    required this.minPercent,
    required this.hasEnabledConsumable,
  });
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

  /// Carica le macchine dalla view `machine_effective_consumables`.
  /// Filtri:
  ///   - client_id = widget.clientId
  ///   - effective_operator_id = utente corrente
  Future<List<ClientMachine>> _loadMachines() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) return [];

    final data = await supabase
        .from('machine_effective_consumables')
        .select(
          'machine_id, machine_code, site_name, client_id, consumable_type, capacity_units, current_units, is_enabled, effective_operator_id',
        )
        .eq('client_id', widget.clientId)
        .eq('effective_operator_id', user.id);

    final rows = (data as List).cast<Map<String, dynamic>>();
    if (rows.isEmpty) {
      return [];
    }

    final machines = <String, _MachineAggregate>{};
    for (final row in rows) {
      final machineId = row['machine_id'] as String?;
      if (machineId == null) continue;

      final machineCode = row['machine_code'] as String? ?? 'N/D';
      final siteName = row['site_name'] as String? ?? 'Sede';
      final enabled = (row['is_enabled'] as bool?) ?? true;
      final capacity = (row['capacity_units'] as num?)?.toDouble() ?? 0.0;
      final current = (row['current_units'] as num?)?.toDouble() ?? 0.0;

      final aggregate = machines.putIfAbsent(
        machineId,
        () => _MachineAggregate(
          machineId: machineId,
          machineCode: machineCode,
          siteName: siteName,
          minPercent: 100,
          hasEnabledConsumable: false,
        ),
      );

      if (!enabled) {
        continue;
      }

      aggregate.hasEnabledConsumable = true;
      final percent = _percentFromUnits(current, capacity);
      if (percent < aggregate.minPercent) {
        aggregate.minPercent = percent;
      }
    }

    final result = machines.values.map((machine) {
      final percent = machine.hasEnabledConsumable ? machine.minPercent : 100.0;
      return ClientMachine(
        machineId: machine.machineId,
        code: machine.machineCode,
        siteName: machine.siteName,
        currentFillPercent: percent,
        state: ClientMachine._stateFromFill(percent),
      );
    }).toList();

    result.sort((a, b) => a.code.compareTo(b.code));
    return result;
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

  double _percentFromUnits(double current, double capacity) {
    if (capacity <= 0) return 0;
    final percent = (current / capacity) * 100;
    if (percent.isNaN || percent.isInfinite) return 0;
    return percent.clamp(0, 100);
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
