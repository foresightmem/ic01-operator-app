import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

    final sites =
        (sitesRaw as List).map((e) => e as Map<String, dynamic>).toList();

    final siteIds = sites.map((s) => s['id'] as String).toList();

    List<Map<String, dynamic>> machines = [];
    if (siteIds.isNotEmpty) {
      final machinesRaw = await supabase
          .from('machines')
          .select(
              'id, code, site_id, current_fill_percent, yearly_shots, hw_serial')
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
      machines: machinesWithSite,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _isAdminFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final isAdmin = snapshot.data ?? false;
        if (!isAdmin) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Cliente'),
            ),
            body: const Center(
              child: Text('Accesso riservato agli admin.'),
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Dettaglio cliente'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.go('/admin/clients'),
            ),
          ),
          body: FutureBuilder<_ClientMachinesData>(
            future: _dataFuture,
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final data = snap.data!;
              if (data.clientId == null) {
                return const Center(child: Text('Cliente non trovato.'));
              }

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    data.clientName,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  if (data.vatNumber != null &&
                      data.vatNumber!.trim().isNotEmpty)
                    Text(
                      'P.IVA: ${data.vatNumber}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  const SizedBox(height: 12),
                  if (data.notes != null &&
                      data.notes!.trim().isNotEmpty)
                    Text(
                      data.notes!,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  const SizedBox(height: 16),

                  // KPI cliente
                  Row(
                    children: [
                      _smallKpi(
                        context,
                        label: 'Macchine',
                        value: data.totalMachines.toString(),
                      ),
                      const SizedBox(width: 8),
                      _smallKpi(
                        context,
                        label: 'Erogazioni',
                        value: data.totalShots.toString(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  Text(
                    'Macchine',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),

                  if (data.machines.isEmpty)
                    const Text('Nessuna macchina associata.'),
                  for (final m in data.machines)
                    _MachineCard(machine: m),
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
    return Expanded(
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        elevation: 0.5,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
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
  final List<_MachineWithSite> machines;

  _ClientMachinesData({
    required this.clientId,
    required this.clientName,
    required this.vatNumber,
    required this.notes,
    required this.totalMachines,
    required this.totalShots,
    required this.machines,
  });

  factory _ClientMachinesData.empty() => _ClientMachinesData(
        clientId: null,
        clientName: '',
        vatNumber: null,
        notes: null,
        totalMachines: 0,
        totalShots: 0,
        machines: const [],
      );
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

class _MachineCard extends StatelessWidget {
  final _MachineWithSite machine;

  const _MachineCard({required this.machine});

  Color _fillColor(double p) {
    if (p <= 20) return Colors.red;
    if (p <= 40) return Colors.orange;
    if (p <= 70) return Colors.amber;
    return Colors.green;
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
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // prima riga: codice + chip stato
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  machine.code,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${_fillLabel(machine.currentFillPercent)} (${machine.currentFillPercent.toStringAsFixed(0)}%)',
                    style: TextStyle(
                      fontSize: 12,
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${machine.siteName} • ${machine.city}',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              'Erogazioni anno: ${machine.yearlyShots}',
              style: const TextStyle(fontSize: 13),
            ),
            if (machine.hwSerial != null &&
                machine.hwSerial!.trim().isNotEmpty)
              Text(
                'HW: ${machine.hwSerial}',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
          ],
        ),
      ),
    );
  }
}
