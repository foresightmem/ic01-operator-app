import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  late Future<bool> _isAdminFuture;
  Future<_AdminKpiData>? _kpiFuture;

  @override
  void initState() {
    super.initState();
    _isAdminFuture = _checkIfAdmin();
  }

  Future<bool> _checkIfAdmin() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user == null) {
      return false;
    }

    final data = await supabase
        .from('profiles')
        .select('role')
        .eq('id', user.id)
        .maybeSingle();

    if (data == null) return false;
    return data['role'] == 'admin';
  }

  Future<_AdminKpiData> _loadKpis() async {
    final supabase = Supabase.instance.client;

    final now = DateTime.now().toUtc();
    final startOfToday = DateTime.utc(now.year, now.month, now.day);

    // --- KPI "semplici" ---
    final clientsData = await supabase.from('clients').select('id, name');
    final machinesData = await supabase
        .from('machines')
        .select('id, code, site_id, yearly_shots');
    final sitesData =
        await supabase.from('sites').select('id, client_id');

    final ticketsOpenData = await supabase
        .from('tickets')
        .select('id')
        .eq('status', 'open');

    final ticketsInProgressData = await supabase
        .from('tickets')
        .select('id')
        .eq('status', 'in_progress');

    final refillsTodayData = await supabase
        .from('refills')
        .select('id')
        .gte('created_at', startOfToday.toIso8601String());

    final visitsTodayData = await supabase
        .from('visits')
        .select('id')
        .gte('created_at', startOfToday.toIso8601String());

    // --- Aggregazioni erogazioni ---
    // mappe di supporto
    final Map<String, String> clientIdToName = {
      for (final row in clientsData)
        (row['id'] as String): (row['name'] as String? ?? 'Senza nome'),
    };

    final Map<String, String> siteIdToClientId = {
      for (final row in sitesData)
        (row['id'] as String): (row['client_id'] as String),
    };

    int totalShots = 0;
    final Map<String, int> shotsPerClient = {};
    final Map<String, int> shotsPerMachine = {};

    for (final row in machinesData) {
      final String machineCode = row['code'] as String? ?? 'N/D';
      final String? siteId = row['site_id'] as String?;
      final int shots = (row['yearly_shots'] as int?) ?? 0;

      totalShots += shots;

      // per macchina
      shotsPerMachine[machineCode] = shots;

      // per cliente (tramite site → client)
      if (siteId != null) {
        final clientId = siteIdToClientId[siteId];
        if (clientId != null) {
          final clientName = clientIdToName[clientId] ?? 'Senza nome';
          shotsPerClient[clientName] =
              (shotsPerClient[clientName] ?? 0) + shots;
        }
      }
    }

    return _AdminKpiData(
      totalClients: clientsData.length,
      totalMachines: machinesData.length,
      openTickets: ticketsOpenData.length,
      inProgressTickets: ticketsInProgressData.length,
      refillsToday: refillsTodayData.length,
      visitsToday: visitsTodayData.length,
      totalShots: totalShots,
      shotsPerClient: shotsPerClient,
      shotsPerMachine: shotsPerMachine,
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
              title: const Text('Area admin'),
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock, size: 72),
                    const SizedBox(height: 16),
                    const Text(
                      'Questa sezione è riservata agli admin.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      child: const Text('Torna indietro'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        _kpiFuture ??= _loadKpis();

        return Scaffold(
          appBar: AppBar(
            title: const Text('Dashboard Admin'),
          ),
          body: FutureBuilder<_AdminKpiData>(
            future: _kpiFuture,
            builder: (context, kpiSnapshot) {
              if (!kpiSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final kpi = kpiSnapshot.data!;

              return LayoutBuilder(
                builder: (context, constraints) {
                  int crossAxisCount = 1;
                  if (constraints.maxWidth >= 1000) {
                    crossAxisCount = 3;
                  } else if (constraints.maxWidth >= 600) {
                    crossAxisCount = 2;
                  }

                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          kIsWeb
                              ? 'Overview flotta (web)'
                              : 'Overview flotta (app)',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 16),

                        // KPI cards
                        GridView.count(
                          crossAxisCount: crossAxisCount,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          children: [
                            _AdminKpiCard(
                              label: 'Clienti totali',
                              value: kpi.totalClients.toString(),
                              subtitle: 'Tabella clients',
                              icon: Icons.apartment,
                            ),
                            _AdminKpiCard(
                              label: 'Macchine totali',
                              value: kpi.totalMachines.toString(),
                              subtitle: 'Tabella machines',
                              icon: Icons.coffee,
                            ),
                            _AdminKpiCard(
                              label: 'Ticket aperti',
                              value: kpi.openTickets.toString(),
                              subtitle: 'status = open',
                              icon: Icons.report_problem,
                            ),
                            _AdminKpiCard(
                              label: 'Ticket in corso',
                              value: kpi.inProgressTickets.toString(),
                              subtitle: 'status = in_progress',
                              icon: Icons.build,
                            ),
                            _AdminKpiCard(
                              label: 'Refill oggi',
                              value: kpi.refillsToday.toString(),
                              subtitle: 'refills.created_at ≥ oggi',
                              icon: Icons.local_cafe,
                            ),
                            _AdminKpiCard(
                              label: 'Visite oggi',
                              value: kpi.visitsToday.toString(),
                              subtitle: 'visits.created_at ≥ oggi',
                              icon: Icons.route,
                            ),
                            _AdminKpiCard(
                              label: 'Erogazioni totali',
                              value: kpi.totalShots.toString(),
                              subtitle: 'Somma machines.yearly_shots',
                              icon: Icons.waterfall_chart,
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),

                        Text(
                          'Erogazioni per cliente (top 5)',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        _ShotsBarChart(
                          data: kpi.shotsPerClient,
                        ),

                        const SizedBox(height: 24),

                        Text(
                          'Erogazioni per macchina (top 5)',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        _ShotsBarChart(
                          data: kpi.shotsPerMachine,
                        ),

                        const SizedBox(height: 24),

                        Text(
                          'Attività recenti',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),

                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.coffee),
                            title: const Text('Ultimi refill'),
                            subtitle: const Text(
                              'In uno step successivo li popoleremo da Supabase.',
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.build),
                            title: const Text('Ultime manutenzioni'),
                            subtitle: const Text(
                              'In uno step successivo useremo tickets/visits.',
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

class _AdminKpiData {
  final int totalClients;
  final int totalMachines;
  final int openTickets;
  final int inProgressTickets;
  final int refillsToday;
  final int visitsToday;
  final int totalShots;
  final Map<String, int> shotsPerClient;
  final Map<String, int> shotsPerMachine;

  _AdminKpiData({
    required this.totalClients,
    required this.totalMachines,
    required this.openTickets,
    required this.inProgressTickets,
    required this.refillsToday,
    required this.visitsToday,
    required this.totalShots,
    required this.shotsPerClient,
    required this.shotsPerMachine,
  });
}

class _AdminKpiCard extends StatelessWidget {
  final String label;
  final String value;
  final String subtitle;
  final IconData icon;

  const _AdminKpiCard({
    required this.label,
    required this.value,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShotsBarChart extends StatelessWidget {
  final Map<String, int> data;

  const _ShotsBarChart({required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Nessun dato disponibile.'),
        ),
      );
    }

    final entries = data.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = entries.take(5).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isNarrow = constraints.maxWidth < 500;
        final double chartHeight = isNarrow ? 220 : 280;
        final double barWidth = isNarrow ? 20 : 26;
        final double labelRotation = isNarrow ? -0.8 : 0.0;

        // larghezza minima del grafico: se lo schermo è stretto, permettiamo lo scroll
        final double minChartWidth = top.length * 80.0;
        final double chartWidth =
            constraints.maxWidth < minChartWidth ? minChartWidth : constraints.maxWidth;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              height: chartHeight,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: chartWidth,
                  child: BarChart(
                    BarChartData(
                      barTouchData: BarTouchData(
                        enabled: true,
                        touchTooltipData: BarTouchTooltipData(
                          tooltipPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          getTooltipItem: (group, groupIndex, rod, rodIndex) {
                            final label = top[group.x.toInt()].key;
                            final value = top[group.x.toInt()].value;
                            return BarTooltipItem(
                              '$label\n$value erogazioni',
                              const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            );
                          },
                        ),
                      ),
                      barGroups: [
                        for (int i = 0; i < top.length; i++)
                          BarChartGroupData(
                            x: i,
                            barRods: [
                              BarChartRodData(
                                toY: top[i].value.toDouble(),
                                width: barWidth,
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(8),
                                  topRight: Radius.circular(8),
                                ),
                              ),
                            ],
                          ),
                      ],
                      titlesData: FlTitlesData(
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: isNarrow ? 64 : 40,
                            getTitlesWidget: (value, meta) {
                              final index = value.toInt();
                              if (index < 0 || index >= top.length) {
                                return const SizedBox.shrink();
                              }
                              final label = top[index].key;
                              final text = Text(
                                label,
                                style: const TextStyle(fontSize: 10),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 2,
                              );

                              if (labelRotation == 0) {
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: text,
                                );
                              }

                              return Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Transform.rotate(
                                  angle: labelRotation,
                                  child: text,
                                ),
                              );
                            },
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 36,
                            getTitlesWidget: (value, meta) {
                              return Text(
                                value.toInt().toString(),
                                style: const TextStyle(fontSize: 10),
                              );
                            },
                          ),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                      ),
                      borderData: FlBorderData(show: false),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}