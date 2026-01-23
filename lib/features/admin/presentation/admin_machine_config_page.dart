// lib/features/admin/presentation/admin_machine_config_page.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum ConsumableType { coffee, milk, powder, water }

String consumableTypeToDb(ConsumableType t) {
  switch (t) {
    case ConsumableType.coffee:
      return 'coffee';
    case ConsumableType.milk:
      return 'milk';
    case ConsumableType.powder:
      return 'powder';
    case ConsumableType.water:
      return 'water';
  }
}

String consumableLabel(ConsumableType t) {
  switch (t) {
    case ConsumableType.coffee:
      return 'Caffè';
    case ConsumableType.milk:
      return 'Latte';
    case ConsumableType.powder:
      return 'Polveri';
    case ConsumableType.water:
      return 'Acqua';
  }
}

IconData consumableIcon(ConsumableType t) {
  switch (t) {
    case ConsumableType.coffee:
      return Icons.coffee;
    case ConsumableType.milk:
      return Icons.local_drink;
    case ConsumableType.powder:
      return Icons.grain;
    case ConsumableType.water:
      return Icons.water_drop;
  }
}

class MachineOption {
  final String id;
  final String code;

  const MachineOption({required this.id, required this.code});
}

class ConsumableConfigRow {
  final ConsumableType type;
  bool isEnabled;
  int capacityUnits;
  int currentUnits;

  ConsumableConfigRow({
    required this.type,
    required this.isEnabled,
    required this.capacityUnits,
    required this.currentUnits,
  });

  ConsumableConfigRow copy() => ConsumableConfigRow(
        type: type,
        isEnabled: isEnabled,
        capacityUnits: capacityUnits,
        currentUnits: currentUnits,
      );
}

class AdminMachineConfigPage extends StatefulWidget {
  const AdminMachineConfigPage({super.key});

  @override
  State<AdminMachineConfigPage> createState() => _AdminMachineConfigPageState();
}

class _AdminMachineConfigPageState extends State<AdminMachineConfigPage> {
  final _supabase = Supabase.instance.client;

  bool _checkingRole = true;
  bool _isAdmin = false;
  String? _roleError;

  bool _loadingMachines = false;
  List<MachineOption> _machines = [];
  String? _selectedMachineId;

  bool _loadingConfig = false;
  bool _saving = false;
  String? _configError;

  bool _waterTankEnabled = false;

  // UI state for consumables
  final Map<ConsumableType, ConsumableConfigRow> _rows = {
    ConsumableType.coffee: ConsumableConfigRow(
      type: ConsumableType.coffee,
      isEnabled: true,
      capacityUnits: 0,
      currentUnits: 0,
    ),
    ConsumableType.milk: ConsumableConfigRow(
      type: ConsumableType.milk,
      isEnabled: true,
      capacityUnits: 0,
      currentUnits: 0,
    ),
    ConsumableType.powder: ConsumableConfigRow(
      type: ConsumableType.powder,
      isEnabled: true,
      capacityUnits: 0,
      currentUnits: 0,
    ),
    ConsumableType.water: ConsumableConfigRow(
      type: ConsumableType.water,
      isEnabled: false,
      capacityUnits: 0,
      currentUnits: 0,
    ),
  };

  // Controllers (per evitare che il Grid resetti il cursore)
  final Map<ConsumableType, TextEditingController> _capControllers = {};
  final Map<ConsumableType, TextEditingController> _curControllers = {};

  @override
  void initState() {
    super.initState();
    _initControllers();
    _bootstrap();
  }

  void _initControllers() {
    for (final t in ConsumableType.values) {
      _capControllers[t] = TextEditingController(text: '0');
      _curControllers[t] = TextEditingController(text: '0');
    }
  }

