// lib/features/clients/presentation/client_detail_page.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';


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

  Future<List<ClientMachine>> _loadMachines() async {
    final supabase = Supabase.instance.client;

    final data = await supabase
        .from('client_machines')
        .select()
        .eq('client_id', widget.clientId)
        .order('code', ascending: true);

    return (data as List<dynamic>)
        .map((row) => ClientMachine.fromMap(row as Map<String, dynamic>))
        .toList();
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
                  onTap: () {
                    context.push('/machines/${m.machineId}');
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
