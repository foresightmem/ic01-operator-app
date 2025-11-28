// ignore_for_file: unnecessary_underscores, unnecessary_brace_in_string_interps

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
    final machinesData = await supabase.from('machines').select(
        'id, code, site_id, yearly_shots, assigned_operator_id, current_fill_percent');
    final sitesData =
        await supabase.from('sites').select('id, client_id, name, city');
    final ticketsData = await supabase
        .from('tickets')
        .select(
            'id, status, client_id, site_id, machine_id, assigned_technician_id, created_at, updated_at')
        .order('updated_at', ascending: false)
        .limit(30);
    final ticketsOpenData = ticketsData
        .where((t) => t['status'] == 'open')
        .toList(growable: false);
    final ticketsInProgressData = ticketsData
        .where((t) => t['status'] == 'in_progress')
        .toList(growable: false);

    final refillsTodayData = await supabase
        .from('refills')
        .select('id')
        .gte('created_at', startOfToday.toIso8601String());

    final visitsTodayData = await supabase
        .from('visits')
        .select('id')
        .gte('created_at', startOfToday.toIso8601String());

    // per eventi
    final refillsData = await supabase
        .from('refills')
        .select('id, machine_id, operator_id, previous_fill_percent, new_fill_percent, created_at')
        .order('created_at', ascending: false)
        .limit(30);

    final visitsData = await supabase
        .from('visits')
        .select(
            'id, operator_id, client_id, site_id, visit_type, created_at')
        .order('created_at', ascending: false)
        .limit(30);

    // profili (operatori & tecnici)
    final profilesData = await supabase
        .from('profiles')
        .select('id, full_name, role');

    // mappe di supporto
    final Map<String, String> clientIdToName = {};
    for (final row in clientsData) {
      final map = row;
      clientIdToName[map['id'] as String] =
          (map['name'] as String?) ?? 'Senza nome';
    }

    final Map<String, Map<String, dynamic>> siteIdToSite = {};
    final Map<String, String> siteIdToClientId = {};
    for (final row in sitesData) {
      final map = row;
      final id = map['id'] as String;
      siteIdToClientId[id] = map['client_id'] as String;
      siteIdToSite[id] = map;
    }

    final Map<String, Map<String, dynamic>> machineIdToMachine = {};
    for (final row in machinesData) {
      final map = row;
      machineIdToMachine[map['id'] as String] = map;
    }

    final Map<String, String> profileIdToName = {};
    for (final row in profilesData) {
      final map = row;
      profileIdToName[map['id'] as String] =
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
            profileIdToName[operatorId] ?? 'Operatore senza nome';
        shotsPerOperator[operatorName] =
            (shotsPerOperator[operatorName] ?? 0) + shots;
      }
    }

    // ---------- Costruzione eventi recenti ----------

    final List<_AdminEvent> events = [];

    // Refill
    for (final row in refillsData) {
      final map = row;
      final createdAt = DateTime.parse(map['created_at'] as String);

      final String? machineId = map['machine_id'] as String?;
      final machine = machineId != null ? machineIdToMachine[machineId] : null;
      final String machineCode =
          machine != null ? (machine['code'] as String? ?? 'N/D') : 'N/D';

      String? siteName;
      String? clientName;
      if (machine != null) {
        final String? siteId = machine['site_id'] as String?;
        final site = siteId != null ? siteIdToSite[siteId] : null;
        siteName = site?['name'] as String?;
        final clientId = site != null ? site['client_id'] as String : null;
        if (clientId != null) {
          clientName = clientIdToName[clientId];
        }
      }

      final String operatorName = profileIdToName[map['operator_id'] as String] ??
          'Operatore';

      final num? prev = map['previous_fill_percent'] as num?;
      final num? next = map['new_fill_percent'] as num?;
      final prevStr = prev != null ? '${prev.toStringAsFixed(0)}%' : '?';
      final nextStr = next != null ? '${next.toStringAsFixed(0)}%' : '?';

      final subtitleParts = <String>['Macchina $machineCode'];
      if (siteName != null) subtitleParts.add(siteName);
      if (clientName != null) subtitleParts.add(clientName);

      events.add(
        _AdminEvent(
          timestamp: createdAt,
          type: 'refill',
          title: '$operatorName ha effettuato un refill',
          subtitle: '${subtitleParts.join(' • ')}  ($prevStr → $nextStr)',
          icon: Icons.local_cafe,
        ),
      );
    }

    // Ticket (usiamo updated_at per ordinare gli eventi di stato)
    for (final row in ticketsData) {
      final map = row;
      final updatedAt = DateTime.parse(map['updated_at'] as String);
      final String status = map['status'] as String;

      String action;
      IconData icon;
      switch (status) {
        case 'open':
          action = 'Ticket aperto';
          icon = Icons.report_problem;
          break;
        case 'assigned':
          action = 'Ticket assegnato';
          icon = Icons.person;
          break;
        case 'in_progress':
          action = 'Intervento in corso';
          icon = Icons.build;
          break;
        case 'closed':
          action = 'Ticket chiuso';
          icon = Icons.check_circle;
          break;
        default:
          action = 'Aggiornamento ticket';
          icon = Icons.info;
      }

      final String? clientId = map['client_id'] as String?;
      final String clientName =
          clientId != null ? (clientIdToName[clientId] ?? 'Cliente') : 'Cliente';

      final String? machineId = map['machine_id'] as String?;
      final machine = machineId != null ? machineIdToMachine[machineId] : null;
      final String machineCode =
          machine != null ? (machine['code'] as String? ?? 'N/D') : 'N/D';

      final String? techId = map['assigned_technician_id'] as String?;
      final String? techName =
          techId != null ? profileIdToName[techId] : null;

      final subtitleParts = <String>[
        clientName,
        'Macchina $machineCode',
      ];
      if (techName != null) {
        subtitleParts.add('Tecnico: $techName');
      }

      events.add(
        _AdminEvent(
          timestamp: updatedAt,
          type: 'ticket_$status',
          title: action,
          subtitle: subtitleParts.join(' • '),
          icon: icon,
        ),
      );
    }

    // Visite
    for (final row in visitsData) {
      final map = row;
      final createdAt = DateTime.parse(map['created_at'] as String);

      final String? clientId = map['client_id'] as String?;
      final String clientName =
          clientId != null ? (clientIdToName[clientId] ?? 'Cliente') : 'Cliente';

      String? siteName;
      if (map['site_id'] != null) {
        final site = siteIdToSite[map['site_id'] as String];
        siteName = site?['name'] as String?;
      }

      final String operatorName =
          profileIdToName[map['operator_id'] as String] ?? 'Operatore';

      final String visitType = map['visit_type'] as String;
      final String typeLabel =
          visitType == 'maintenance' ? 'manutenzione' : 'refill';

      final subtitleParts = <String>[clientName];
      if (siteName != null) subtitleParts.add(siteName);

      events.add(
        _AdminEvent(
          timestamp: createdAt,
          type: 'visit_$visitType',
          title: '$operatorName ha effettuato una visita $typeLabel',
          subtitle: subtitleParts.join(' • '),
          icon: visitType == 'maintenance'
              ? Icons.build
              : Icons.local_cafe_outlined,
        ),
      );
    }

    // ordiniamo tutti gli eventi
    events.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final recentEvents = events.take(15).toList();

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
      recentEvents: recentEvents,
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
        final user = Supabase.instance.client.auth.currentUser;

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
                    childAspectRatio = 3.0;
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
                              onTap: () {
                                context.go('/admin/clients');
                              },
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
                        _RecentActivitySection(events: kpi.recentEvents),
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
  final List<_AdminEvent> recentEvents;

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
    required this.recentEvents,
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

    // massimo valore tra le barre
    final int maxValue =
        top.map((e) => e.value).fold<int>(0, (prev, v) => v > prev ? v : prev);

    // arrotonda al "bin superiore" (multipli di 10.000)
    final double niceMaxY =
        ((maxValue / 10000).ceil() * 10000).toDouble().clamp(1, double.infinity);

    // intervallo tra le linee di griglia (4 step)
    final double interval = niceMaxY / 4;

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
                      maxY: niceMaxY,
                      minY: 0,
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
                            interval: interval,
                            getTitlesWidget: (value, meta) {
                              // nascondo l’etichetta esattamente sul maxY per non farla tagliare
                              if ((value - niceMaxY).abs() < interval / 4) {
                                return const SizedBox.shrink();
                              }
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
                        horizontalInterval: interval,
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

/// Modello evento per "Attività recenti"
class _AdminEvent {
  final DateTime timestamp;
  final String type;
  final String title;
  final String subtitle;
  final IconData icon;

  _AdminEvent({
    required this.timestamp,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.icon,
  });
}

class _RecentActivitySection extends StatelessWidget {
  final List<_AdminEvent> events;

  const _RecentActivitySection({required this.events});

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Nessuna attività recente.'),
        ),
      );
    }

    final visible = events.take(8).toList();

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: visible.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final e = visible[index];
          return ListTile(
            leading: CircleAvatar(
              radius: 18,
              backgroundColor: Theme.of(context)
                  .colorScheme
                  .primary
                  .withAlpha(20),
              child: Icon(
                e.icon,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            title: Text(
              e.title,
              style: const TextStyle(fontSize: 14),
            ),
            subtitle: Text(
              e.subtitle,
              style: const TextStyle(fontSize: 12),
            ),
            trailing: Text(
              _timeAgo(e.timestamp),
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          );
        },
      ),
    );
  }

  static String _timeAgo(DateTime time) {
    final diff = DateTime.now().toUtc().difference(time.toUtc());
    if (diff.inMinutes < 1) return 'Ora';
    if (diff.inHours < 1) return '${diff.inMinutes} min fa';
    if (diff.inHours < 24) return '${diff.inHours} h fa';
    if (diff.inDays < 7) return '${diff.inDays} g fa';
    final days = diff.inDays;
    final weeks = (days / 7).floor();
    if (weeks < 4) return '${weeks} sett fa';
    final months = (days / 30).floor();
    return '${months} mesi fa';
  }
}
