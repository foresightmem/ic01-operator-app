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

import '../../../core/auth/app_role_service.dart';
import '../../../core/navigation/navigation_action_sheet.dart';
import '../../../core/navigation/navigation_launcher.dart';
import '../../../core/navigation/navigation_permissions.dart';
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

class ClientDetailData {
  final List<OnboardingSite> sites;
  final List<ClientMachine> machines;
  final bool canOpenNavigator;

  const ClientDetailData({
    required this.sites,
    required this.machines,
    required this.canOpenNavigator,
  });
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
  late Future<ClientDetailData> _futureData;

  @override
  void initState() {
    super.initState();
    _futureData = _loadData();
  }

  Future<ClientDetailData> _loadData() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) {
      return const ClientDetailData(
        sites: [],
        machines: [],
        canOpenNavigator: false,
      );
    }

    final role = await AppRoleService(client: supabase).currentRole();

    final sitesData = await supabase
        .from('sites')
        .select('id, client_id, name, address, city, latitude, longitude')
        .eq('client_id', widget.clientId)
        .order('name', ascending: true);

    final sites = (sitesData as List)
        .cast<Map<String, dynamic>>()
        .map(OnboardingSite.fromMap)
        .toList();

    final data = await supabase
        .from('machine_effective_assignment')
        .select('machine_id, machine_code, current_fill_percent, site_name')
        .eq('client_id', widget.clientId)
        .eq('effective_operator_id', user.id);

    final rows = (data as List).cast<Map<String, dynamic>>();
    final machines = rows.map(ClientMachine.fromEffectiveMap).toList();

    return ClientDetailData(
      sites: sites,
      machines: machines,
      canOpenNavigator: canUseExternalNavigation(role),
    );
  }

  Future<void> _refreshData() async {
    setState(() {
      _futureData = _loadData();
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
                _refreshData();
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
                _refreshData();
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
      body: FutureBuilder<ClientDetailData>(
        future: _futureData,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AppLoading();
          }

          if (snapshot.hasError) {
            return AppErrorState(
              message: 'Errore nel caricamento: ${snapshot.error}',
              onRetry: _refreshData,
            );
          }

          final data = snapshot.data;
          final sites = data?.sites ?? const <OnboardingSite>[];
          final machines = data?.machines ?? const <ClientMachine>[];

          if (sites.isEmpty && machines.isEmpty) {
            return const AppEmptyState(
              title: 'Nessuna macchina trovata',
              message: 'Aggiungi una sede o una macchina dal menu in alto.',
              icon: Icons.coffee_maker_outlined,
            );
          }

          return ListView(
            padding: context.responsive.pagePadding,
            children: [
              if (sites.isNotEmpty) ...[
                Text('Sedi', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                for (final site in sites)
                  _SiteCard(
                    site: site,
                    showNavigation: data?.canOpenNavigator ?? false,
                  ),
                const SizedBox(height: AppSpacing.lg),
              ],
              Text('Macchine', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.xs),
              if (machines.isEmpty)
                const AppEmptyState(
                  title: 'Nessuna macchina trovata',
                  icon: Icons.coffee_maker_outlined,
                ),
              for (final m in machines) ...[
                Builder(
                  builder: (context) {
                    final color = _stateColor(m.state);
                    final label = _stateLabel(m.state);

                    return Card(
                      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
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
                        subtitle: Text(
                          '${m.siteName}\nStato: $label (${m.state})',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        isThreeLine: true,
                        onTap: () async {
                          await context.push('/machines/${m.machineId}');
                          if (mounted) {
                            _refreshData();
                          }
                        },
                      ),
                    );
                  },
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SiteCard extends StatelessWidget {
  final OnboardingSite site;
  final bool showNavigation;

  const _SiteCard({required this.site, required this.showNavigation});

  @override
  Widget build(BuildContext context) {
    final destination = SiteNavigationDestination(
      siteId: site.id,
      siteName: site.name,
      address: site.address,
      city: site.city,
      latitude: site.latitude,
      longitude: site.longitude,
    );

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.place_outlined, color: AppColors.muted),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        site.name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        site.displaySubtitle,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (showNavigation && destination.canNavigate) ...[
              const SizedBox(height: AppSpacing.sm),
              SiteNavigationButton(destination: destination),
            ],
          ],
        ),
      ),
    );
  }
}
