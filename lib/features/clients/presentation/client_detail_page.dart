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

import '../../../core/ui/app_design_system.dart';
import '../../onboarding/data/customer_machine_onboarding_service.dart';
import '../../onboarding/presentation/onboarding_dialogs.dart';

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

  const ClientDetailPage({super.key, required this.clientId, this.clientName});

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

  Future<void> _deleteClient() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Elimina cliente'),
        content: const Text(
          'Puoi eliminare solo clienti senza macchine, ticket o visite. Continuare?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annulla'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Elimina'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await CustomerMachineOnboardingService().deleteClient(widget.clientId);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Cliente eliminato.')));
      context.go('/dashboard');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            onboardingUserMessage(error, OnboardingAction.deleteClient),
          ),
        ),
      );
    }
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

  @override
  Widget build(BuildContext context) {
    final title = widget.clientName ?? 'Dettaglio cliente';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Nuova sede',
            icon: const Icon(Icons.add_location_alt_outlined),
            onPressed: () async {
              final created = await showCreateSiteDialog(
                context,
                clientId: widget.clientId,
              );
              if (created && mounted) {
                _refreshMachines();
              }
            },
          ),
          IconButton(
            tooltip: 'Nuova macchina',
            icon: const Icon(Icons.add_business),
            onPressed: () async {
              final created = await showCreateMachineDialog(
                context,
                initialClientId: widget.clientId,
              );
              if (created && mounted) {
                _refreshMachines();
              }
            },
          ),
          IconButton(
            tooltip: 'Elimina cliente',
            icon: const Icon(Icons.delete_outline),
            onPressed: _deleteClient,
          ),
        ],
      ),
      body: FutureBuilder<List<ClientMachine>>(
        future: _futureMachines,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AppLoading();
          }

          if (snapshot.hasError) {
            return AppErrorState(
              message: 'Errore nel caricamento: ${snapshot.error}',
              onRetry: _refreshMachines,
            );
          }

          final machines = snapshot.data ?? [];

          if (machines.isEmpty) {
            return const AppEmptyState(
              title: 'Nessuna macchina trovata',
              message: 'Aggiungi una sede o una macchina dal menu in alto.',
              icon: Icons.coffee_maker_outlined,
            );
          }

          return ListView.separated(
            padding: context.responsive.pagePadding,
            itemCount: machines.length,
            separatorBuilder: (context, index) =>
                const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) {
              final m = machines[index];
              final color = _stateColor(m.state);
              final label = _stateLabel(m.state);

              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: color.withValues(alpha: 0.12),
                    child: Text(
                      '${m.currentFillPercent.toStringAsFixed(0)}%',
                      style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  title: Text(
                    m.code,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text('${m.siteName}\nStato: $label (${m.state})'),
                  trailing: const Icon(Icons.chevron_right),
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
