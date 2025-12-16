import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminCoveragePlanPage extends StatefulWidget {
  final String unavailabilityId;

  const AdminCoveragePlanPage({
    super.key,
    required this.unavailabilityId,
  });

  @override
  State<AdminCoveragePlanPage> createState() => _AdminCoveragePlanPageState();
}

class _AdminCoveragePlanPageState extends State<AdminCoveragePlanPage> {
  late Future<bool> _isAdminFuture;

  bool _loading = true;
  bool _saving = false;

  _Unavailability? _absence;
  List<_AssignmentRow> _rows = [];
  List<_ProfileItem> _operators = [];

  @override
  void initState() {
    super.initState();
    _isAdminFuture = _checkIfAdmin();
    _load();
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

  Future<void> _load() async {
    setState(() => _loading = true);
    final supabase = Supabase.instance.client;

    try {
      // assenza
      final absenceRow = await supabase
          .from('operator_unavailability')
          .select('id, operator_id, start_date, end_date, reason')
          .eq('id', widget.unavailabilityId)
          .maybeSingle();

      if (absenceRow == null) {
        setState(() {
          _absence = null;
          _rows = [];
        });
        return;
      }

      final abs = _Unavailability(
        id: absenceRow['id'] as String,
        operatorId: absenceRow['operator_id'] as String,
        startDate: DateTime.parse(absenceRow['start_date'] as String),
        endDate: DateTime.parse(absenceRow['end_date'] as String),
        reason: absenceRow['reason'] as String?,
      );

      // operatori
      final operatorsRows = await supabase
          .from('profiles')
          .select('id, full_name')
          .eq('role', 'refill_operator')
          .order('full_name');

      _operators = (operatorsRows as List)
          .map((m) => m as Map<String, dynamic>)
          .map((m) => _ProfileItem(
                id: m['id'] as String,
                name: (m['full_name'] as String?) ?? 'Operatore',
              ))
          .toList();

      // suggested assignments: filtriamo per operatore assente + date (v1)
      final start = abs.startDate.toIso8601String().substring(0, 10);
      final end = abs.endDate.toIso8601String().substring(0, 10);

      final assignmentsRows = await supabase
          .from('temp_machine_assignments')
          .select('id, machine_id, original_operator_id, new_operator_id, start_date, end_date, status')
          .eq('original_operator_id', abs.operatorId)
          .eq('start_date', start)
          .eq('end_date', end)
          .eq('status', 'suggested');

      final assignmentList = (assignmentsRows as List)
          .map((m) => m as Map<String, dynamic>)
          .toList();

      // info macchine+site+client per rendering
      final machineIds =
          assignmentList.map((a) => a['machine_id'] as String).toSet().toList();

      Map<String, _MachineInfo> machineInfoById = {};
      if (machineIds.isNotEmpty) {
        final machineRows = await supabase
            .from('machines')
            .select('id, code, site_id, sites(name, city, clients(name))')
            .inFilter('id', machineIds);

        for (final r in (machineRows as List).cast<Map<String, dynamic>>()) {
          final site = r['sites'] as Map<String, dynamic>?;
          final client = site?['clients'] as Map<String, dynamic>?;
          machineInfoById[r['id'] as String] = _MachineInfo(
            code: r['code'] as String? ?? 'N/D',
            siteName: site?['name'] as String?,
            city: site?['city'] as String?,
            clientName: client?['name'] as String?,
          );
        }
      }

      _rows = assignmentList.map((a) {
        final id = a['id'] as String;
        final machineId = a['machine_id'] as String;
        return _AssignmentRow(
          id: id,
          machineId: machineId,
          machineInfo: machineInfoById[machineId],
          newOperatorId: a['new_operator_id'] as String,
        );
      }).toList();

      setState(() {
        _absence = abs;
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _updateRowOperator(_AssignmentRow row, String newOperatorId) async {
    setState(() {
      row.newOperatorId = newOperatorId;
    });

    final supabase = Supabase.instance.client;
    await supabase.from('temp_machine_assignments').update({
      'new_operator_id': newOperatorId,
    }).eq('id', row.id);
  }

  Future<void> _confirmPlan() async {
    if (_absence == null) return;
    if (_rows.isEmpty) return;

    setState(() => _saving = true);
    final supabase = Supabase.instance.client;

    try {
      final start = _absence!.startDate.toIso8601String().substring(0, 10);
      final end = _absence!.endDate.toIso8601String().substring(0, 10);

      await supabase
          .from('temp_machine_assignments')
          .update({'status': 'confirmed'})
          .eq('original_operator_id', _absence!.operatorId)
          .eq('start_date', start)
          .eq('end_date', end)
          .eq('status', 'suggested');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Piano confermato.')),
      );

      context.go('/admin');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore conferma: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
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
            appBar: AppBar(title: const Text('Piano copertura')),
            body: const Center(child: Text('Accesso riservato agli admin.')),
          );
        }

        final user = Supabase.instance.client.auth.currentUser;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Piano suggerito'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.go('/admin/coverage'),
            ),
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
              : (_absence == null)
                  ? const Center(child: Text('Assenza non trovata.'))
                  : Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 900),
                        child: ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            _AbsenceHeader(absence: _absence!),
                            const SizedBox(height: 12),
                            if (_rows.isEmpty)
                              const Card(
                                child: Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Text(
                                      'Nessuna macchina da riassegnare (o piano già generato/confirmato).'),
                                ),
                              )
                            else
                              Card(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: ListView.separated(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: _rows.length,
                                  separatorBuilder: (_, __) =>
                                      const Divider(height: 1),
                                  itemBuilder: (context, i) {
                                    final r = _rows[i];
                                    final info = r.machineInfo;

                                    return ListTile(
                                      title: Text(
                                        info == null
                                            ? 'Macchina'
                                            : 'Macchina ${info.code}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      subtitle: Text(
                                        [
                                          if (info?.clientName != null)
                                            info!.clientName!,
                                          if (info?.siteName != null)
                                            info!.siteName!,
                                          if (info?.city != null) info!.city!,
                                        ].join(' • '),
                                      ),
                                      trailing: SizedBox(
                                        width: 260,
                                        child: DropdownButtonFormField<String>(
                                          initialValue: r.newOperatorId,
                                          decoration: const InputDecoration(
                                            labelText: 'Assegna a',
                                            isDense: true,
                                          ),
                                          items: _operators
                                              .where((o) =>
                                                  o.id != _absence!.operatorId)
                                              .map(
                                                (o) => DropdownMenuItem(
                                                  value: o.id,
                                                  child: Text(o.name),
                                                ),
                                              )
                                              .toList(),
                                          onChanged: (value) {
                                            if (value == null) return;
                                            _updateRowOperator(r, value);
                                          },
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: _saving ? null : _confirmPlan,
                              icon: _saving
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.check),
                              label: const Text('Conferma piano'),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Nota: dopo la conferma, le assegnazioni temporanee vengono applicate agli operatori durante il periodo selezionato, senza modificare l’assegnazione “di default” delle macchine.',
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

class _AbsenceHeader extends StatelessWidget {
  final _Unavailability absence;
  const _AbsenceHeader({required this.absence});

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Assenza registrata',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Periodo: ${absence.startDate.toIso8601String().substring(0, 10)} → ${absence.endDate.toIso8601String().substring(0, 10)}',
            ),
            if (absence.reason != null && absence.reason!.trim().isNotEmpty)
              Text('Motivo: ${absence.reason}'),
          ],
        ),
      ),
    );
  }
}

class _Unavailability {
  final String id;
  final String operatorId;
  final DateTime startDate;
  final DateTime endDate;
  final String? reason;

  _Unavailability({
    required this.id,
    required this.operatorId,
    required this.startDate,
    required this.endDate,
    required this.reason,
  });
}

class _ProfileItem {
  final String id;
  final String name;
  _ProfileItem({required this.id, required this.name});
}

class _AssignmentRow {
  final String id;
  final String machineId;
  final _MachineInfo? machineInfo;
  String newOperatorId;

  _AssignmentRow({
    required this.id,
    required this.machineId,
    required this.machineInfo,
    required this.newOperatorId,
  });
}

class _MachineInfo {
  final String code;
  final String? siteName;
  final String? city;
  final String? clientName;

  _MachineInfo({
    required this.code,
    required this.siteName,
    required this.city,
    required this.clientName,
  });
}
