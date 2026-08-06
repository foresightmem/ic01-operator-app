import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/ui/app_design_system.dart';
import '../../onboarding/data/customer_machine_onboarding_service.dart';
import '../../onboarding/presentation/onboarding_dialogs.dart';

class AdminClientDetailPage extends StatefulWidget {
  final String clientId;

  const AdminClientDetailPage({super.key, required this.clientId});

  @override
  State<AdminClientDetailPage> createState() => _AdminClientDetailPageState();
}

class _AdminClientDetailPageState extends State<AdminClientDetailPage> {
  late Future<bool> _isAdminFuture;
  late Future<_ClientMachinesData> _dataFuture;

  @override
  void initState() {
    super.initState();
    _isAdminFuture = _checkIfAdmin();
    _dataFuture = _loadData();
  }

  Future<bool> _checkIfAdmin() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user == null) return false;

    final data = await supabase
        .from('profiles')
        .select('role')
        .eq('id', user.id)
        .maybeSingle();

    return (data?['role'] as String?) == 'admin';
  }

  Future<_ClientMachinesData> _loadData() async {
    final supabase = Supabase.instance.client;

    final clientRaw = await supabase
        .from('clients')
        .select('id, name, vat_number, notes')
        .eq('id', widget.clientId)
        .maybeSingle();

    if (clientRaw == null) {
      return _ClientMachinesData.empty();
    }

    final sitesRaw = await supabase
        .from('sites')
        .select('id, name, city, address')
        .eq('client_id', widget.clientId);

    final sites = (sitesRaw as List)
        .map((e) => e as Map<String, dynamic>)
        .toList();

    final siteIds = sites.map((s) => s['id'] as String).toList();

    List<Map<String, dynamic>> machines = [];
    if (siteIds.isNotEmpty) {
      final machinesRaw = await supabase
          .from('machines')
          .select(
            'id, code, site_id, current_fill_percent, yearly_shots, hw_serial',
          )
          .inFilter('site_id', siteIds);

      machines = (machinesRaw as List)
          .map((e) => e as Map<String, dynamic>)
          .toList();
    }

    final Map<String, Map<String, dynamic>> siteById = {
      for (final s in sites) s['id'] as String: s,
    };

    int totalShots = 0;
    final List<_MachineWithSite> machinesWithSite = [];

    for (final m in machines) {
      final String? siteId = m['site_id'] as String?;
      final site = siteId != null ? siteById[siteId] : null;

      final int shots = (m['yearly_shots'] as int?) ?? 0;
      totalShots += shots;

      machinesWithSite.add(
        _MachineWithSite(
          id: m['id'] as String,
          code: m['code'] as String? ?? 'N/D',
          currentFillPercent:
              (m['current_fill_percent'] as num?)?.toDouble() ?? 0,
          yearlyShots: shots,
          hwSerial: m['hw_serial'] as String?,
          siteName: site?['name'] as String? ?? 'Senza sito',
          city: site?['city'] as String? ?? 'Senza città',
        ),
      );
    }

    // ordina macchine per livello (prima quelle più scariche)
    machinesWithSite.sort(
      (a, b) => a.currentFillPercent.compareTo(b.currentFillPercent),
    );

    final clientName = clientRaw['name'] as String? ?? 'Senza nome';

    return _ClientMachinesData(
      clientId: widget.clientId,
      clientName: clientName,
      vatNumber: clientRaw['vat_number'] as String?,
      notes: clientRaw['notes'] as String?,
      totalMachines: machinesWithSite.length,
      totalShots: totalShots,
      sites: sites
          .map(
            (site) => _ClientSite(
              id: site['id'] as String,
              name: site['name'] as String? ?? 'Sede',
              address: site['address'] as String?,
              city: site['city'] as String?,
            ),
          )
          .toList(),
      machines: machinesWithSite,
    );
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
      context.go('/admin/clients');
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

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _isAdminFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(body: AppLoading());
        }

        final isAdmin = snapshot.data ?? false;
        if (!isAdmin) {
          return Scaffold(
            appBar: AppBar(title: const Text('Cliente')),
            body: const Center(child: Text('Accesso riservato agli admin.')),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Dettaglio cliente'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.go('/admin/clients'),
            ),
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
                    setState(() {
                      _dataFuture = _loadData();
                    });
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
                    setState(() {
                      _dataFuture = _loadData();
                    });
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
          body: FutureBuilder<_ClientMachinesData>(
            future: _dataFuture,
            builder: (context, snap) {
              if (!snap.hasData) {
                return const AppLoading(label: 'Caricamento cliente');
              }
              final data = snap.data!;
              if (data.clientId == null) {
                return const AppEmptyState(
                  title: 'Cliente non trovato',
                  icon: Icons.apartment_outlined,
                );
              }

              return ListView(
                padding: context.responsive.pagePadding,
                children: [
                  AppSectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data.clientName,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (data.vatNumber != null &&
                            data.vatNumber!.trim().isNotEmpty)
                          Text(
                            'P.IVA: ${data.vatNumber}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        if (data.notes != null &&
                            data.notes!.trim().isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            data.notes!,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // KPI cliente
                  AppAdaptiveGrid(
                    minTileWidth: 180,
                    maxColumns: 2,
                    childAspectRatio: 2.6,
                    children: [
                      _smallKpi(
                        context,
                        label: 'Macchine',
                        value: data.totalMachines.toString(),
                      ),
                      _smallKpi(
                        context,
                        label: 'Erogazioni',
                        value: data.totalShots.toString(),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  Text('Sedi', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.xs),

                  if (data.sites.isEmpty)
                    const AppEmptyState(
                      title: 'Nessuna sede associata',
                      icon: Icons.place_outlined,
                    ),
                  for (final site in data.sites) _SiteCard(site: site),

                  const SizedBox(height: AppSpacing.lg),

                  Text(
                    'Macchine',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),

                  if (data.machines.isEmpty)
                    const AppEmptyState(
                      title: 'Nessuna macchina associata',
                      icon: Icons.coffee_maker_outlined,
                    ),
                  for (final m in data.machines) _MachineCard(machine: m),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _smallKpi(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    return AppSectionCard(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.sm,
        horizontal: AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _ClientMachinesData {
  final String? clientId;
  final String clientName;
  final String? vatNumber;
  final String? notes;
  final int totalMachines;
  final int totalShots;
  final List<_ClientSite> sites;
  final List<_MachineWithSite> machines;

  _ClientMachinesData({
    required this.clientId,
    required this.clientName,
    required this.vatNumber,
    required this.notes,
    required this.totalMachines,
    required this.totalShots,
    required this.sites,
    required this.machines,
  });

  factory _ClientMachinesData.empty() => _ClientMachinesData(
    clientId: null,
    clientName: '',
    vatNumber: null,
    notes: null,
    totalMachines: 0,
    totalShots: 0,
    sites: const [],
    machines: const [],
  );
}

class _ClientSite {
  final String id;
  final String name;
  final String? address;
  final String? city;

  const _ClientSite({
    required this.id,
    required this.name,
    required this.address,
    required this.city,
  });
}

class _MachineWithSite {
  final String id;
  final String code;
  final double currentFillPercent;
  final int yearlyShots;
  final String? hwSerial;
  final String siteName;
  final String city;

  _MachineWithSite({
    required this.id,
    required this.code,
    required this.currentFillPercent,
    required this.yearlyShots,
    required this.hwSerial,
    required this.siteName,
    required this.city,
  });
}

class _SiteCard extends StatelessWidget {
  final _ClientSite site;

  const _SiteCard({required this.site});

  @override
  Widget build(BuildContext context) {
    final subtitleParts = <String>[
      if ((site.address ?? '').trim().isNotEmpty) site.address!.trim(),
      if ((site.city ?? '').trim().isNotEmpty) site.city!.trim(),
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        leading: const Icon(Icons.place_outlined),
        title: Text(site.name),
        subtitle: Text(
          subtitleParts.isEmpty
              ? 'Indirizzo non disponibile'
              : subtitleParts.join(' - '),
        ),
      ),
    );
  }
}

class _MachineCard extends StatelessWidget {
  final _MachineWithSite machine;

  const _MachineCard({required this.machine});

  Color _fillColor(double p) {
    if (p <= 20) return AppColors.danger;
    if (p <= 40) return AppColors.warning;
    if (p <= 70) return AppColors.info;
    return AppColors.success;
  }

  String _fillLabel(double p) {
    if (p <= 20) return 'Critico';
    if (p <= 40) return 'Basso';
    if (p <= 70) return 'Ok';
    return 'Pieno';
  }

  @override
  Widget build(BuildContext context) {
    final color = _fillColor(machine.currentFillPercent);

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // prima riga: codice + chip stato
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                Text(
                  machine.code,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                AppStatusPill(
                  label:
                      '${_fillLabel(machine.currentFillPercent)} (${machine.currentFillPercent.toStringAsFixed(0)}%)',
                  color: color,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              '${machine.siteName} • ${machine.city}',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Erogazioni anno: ${machine.yearlyShots}',
              style: const TextStyle(fontSize: 13),
            ),
            if (machine.hwSerial != null && machine.hwSerial!.trim().isNotEmpty)
              Text(
                'HW: ${machine.hwSerial}',
                style: const TextStyle(fontSize: 11, color: AppColors.muted),
              ),
          ],
        ),
      ),
    );
  }
}