  @override
  void dispose() {
    for (final c in _capControllers.values) {
      c.dispose();
    }
    for (final c in _curControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await _checkAdminRole();
    if (!_isAdmin) return;
    await _loadMachines();
  }

  Future<void> _checkAdminRole() async {
    final user = _supabase.auth.currentUser;

    setState(() {
      _checkingRole = true;
      _roleError = null;
      _isAdmin = false;
    });

    try {
      if (user == null) {
        throw Exception('Utente non autenticato.');
      }

      final row = await _supabase
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();

      final role = row?['role'] as String?;
      setState(() {
        _isAdmin = role == 'admin';
        _checkingRole = false;
      });

      if (!_isAdmin) {
        setState(() {
          _roleError = 'Accesso negato: questa pagina è solo per admin.';
        });
      }
    } catch (e) {
      setState(() {
        _roleError = 'Errore verifica ruolo: $e';
        _checkingRole = false;
      });
    }
  }

  Future<void> _loadMachines() async {
    setState(() {
      _loadingMachines = true;
      _machines = [];
    });

    try {
      // Semplice: carico id+code. Se vuoi, possiamo arricchire con site/client.
      final data = await _supabase
          .from('machines')
          .select('id, code')
          .order('code', ascending: true);

      final list = (data as List)
          .cast<Map<String, dynamic>>()
          .map((m) => MachineOption(
                id: m['id'] as String,
                code: (m['code'] as String?) ?? 'N/D',
              ))
          .toList();

      setState(() {
        _machines = list;
        _loadingMachines = false;
        // auto-select first machine for speed
        _selectedMachineId ??= list.isNotEmpty ? list.first.id : null;
      });

      if (_selectedMachineId != null) {
        await _loadMachineConfig(_selectedMachineId!);
      }
    } catch (e) {
      setState(() {
        _loadingMachines = false;
        _configError = 'Errore caricamento macchine: $e';
      });
    }
  }

  Future<void> _loadMachineConfig(String machineId) async {
    setState(() {
      _loadingConfig = true;
      _configError = null;
    });

    try {
      // water_tank_enabled
      final m = await _supabase
          .from('machines')
          .select('water_tank_enabled')
          .eq('id', machineId)
          .maybeSingle();

      final waterTank = (m?['water_tank_enabled'] as bool?) ?? false;

      // consumables rows
      final rows = await _supabase
          .from('machine_consumables')
          .select('type, is_enabled, capacity_units, current_units')
          .eq('machine_id', machineId);

      final map = <String, Map<String, dynamic>>{};
      for (final r in (rows as List).cast<Map<String, dynamic>>()) {
        map[(r['type'] as String?) ?? ''] = r;
      }

      // Apply to UI state with defaults
      void apply(ConsumableType t) {
        final key = consumableTypeToDb(t);
        final r = map[key];
        final enabled = (r?['is_enabled'] as bool?) ?? (t != ConsumableType.water ? true : false);
        final cap = (r?['capacity_units'] as num?)?.toInt() ?? 0;
        final cur = (r?['current_units'] as num?)?.toInt() ?? 0;

        final safeCap = cap < 0 ? 0 : cap;
        final safeCur = cur < 0 ? 0 : cur;
        final normalizedCur = safeCap > 0 ? safeCur.clamp(0, safeCap) : safeCur;

        _rows[t] = ConsumableConfigRow(
          type: t,
          isEnabled: enabled,
          capacityUnits: safeCap,
          currentUnits: normalizedCur,
        );

        _capControllers[t]!.text = safeCap.toString();
        _curControllers[t]!.text = normalizedCur.toString();
      }

      for (final t in ConsumableType.values) {
        apply(t);
      }

      // se water tank è false, forza water disabled in UI (coerente col modello)
      if (!waterTank) {
        final w = _rows[ConsumableType.water]!;
        w.isEnabled = false;
      }

      setState(() {
        _waterTankEnabled = waterTank;
        _loadingConfig = false;
      });
    } catch (e) {
      setState(() {
        _configError = 'Errore caricamento configurazione: $e';
        _loadingConfig = false;
      });
    }
  }

  ConsumableConfigRow _readRowFromControllers(ConsumableType t) {
    final row = _rows[t]!.copy();
    final cap = int.tryParse(_capControllers[t]!.text.trim()) ?? 0;
    final cur = int.tryParse(_curControllers[t]!.text.trim()) ?? 0;

    row.capacityUnits = cap < 0 ? 0 : cap;
    row.currentUnits = cur < 0 ? 0 : cur;

    if (row.capacityUnits > 0) {
      row.currentUnits = row.currentUnits.clamp(0, row.capacityUnits);
    }
    return row;
  }

  String? _validateAll() {
    // water constraints
    if (!_waterTankEnabled) {
      final w = _rows[ConsumableType.water]!;
      if (w.isEnabled) {
        return 'Acqua abilitata ma water_tank_enabled è OFF. Disabilita acqua o abilita tanica.';
      }
    }

    for (final t in ConsumableType.values) {
      final row = _readRowFromControllers(t);
      if (!row.isEnabled) continue;

      // capacity must be >0 for enabled consumables, otherwise operator UX is confusing
      if (row.capacityUnits <= 0) {
        return 'Capacità non valida per ${consumableLabel(t)} (deve essere > 0 se abilitato).';
      }
      if (row.currentUnits < 0 || row.currentUnits > row.capacityUnits) {
        return 'Valore corrente non valido per ${consumableLabel(t)}.';
      }
    }

    return null;
  }

  Future<void> _saveAll() async {
    final machineId = _selectedMachineId;
    if (machineId == null) return;

    final validation = _validateAll();
    if (validation != null) {
      setState(() {
        _configError = validation;
      });
      return;
    }

    setState(() {
      _saving = true;
      _configError = null;
    });

    try {
      // 1) update machine water_tank_enabled
      await _supabase
          .from('machines')
          .update({'water_tank_enabled': _waterTankEnabled})
          .eq('id', machineId);

      // 2) prepare upserts for machine_consumables
      final upserts = <Map<String, dynamic>>[];
      for (final t in ConsumableType.values) {
        final row = _readRowFromControllers(t);

        // Enforce: if tank disabled => water disabled
        final isEnabled = (t == ConsumableType.water && !_waterTankEnabled) ? false : row.isEnabled;

        upserts.add({
          'machine_id': machineId,
          'type': consumableTypeToDb(t),
          'is_enabled': isEnabled,
          'capacity_units': row.capacityUnits,
          'current_units': isEnabled ? row.currentUnits.clamp(0, row.capacityUnits) : 0,
          'updated_at': DateTime.now().toIso8601String(),
        });
      }

      await _supabase.from('machine_consumables').upsert(upserts);

      // 3) If tank disabled, ensure DB water row disabled (safety belt)
      if (!_waterTankEnabled) {
        await _supabase
            .from('machine_consumables')
            .update({'is_enabled': false, 'current_units': 0})
            .eq('machine_id', machineId)
            .eq('type', 'water');
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configurazione salvata.')),
      );

      // refresh from DB to ensure what you see is truth
      await _loadMachineConfig(machineId);
    } catch (e) {
      setState(() {
        _configError = 'Errore salvataggio: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _onChangeMachine(String? id) async {
    if (id == null) return;
    setState(() {
      _selectedMachineId = id;
    });
    await _loadMachineConfig(id);
  }

  @override
  Widget build(BuildContext context) {
    final user = _supabase.auth.currentUser;

    if (_checkingRole) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_isAdmin) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Backoffice Serbatoi'),
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
        body: Center(child: Text(_roleError ?? 'Accesso negato.')),
      );
    }

    final selected = _machines.where((m) => m.id == _selectedMachineId).toList();
    final selectedLabel = selected.isNotEmpty ? selected.first.code : 'Seleziona macchina';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Backoffice Serbatoi (Dev)'),
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
      body: _loadingMachines
          ? const Center(child: CircularProgressIndicator())
          : _machines.isEmpty
              ? const Center(child: Text('Nessuna macchina trovata.'))
              : RefreshIndicator(
                  onRefresh: () async {
                    await _loadMachines();
                  },
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildMachinePickerCard(selectedLabel),
                      const SizedBox(height: 12),
                      _buildWaterTankCard(),
                      const SizedBox(height: 12),
                      _buildConsumablesCard(),
                      const SizedBox(height: 12),
                      if (_configError != null)
                        Text(
                          _configError!,
                          style: const TextStyle(color: Colors.red, fontSize: 13),
                        ),
                      const SizedBox(height: 12),
                      _buildSaveBar(),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
    );
  }

  Widget _buildMachinePickerCard(String selectedLabel) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Selezione macchina',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _selectedMachineId,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
                labelText: 'Macchina',
              ),
              items: _machines
                  .map(
                    (m) => DropdownMenuItem(
                      value: m.id,
                      child: Text(m.code),
                    ),
                  )
                  .toList(),
              onChanged: _loadingConfig ? null : _onChangeMachine,
            ),
            const SizedBox(height: 8),
            Text(
              'Selezionata: $selectedLabel',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWaterTankCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: [
            const Icon(Icons.water_drop, color: Colors.grey),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Tanica acqua (water_tank_enabled)',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            Switch(
              value: _waterTankEnabled,
              onChanged: _loadingConfig
                  ? null
                  : (v) {
                      setState(() {
                        _waterTankEnabled = v;
                        if (!v) {
                          // se disabiliti la tanica, l’acqua deve essere off
                          _rows[ConsumableType.water]!.isEnabled = false;
                        }
                      });
                    },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConsumablesCard() {
    if (_loadingConfig) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Serbatoi per consumabile (dosi)',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const Text(
              'capacity_units = massimo, current_units = rimanenza. Se un consumabile è abilitato, capacity deve essere > 0.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final cross = w >= 900 ? 2 : 1;

                return GridView.count(
                  crossAxisCount: cross,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: cross == 2 ? 3.2 : 2.9,
                  children: ConsumableType.values.map(_buildConsumableEditorTile).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConsumableEditorTile(ConsumableType t) {
    final row = _rows[t]!;
    final isWater = t == ConsumableType.water;
    final waterBlocked = isWater && !_waterTankEnabled;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(consumableIcon(t), color: Colors.grey),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  consumableLabel(t),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
              Switch(
                value: waterBlocked ? false : row.isEnabled,
                onChanged: (_saving || waterBlocked)
                    ? null
                    : (v) {
                        setState(() {
                          row.isEnabled = v;
                          if (!v) {
                            _capControllers[t]!.text = _capControllers[t]!.text; // keep
                            _curControllers[t]!.text = '0';
                          }
                        });
                      },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _capControllers[t],
                  keyboardType: TextInputType.number,
                  enabled: !_saving && !waterBlocked && row.isEnabled,
                  decoration: const InputDecoration(
                    labelText: 'Capacity (dosi)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  controller: _curControllers[t],
                  keyboardType: TextInputType.number,
                  enabled: !_saving && !waterBlocked && row.isEnabled,
                  decoration: const InputDecoration(
                    labelText: 'Current (dosi)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (waterBlocked)
            const Text(
              'Acqua disabilitata: tanica OFF.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            )
          else if (!row.isEnabled)
            const Text(
              'Consumabile disabilitato.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            )
          else
            const Text(
              'Suggerimento: imposta current = capacity dopo ricarica iniziale.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
        ],
      ),
    );
  }

  Widget _buildSaveBar() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: (_saving || _selectedMachineId == null) ? null : () => _loadMachineConfig(_selectedMachineId!),
            icon: const Icon(Icons.refresh),
            label: const Text('Ricarica'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: (_saving || _selectedMachineId == null) ? null : _saveAll,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.save),
            label: Text(_saving ? 'Salvataggio...' : 'Salva'),
          ),
        ),
      ],
    );
  }
}
