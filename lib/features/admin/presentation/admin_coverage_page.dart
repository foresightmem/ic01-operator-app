import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminCoveragePage extends StatefulWidget {
  const AdminCoveragePage({super.key});

  @override
  State<AdminCoveragePage> createState() => _AdminCoveragePageState();
}

class _AdminCoveragePageState extends State<AdminCoveragePage> {
  late Future<bool> _isAdminFuture;

  bool _loading = true;
  bool _submitting = false;

  List<_ProfileItem> _operators = [];
  _ProfileItem? _selectedOperator;

  DateTime? _startDate;
  DateTime? _endDate;
  final _reasonController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _isAdminFuture = _checkIfAdmin();
    _bootstrap();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
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

  Future<void> _bootstrap() async {
    setState(() => _loading = true);
    final supabase = Supabase.instance.client;

    try {
      final rows = await supabase
          .from('profiles')
          .select('id, full_name, role')
          .eq('role', 'refill_operator')
          .order('full_name');

      _operators = (rows as List)
          .map((r) => r as Map<String, dynamic>)
          .map((m) => _ProfileItem(
                id: m['id'] as String,
                name: (m['full_name'] as String?) ?? 'Operatore',
              ))
          .toList();

      if (_operators.isNotEmpty) {
        _selectedOperator = _operators.first;
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart
        ? (_startDate ?? DateTime.now())
        : (_endDate ?? _startDate ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;

    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_endDate != null && _endDate!.isBefore(picked)) {
          _endDate = picked;
        }
      } else {
        _endDate = picked;
      }
    });
  }

  Future<void> _createAbsenceAndGeneratePlan() async {
    if (_selectedOperator == null) return;
    if (_startDate == null || _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleziona inizio e fine assenza.')),
      );
      return;
    }

    setState(() => _submitting = true);

    final supabase = Supabase.instance.client;

    try {
      // 1) crea assenza
      final created = await supabase
          .from('operator_unavailability')
          .insert({
            'operator_id': _selectedOperator!.id,
            'start_date': _startDate!.toIso8601String().substring(0, 10),
            'end_date': _endDate!.toIso8601String().substring(0, 10),
            'reason': _reasonController.text.trim().isEmpty
                ? null
                : _reasonController.text.trim(),
          })
          .select('id')
          .single();

      final unavailabilityId = created['id'] as String;

      // 2) genera piano suggested
      await _generateSuggestedPlan(
        unavailabilityId: unavailabilityId,
        absentOperatorId: _selectedOperator!.id,
        startDate: _startDate!,
        endDate: _endDate!,
      );

      if (!mounted) return;
      context.push('/admin/coverage/$unavailabilityId');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Algoritmo v1:
  /// - prende tutte le macchine del refill_operator assente
  /// - le raggruppa per city (via sites.city)
  /// - per ciascuna city distribuisce sulle risorse disponibili (altri operatori)
  ///   bilanciando per numero macchine attualmente assegnate in quella city.
  Future<void> _generateSuggestedPlan({
    required String unavailabilityId,
    required String absentOperatorId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final supabase = Supabase.instance.client;

    // cancella eventuali suggestion precedenti per lo stesso range/operatore
    await supabase
        .from('temp_machine_assignments')
        .delete()
        .eq('original_operator_id', absentOperatorId)
        .eq('start_date', startDate.toIso8601String().substring(0, 10))
        .eq('end_date', endDate.toIso8601String().substring(0, 10))
        .eq('status', 'suggested');

    // macchine dell'assente + city
    // TODO: Consider also machines temporarily assigned to the absent operator
    // via confirmed temp_machine_assignments for the selected period.
    final machinesRows = await supabase
        .from('machines')
        .select('id, site_id')
        .eq('assigned_operator_id', absentOperatorId);

    final machines = (machinesRows as List)
        .map((e) => e as Map<String, dynamic>)
        .toList();

    if (machines.isEmpty) return;

    final siteIds = machines
        .map((m) => m['site_id'] as String)
        .toSet()
        .toList(growable: false);

    final sitesRows = await supabase
        .from('sites')
        .select('id, city, client_id')
        .inFilter('id', siteIds);

    final Map<String, String> siteIdToCity = {
      for (final s in (sitesRows as List).cast<Map<String, dynamic>>())
        s['id'] as String: ((s['city'] as String?)?.trim().isNotEmpty == true)
            ? (s['city'] as String)
            : 'Senza città',
    };

    final Map<String, String> siteIdToClientId = {
      for (final s in (sitesRows).cast<Map<String, dynamic>>())
        s['id'] as String: (s['client_id'] as String?) ?? 'unknown-client',
    };

    // macchine raggruppate per city -> client
    final Map<String, Map<String, List<String>>> machineIdsByCityClient = {};
    for (final m in machines) {
      final siteId = m['site_id'] as String;
      final city = siteIdToCity[siteId] ?? 'Senza città';
      final clientId = siteIdToClientId[siteId] ?? 'unknown-client';
      machineIdsByCityClient.putIfAbsent(city, () => {});
      machineIdsByCityClient[city]!
          .putIfAbsent(clientId, () => [])
          .add(m['id'] as String);
    }

    // candidati: tutti gli operatori refill tranne l'assente
    final operatorsRows = await supabase
        .from('profiles')
        .select('id, full_name')
        .eq('role', 'refill_operator');

    final candidates = (operatorsRows as List)
        .map((e) => e as Map<String, dynamic>)
        .map((m) => m['id'] as String)
        .where((id) => id != absentOperatorId)
        .toList();

    if (candidates.isEmpty) return;

    // carico per city: quante macchine ha ogni candidato in quella city
    // (approssimazione v1: conteggio su assigned_operator_id)
    final allMachinesRows = await supabase
        .from('machines')
        .select('id, site_id, assigned_operator_id')
        .inFilter('assigned_operator_id', candidates);

    final allMachines = (allMachinesRows as List)
        .map((e) => e as Map<String, dynamic>)
        .toList();

    // per ottenere city delle macchine dei candidati
    final candSiteIds = allMachines
        .map((m) => m['site_id'] as String)
        .toSet()
        .toList(growable: false);

    final candSitesRows = candSiteIds.isEmpty
        ? <dynamic>[]
        : await supabase
            .from('sites')
            .select('id, city')
            .inFilter('id', candSiteIds);

    final Map<String, String> candSiteIdToCity = {
      for (final s in (candSitesRows).cast<Map<String, dynamic>>())
        s['id'] as String: ((s['city'] as String?)?.trim().isNotEmpty == true)
            ? (s['city'] as String)
            : 'Senza città',
    };

    // load[city][operatorId] = count
    final Map<String, Map<String, int>> load = {};

    for (final m in allMachines) {
      final opId = m['assigned_operator_id'] as String;
      final siteId = m['site_id'] as String;
      final city = candSiteIdToCity[siteId] ?? 'Senza città';
      load.putIfAbsent(city, () => {});
      load[city]![opId] = (load[city]![opId] ?? 0) + 1;
    }

    final start = startDate.toIso8601String().substring(0, 10);
    final end = endDate.toIso8601String().substring(0, 10);

    final inserts = <Map<String, dynamic>>[];

    for (final entry in machineIdsByCityClient.entries) {
      final city = entry.key;
      final clientsToMachines = entry.value;

      // se non ho load per quella city, inizializzo a 0 per tutti
      load.putIfAbsent(city, () => {});

      final clientGroups = clientsToMachines.entries.toList()
        ..sort((a, b) => b.value.length.compareTo(a.value.length));

      for (final clientEntry in clientGroups) {
        final machineIds = clientEntry.value;

        // scegli candidato con load minimo in quella city
        String chosen = candidates.first;
        int chosenLoad = load[city]![chosen] ?? 0;

        for (final opId in candidates) {
          final l = load[city]![opId] ?? 0;
          if (l < chosenLoad) {
            chosen = opId;
            chosenLoad = l;
          }
        }

        for (final machineId in machineIds) {
          inserts.add({
            'machine_id': machineId,
            'original_operator_id': absentOperatorId,
            'new_operator_id': chosen,
            'start_date': start,
            'end_date': end,
            'status': 'suggested',
          });
        }

        // aggiorna load
        load[city]![chosen] =
            (load[city]![chosen] ?? 0) + machineIds.length;
      }
    }

    if (inserts.isNotEmpty) {
      // bulk insert
      await supabase.from('temp_machine_assignments').insert(inserts);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _isAdminFuture,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final isAdmin = snap.data ?? false;

        if (!isAdmin) {
          return Scaffold(
            appBar: AppBar(title: const Text('Copertura turni')),
            body: const Center(child: Text('Accesso riservato agli admin.')),
          );
        }

        final user = Supabase.instance.client.auth.currentUser;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Copertura assenze'),
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
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 700),
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Text(
                          'Nuova assenza operatore',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 12),
                        Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                DropdownButtonFormField<_ProfileItem>(
                                  initialValue: _selectedOperator,
                                  decoration: const InputDecoration(
                                    labelText: 'Operatore assente',
                                  ),
                                  items: _operators
                                      .map(
                                        (o) => DropdownMenuItem(
                                          value: o,
                                          child: Text(o.name),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (value) {
                                    setState(() => _selectedOperator = value);
                                  },
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () => _pickDate(isStart: true),
                                        icon: const Icon(Icons.date_range),
                                        label: Text(
                                          _startDate == null
                                              ? 'Inizio'
                                              : _startDate!
                                                  .toIso8601String()
                                                  .substring(0, 10),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () => _pickDate(isStart: false),
                                        icon: const Icon(Icons.date_range_outlined),
                                        label: Text(
                                          _endDate == null
                                              ? 'Fine'
                                              : _endDate!
                                                  .toIso8601String()
                                                  .substring(0, 10),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _reasonController,
                                  decoration: const InputDecoration(
                                    labelText: 'Motivo (opzionale)',
                                  ),
                                ),
                                const SizedBox(height: 16),
                                FilledButton.icon(
                                  onPressed: _submitting
                                      ? null
                                      : _createAbsenceAndGeneratePlan,
                                  icon: _submitting
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.auto_fix_high),
                                  label: const Text('Genera piano suggerito'),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Nota: v2 distribuisce per cliente (azienda) all’interno di ogni città, bilanciando il carico per città.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }
}

class _ProfileItem {
  final String id;
  final String name;

  _ProfileItem({required this.id, required this.name});
}
