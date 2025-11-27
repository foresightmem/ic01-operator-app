import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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
        .select('id, code, site_id, yearly_shots, assigned_operator_id');
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

    // --- Profili operatori (per nome) ---
    final operatorsData = await supabase
        .from('profiles')
        .select('id, full_name, role')
        .eq('role', 'refill_operator');

    // mappe di supporto
    final Map<String, String> clientIdToName = {};
    for (final row in clientsData) {
      final map = row;
      clientIdToName[map['id'] as String] =
          (map['name'] as String?) ?? 'Senza nome';
    }

    final Map<String, String> siteIdToClientId = {};
    for (final row in sitesData) {
      final map = row;
      siteIdToClientId[map['id'] as String] =
          map['client_id'] as String;
    }

    final Map<String, String> operatorIdToName = {};
    for (final row in operatorsData) {
      final map = row;
      operatorIdToName[map['id'] as String] =
          (map['full_name'] as String?) ?? 'Operatore';
    }

    int totalShots = 0;
    final Map<String, int> shotsPerClient = {};
    final Map<String, int> shotsPerMachine = {};
    final Map<String, int> shotsPerOperator = {};

    for (final row in machinesData) {
      final map = row;
      final String machineCode = map['code'] as String? ?? 'N/D';
      final String? siteId = map['site_id'] as String?;
      final String? operatorId = map['assigned_operator_id'] as String?;
      final int shots = (map['yearly_shots'] as int?) ?? 0;

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

      // per operatore (tramite assigned_operator_id)
      if (operatorId != null) {
        final operatorName =
            operatorIdToName[operatorId] ?? 'Operatore senza nome';
        shotsPerOperator[operatorName] =
            (shotsPerOperator[operatorName] ?? 0) + shots;
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
      shotsPerOperator: shotsPerOperator,
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
        final supabase = Supabase.instance.client;
        final user = supabase.auth.currentUser;
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
              if (context.mounted) context.go('/login');
            },
          ),
        ],
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
                  final double width = constraints.maxWidth;

                  late int crossAxisCount;
                  late double childAspectRatio;

                  if (width >= 1200) {
                    // Desktop largo
                    crossAxisCount = 4;
                    childAspectRatio = 2.8;
                  } else if (width >= 800) {
                    // Tablet / small desktop
                    crossAxisCount = 3;
                    childAspectRatio = 2.2;
                  } else {
                    // Mobile
                    crossAxisCount = 2;
                    childAspectRatio = 1.0;
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
                          childAspectRatio: childAspectRatio,
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
                              onTap: null,
                            ),
                            _AdminKpiCard(
                              label: 'Macchine totali',
                              value: kpi.totalMachines.toString(),
                              subtitle: 'Tabella machines',
                              icon: Icons.coffee,
                              onTap: null,
                            ),
                            _AdminKpiCard(
                              label: 'Ticket aperti',
                              value: kpi.openTickets.toString(),
                              subtitle: 'status = open',
                              icon: Icons.report_problem,
                              onTap: () {
                                context.go('/maintenance?status=open');
                              },
                            ),
                            _AdminKpiCard(
                              label: 'Ticket in corso',
                              value: kpi.inProgressTickets.toString(),
                              subtitle: 'status = in_progress',
                              icon: Icons.build,
                              onTap: () {
                                context.go('/maintenance?status=in_progress');
                              },
                            ),
                            _AdminKpiCard(
                              label: 'Refill oggi',
                              value: kpi.refillsToday.toString(),
                              subtitle: 'refills.created_at ≥ oggi',
                              icon: Icons.local_cafe,
                              onTap: () {
                                // esempio: potresti voler andare alla dashboard refill
                                context.go('/dashboard');
                              },
                            ),
                            _AdminKpiCard(
                              label: 'Visite oggi',
                              value: kpi.visitsToday.toString(),
                              subtitle: 'visits.created_at ≥ oggi',
                              icon: Icons.route,
                              onTap: null,
                            ),
                            _AdminKpiCard(
                              label: 'Erogazioni totali',
                              value: kpi.totalShots.toString(),
                              subtitle: 'Somma machines.yearly_shots',
                              icon: Icons.waterfall_chart,
                              onTap: null,
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
                          'Performance operatori (erogazioni totali)',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        _ShotsBarChart(
                          data: kpi.shotsPerOperator,
                        ),

                        const SizedBox(height: 8),
                        _OperatorRankingCard(data: kpi.shotsPerOperator),

                        const SizedBox(height: 24),

                        Text(
                          'Attività recenti',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),

                        const Card(
                          child: ListTile(
                            leading: Icon(Icons.coffee),
                            title: Text('Ultimi refill'),
                            subtitle: Text(
                              'In uno step successivo li popoleremo da Supabase.',
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Card(
                          child: ListTile(
                            leading: Icon(Icons.build),
                            title: Text('Ultime manutenzioni'),
                            subtitle: Text(
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
  final Map<String, int> shotsPerOperator;

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
    required this.shotsPerOperator,
  });
}

class _AdminKpiCard extends StatelessWidget {
  final String label;
  final String value;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTap;

  const _AdminKpiCard({
    required this.label,
    required this.value,
    required this.subtitle,
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final card = Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      elevation: 0.5,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Icon(
                  icon,
                  size: 20,
                  color: theme.colorScheme.primary.withAlpha(230),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );

    if (onTap == null) {
      return card;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: card,
    );
  }
}

class _OperatorRankingCard extends StatelessWidget {
  final Map<String, int> data;

  const _OperatorRankingCard({required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Nessun operatore con erogazioni registrate.'),
        ),
      );
    }

    final entries = data.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ranking operatori',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 8),
            for (int i = 0; i < entries.length; i++)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 16,
                  child: Text('${i + 1}'),
                ),
                title: Text(entries[i].key),
                subtitle: Text('${entries[i].value} erogazioni'),
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

        final double minChartWidth = top.length * 80.0;
        final double chartWidth =
            constraints.maxWidth < minChartWidth ? minChartWidth : constraints.maxWidth;

        return Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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
