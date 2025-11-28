import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminClientsOverviewPage extends StatefulWidget {
  const AdminClientsOverviewPage({super.key});

  @override
  State<AdminClientsOverviewPage> createState() =>
      _AdminClientsOverviewPageState();
}

class _AdminClientsOverviewPageState extends State<AdminClientsOverviewPage> {
  late Future<bool> _isAdminFuture;
  late Future<_AdminClientsData> _dataFuture;

  // FILTRI / ORDINAMENTO
  String _searchQuery = '';
  String _cityFilter = 'Tutte le città';
  bool _onlyWithMachines = false;
  _ClientSortMode _sortMode = _ClientSortMode.shotsDesc;

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

  Future<_AdminClientsData> _loadData() async {
    final supabase = Supabase.instance.client;

    final clientsRaw =
        await supabase.from('clients').select('id, name, vat_number');
    final sitesRaw =
        await supabase.from('sites').select('id, client_id, city');
    final machinesRaw = await supabase
        .from('machines')
        .select('id, site_id, yearly_shots');

    final clients = (clientsRaw as List)
        .map((e) => e as Map<String, dynamic>)
        .toList();
    final sites =
        (sitesRaw as List).map((e) => e as Map<String, dynamic>).toList();
    final machines =
        (machinesRaw as List).map((e) => e as Map<String, dynamic>).toList();

    // mappe di supporto
    final Map<String, Map<String, dynamic>> clientById = {
      for (final c in clients) c['id'] as String: c,
    };

    final Map<String, Map<String, dynamic>> siteById = {
      for (final s in sites) s['id'] as String: s,
    };

    // aggregati per client
    final Map<String, _ClientAggregate> aggByClientId = {};

    for (final m in machines) {
      final String? siteId = m['site_id'] as String?;
      if (siteId == null) continue;

      final site = siteById[siteId];
      if (site == null) continue;

      final String clientId = site['client_id'] as String;
      final client = clientById[clientId];
      if (client == null) continue;

      final String city =
          (site['city'] as String?)?.trim().isNotEmpty == true
              ? (site['city'] as String)
              : 'Senza città';

      final int shots = (m['yearly_shots'] as int?) ?? 0;

      aggByClientId.putIfAbsent(
        clientId,
        () => _ClientAggregate(
          clientId: clientId,
          clientName: client['name'] as String? ?? 'Senza nome',
          city: city,
          machineCount: 0,
          totalShots: 0,
        ),
      );

      final agg = aggByClientId[clientId]!;
      agg.machineCount += 1;
      agg.totalShots += shots;
    }

    // includiamo anche clienti senza macchine
    for (final c in clients) {
      final String clientId = c['id'] as String;
      if (!aggByClientId.containsKey(clientId)) {
        aggByClientId[clientId] = _ClientAggregate(
          clientId: clientId,
          clientName: c['name'] as String? ?? 'Senza nome',
          city: 'Senza città',
          machineCount: 0,
          totalShots: 0,
        );
      }
    }

    // raggruppa per città
    final Map<String, List<_ClientAggregate>> byCity = {};
    for (final agg in aggByClientId.values) {
      byCity.putIfAbsent(agg.city, () => []).add(agg);
    }

    final List<_CityGroup> groups = byCity.entries.map((entry) {
      final clientsAgg = entry.value;
      final totalMachines =
          clientsAgg.fold<int>(0, (sum, c) => sum + c.machineCount);
      final totalShots =
          clientsAgg.fold<int>(0, (sum, c) => sum + c.totalShots);
      return _CityGroup(
        city: entry.key,
        clients: clientsAgg,
        totalMachines: totalMachines,
        totalShots: totalShots,
      );
    }).toList()
      ..sort((a, b) => a.city.compareTo(b.city));

    return _AdminClientsData(groups: groups);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _isAdminFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        final isAdmin = snapshot.data ?? false;
        if (!isAdmin) {
          return Scaffold(
            appBar: AppBar(title: const Text('Clienti (admin)')),
            body: const Center(
              child: Text('Accesso riservato agli admin.'),
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Clienti per area'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.go('/admin'),
            ),
          ),
          body: FutureBuilder<_AdminClientsData>(
            future: _dataFuture,
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final data = snap.data!;
              if (data.groups.isEmpty) {
                return const Center(child: Text('Nessun cliente trovato.'));
              }

              // lista città per filtro
              final allCities = <String>{
                for (final g in data.groups) g.city,
              }.toList()
                ..sort();
              final List<String> cityOptions = [
                'Tutte le città',
                ...allCities,
              ];

              // costruiamo la lista filtrata/ordinata
              final filteredGroups =
                  _applyFiltersAndSorting(data.groups, _searchQuery,
                      _cityFilter, _onlyWithMachines, _sortMode);

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: filteredGroups.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    // CARD FILTRI
                    return _FiltersCard(
                      searchQuery: _searchQuery,
                      onSearchChanged: (value) {
                        setState(() => _searchQuery = value);
                      },
                      cityFilter: _cityFilter,
                      cityOptions: cityOptions,
                      onCityChanged: (value) {
                        setState(() => _cityFilter = value ?? 'Tutte le città');
                      },
                      onlyWithMachines: _onlyWithMachines,
                      onOnlyWithMachinesChanged: (value) {
                        setState(() => _onlyWithMachines = value ?? false);
                      },
                      sortMode: _sortMode,
                      onSortModeChanged: (mode) {
                        setState(() => _sortMode = mode ?? _ClientSortMode.shotsDesc);
                      },
                    );
                  }

                  final group = filteredGroups[index - 1];
                  return Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ExpansionTile(
                      tilePadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      childrenPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      title: Text(
                        group.city,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      subtitle: Text(
                        '${group.clients.length} clienti • ${group.totalMachines} macchine • ${group.totalShots} erogazioni',
                        style: const TextStyle(fontSize: 12),
                      ),
                      children: [
                        for (final c in group.clients)
                          ListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 8),
                            title: Text(c.clientName),
                            subtitle: Text(
                              'Macchine: ${c.machineCount} • Erogazioni: ${c.totalShots}',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              context.push('/admin/clients/${c.clientId}');
                            },
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

  List<_CityGroup> _applyFiltersAndSorting(
    List<_CityGroup> original,
    String searchQuery,
    String cityFilter,
    bool onlyWithMachines,
    _ClientSortMode sortMode,
  ) {
    final query = searchQuery.trim().toLowerCase();

    final List<_CityGroup> result = [];

    for (final group in original) {
      // filtro città
      if (cityFilter != 'Tutte le città' && group.city != cityFilter) {
        continue;
      }

      // filtro per cliente
      final List<_ClientAggregate> filteredClients = group.clients.where((c) {
        if (onlyWithMachines && c.machineCount == 0) return false;
        if (query.isNotEmpty &&
            !c.clientName.toLowerCase().contains(query)) {
          return false;
        }
        return true;
      }).toList();

      if (filteredClients.isEmpty) continue;

      // ordinamento clienti dentro la città
      filteredClients.sort((a, b) {
        switch (sortMode) {
          case _ClientSortMode.shotsDesc:
            return b.totalShots.compareTo(a.totalShots);
          case _ClientSortMode.machinesDesc:
            return b.machineCount.compareTo(a.machineCount);
          case _ClientSortMode.nameAsc:
            return a.clientName.toLowerCase().compareTo(
                  b.clientName.toLowerCase(),
                );
        }
      });

      // ricalcolo aggregati della città in base ai clienti filtrati
      final totalMachines =
          filteredClients.fold<int>(0, (sum, c) => sum + c.machineCount);
      final totalShots =
          filteredClients.fold<int>(0, (sum, c) => sum + c.totalShots);

      result.add(
        _CityGroup(
          city: group.city,
          clients: filteredClients,
          totalMachines: totalMachines,
          totalShots: totalShots,
        ),
      );
    }

    // ordina città alfabeticamente
    result.sort((a, b) => a.city.compareTo(b.city));
    return result;
  }
}

class _FiltersCard extends StatelessWidget {
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;

  final String cityFilter;
  final List<String> cityOptions;
  final ValueChanged<String?> onCityChanged;

  final bool onlyWithMachines;
  final ValueChanged<bool?> onOnlyWithMachinesChanged;

  final _ClientSortMode sortMode;
  final ValueChanged<_ClientSortMode?> onSortModeChanged;

  const _FiltersCard({
    required this.searchQuery,
    required this.onSearchChanged,
    required this.cityFilter,
    required this.cityOptions,
    required this.onCityChanged,
    required this.onlyWithMachines,
    required this.onOnlyWithMachinesChanged,
    required this.sortMode,
    required this.onSortModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: 'Cerca cliente',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
              onChanged: onSearchChanged,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: cityFilter,
                    decoration: const InputDecoration(
                      labelText: 'Città',
                      isDense: true,
                    ),
                    items: cityOptions
                        .map(
                          (c) => DropdownMenuItem(
                            value: c,
                            child: Text(c),
                          ),
                        )
                        .toList(),
                    onChanged: onCityChanged,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<_ClientSortMode>(
                    initialValue: sortMode,
                    decoration: const InputDecoration(
                      labelText: 'Ordina per',
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: _ClientSortMode.shotsDesc,
                        child: Text('Erogazioni (↓)'),
                      ),
                      DropdownMenuItem(
                        value: _ClientSortMode.machinesDesc,
                        child: Text('Macchine (↓)'),
                      ),
                      DropdownMenuItem(
                        value: _ClientSortMode.nameAsc,
                        child: Text('Nome (A-Z)'),
                      ),
                    ],
                    onChanged: onSortModeChanged,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Solo clienti con almeno una macchina',
                style: TextStyle(fontSize: 13),
              ),
              value: onlyWithMachines,
              onChanged: onOnlyWithMachinesChanged,
              activeThumbColor: theme.colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminClientsData {
  final List<_CityGroup> groups;
  _AdminClientsData({required this.groups});
}

class _CityGroup {
  final String city;
  final List<_ClientAggregate> clients;
  final int totalMachines;
  final int totalShots;

  _CityGroup({
    required this.city,
    required this.clients,
    required this.totalMachines,
    required this.totalShots,
  });
}

class _ClientAggregate {
  final String clientId;
  final String clientName;
  final String city;
  int machineCount;
  int totalShots;

  _ClientAggregate({
    required this.clientId,
    required this.clientName,
    required this.city,
    required this.machineCount,
    required this.totalShots,
  });
}

enum _ClientSortMode {
  shotsDesc,
  machinesDesc,
  nameAsc,
}
