// lib/features/machines/presentation/machine_detail_page.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// ===============================================================
/// MachineDetailPage (Consumabili a dosi)
///
/// - Carica i dati macchina + consumabili dalla view:
///     public.machine_effective_consumables
///   (rispetta assegnazioni temporanee tramite machine_effective_assignment)
///
/// - Ogni consumabile ha:
///     capacity_units (massimo)
///     current_units  (rimanente)
///     is_enabled
///
/// - Mostra una griglia 2x2 di mini-cerchi (coffee/milk/powder/water).
/// - Per ogni consumabile abilitat0, mostra bottone singolo "Refill"
///   che chiama RPC:
///     perform_refill_consumable(p_machine_id, p_type)
///   (reset current_units = capacity_units in modo atomico lato DB)
/// ===============================================================

enum ConsumableType { coffee, milk, powder, water }

ConsumableType? consumableTypeFromDb(String s) {
  switch (s) {
    case 'coffee':
      return ConsumableType.coffee;
    case 'milk':
      return ConsumableType.milk;
    case 'powder':
      return ConsumableType.powder;
    case 'water':
      return ConsumableType.water;
    default:
      return null;
  }
}

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
      return Icons.local_drink; // semplice e leggibile
    case ConsumableType.powder:
      return Icons.grain;
    case ConsumableType.water:
      return Icons.water_drop;
  }
}

class ConsumableState {
  final ConsumableType type;
  final int capacityUnits;
  final int currentUnits;
  final bool isEnabled;
  final DateTime? updatedAt;

  const ConsumableState({
    required this.type,
    required this.capacityUnits,
    required this.currentUnits,
    required this.isEnabled,
    required this.updatedAt,
  });

  double get percent {
    if (!isEnabled) return 0;
    if (capacityUnits <= 0) return 0;
    final p = (currentUnits / capacityUnits) * 100.0;
    if (p.isNaN || p.isInfinite) return 0;
    return p.clamp(0, 100);
  }

  bool get isFull => isEnabled && capacityUnits > 0 && currentUnits >= capacityUnits;
  bool get isConfigMissing => isEnabled && capacityUnits <= 0;

  factory ConsumableState.fromMap(Map<String, dynamic> map) {
    final t = consumableTypeFromDb(map['consumable_type'] as String? ?? '');
    if (t == null) {
      throw Exception('Consumable type sconosciuto: ${map['consumable_type']}');
    }

    final cap = (map['capacity_units'] as num?)?.toInt() ?? 0;
    final cur = (map['current_units'] as num?)?.toInt() ?? 0;
    final enabled = (map['is_enabled'] as bool?) ?? true;

    DateTime? updated;
    final rawUpdated = map['updated_at'];
    if (rawUpdated is String) {
      updated = DateTime.tryParse(rawUpdated);
    }

    // Coerenza: clamp a 0..capacity
    final safeCap = cap < 0 ? 0 : cap;
    final safeCur = cur < 0 ? 0 : cur;
    final normalizedCur = safeCap > 0 ? safeCur.clamp(0, safeCap) : safeCur;

    return ConsumableState(
      type: t,
      capacityUnits: safeCap,
      currentUnits: normalizedCur,
      isEnabled: enabled,
      updatedAt: updated,
    );
  }
}

class MachineHeaderModel {
  final String machineId;
  final String machineCode;
  final String? siteName;
  final String? clientName;

  const MachineHeaderModel({
    required this.machineId,
    required this.machineCode,
    required this.siteName,
    required this.clientName,
  });
}

class MachineDetailPage extends StatefulWidget {
  final String machineId;

  const MachineDetailPage({
    super.key,
    required this.machineId,
  });

  @override
  State<MachineDetailPage> createState() => _MachineDetailPageState();
}

class _MachineDetailPageState extends State<MachineDetailPage> {
  bool _loading = true;
  String? _error;

  MachineHeaderModel? _header;
  final Map<ConsumableType, ConsumableState> _consumables = {};

  ConsumableType? _refillLoadingType;
  String? _refillError;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    setState(() {
      _loading = true;
      _error = null;
      _refillError = null;
    });

    try {
      if (user == null) {
        throw Exception('Utente non autenticato.');
      }

      final rows = await supabase
          .from('machine_effective_consumables')
          .select(
            'machine_id, machine_code, site_name, client_name, effective_operator_id, consumable_type, capacity_units, current_units, is_enabled, updated_at',
          )
          .eq('machine_id', widget.machineId);

      final list = (rows as List).cast<Map<String, dynamic>>();
      if (list.isEmpty) {
        throw Exception('Macchina non trovata o nessun consumabile disponibile.');
      }

      // Guardrail: l’utente deve essere l’assegnatario effettivo
      final effectiveOperatorId = list.first['effective_operator_id'] as String?;
      if (effectiveOperatorId != null && effectiveOperatorId != user.id) {
        throw Exception('Non sei assegnato a questa macchina.');
      }

      final machineId = list.first['machine_id'] as String? ?? widget.machineId;
      final machineCode = list.first['machine_code'] as String? ?? 'N/D';
      final siteName = list.first['site_name'] as String?;
      final clientName = list.first['client_name'] as String?;

      final header = MachineHeaderModel(
        machineId: machineId,
        machineCode: machineCode,
        siteName: siteName,
        clientName: clientName,
      );

      final map = <ConsumableType, ConsumableState>{};
      for (final r in list) {
        try {
          final cs = ConsumableState.fromMap(r);
          map[cs.type] = cs;
        } catch (_) {
          // ignora consumabili sconosciuti per robustezza
        }
      }

      setState(() {
        _header = header;
        _consumables
          ..clear()
          ..addAll(map);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Errore nel caricamento: $e';
        _loading = false;
      });
    }
  }

  Color _colorForPercent(double percent) {
    // Soglie semplici e leggibili
    if (percent <= 10) return Colors.black;
    if (percent <= 20) return Colors.red;
    if (percent <= 40) return Colors.orange;
    return Colors.green;
  }

  String _labelForPercent(double percent) {
    if (percent <= 10) return 'Critico';
    if (percent <= 20) return 'Basso';
    if (percent <= 40) return 'Attenzione';
    return 'OK';
  }

  Future<void> _refillOne(ConsumableType type) async {
    final supabase = Supabase.instance.client;
    final header = _header;
    if (header == null) return;

    setState(() {
      _refillLoadingType = type;
      _refillError = null;
    });

    try {
      await supabase.rpc('perform_refill_consumable', params: {
        'p_machine_id': header.machineId,
        'p_type': consumableTypeToDb(type),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Refill ${consumableLabel(type)} registrato.')),
        );
      }

      await _loadAll();
    } catch (e) {
      setState(() {
        _refillError = 'Errore refill ${consumableLabel(type)}: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _refillLoadingType = null;
        });
      }
    }
  }

  List<ConsumableType> _orderedTypes() {
    // Ordine fisso e coerente con UX
    return const [
      ConsumableType.coffee,
      ConsumableType.milk,
      ConsumableType.powder,
      ConsumableType.water,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final header = _header;

    return Scaffold(
      appBar: AppBar(
        title: Text(header?.machineCode ?? 'Macchina'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : header == null
                  ? const Center(child: Text('Macchina non trovata.'))
                  : RefreshIndicator(
                      onRefresh: _loadAll,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          _buildInfoCard(header),
                          const SizedBox(height: 16),
                          _buildConsumablesGrid(),
                          const SizedBox(height: 16),
                          if (_refillError != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                _refillError!,
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
    );
  }

  Widget _buildInfoCard(MachineHeaderModel header) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Informazioni macchina',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            _infoRow('Cliente', (header.clientName ?? '').isEmpty ? '-' : header.clientName!),
            if ((header.siteName ?? '').isNotEmpty) ...[
              const SizedBox(height: 4),
              _infoRow('Sede', header.siteName!),
            ],
            const SizedBox(height: 4),
            _infoRow('Codice macchina', header.machineCode),
          ],
        ),
      ),
    );
  }

  Widget _buildConsumablesGrid() {
    final types = _orderedTypes();

    // Se water è disabled/non presente, la card rimane nascosta
    final items = <ConsumableType>[];
    for (final t in types) {
      final cs = _consumables[t];
      if (cs == null) continue;
      if (!cs.isEnabled) continue;
      items.add(t);
    }

    if (items.isEmpty) {
      return const Center(child: Text('Nessun consumabile configurato per questa macchina.'));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // 2 colonne quasi sempre; se desktop molto largo, al massimo 4 in riga.
        final w = constraints.maxWidth;
        final crossAxisCount = w >= 900 ? 4 : (w >= 520 ? 2 : 2);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Serbatoi (dosi)',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                // card compatta e stabile su web/mobile
                childAspectRatio: w >= 900 ? 1.2 : 1.05,
              ),
              itemBuilder: (context, index) {
                final type = items[index];
                final cs = _consumables[type]!;
                return _buildConsumableCard(cs);
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildConsumableCard(ConsumableState cs) {
    final percent = cs.percent;
    final color = _colorForPercent(percent);
    final label = _labelForPercent(percent);

    final isLoadingThis = _refillLoadingType == cs.type;
    final canRefill = cs.isEnabled && !cs.isConfigMissing && !cs.isFull && !isLoadingThis;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Titolo riga: icona + label
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(consumableIcon(cs.type), size: 18, color: Colors.grey),
                const SizedBox(width: 8),
                Text(
                  consumableLabel(cs.type),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Cerchio con %
            SizedBox(
              width: 92,
              height: 92,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 92,
                    height: 92,
                    child: CircularProgressIndicator(
                      value: percent / 100.0,
                      strokeWidth: 9,
                      backgroundColor: color.withValues(alpha: 0.12),
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${percent.toStringAsFixed(0)}%',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // Dosi
            Text(
              cs.isConfigMissing
                  ? 'Capacità non impostata'
                  : '${cs.currentUnits} / ${cs.capacityUnits} dosi',
              style: TextStyle(
                fontSize: 12,
                color: cs.isConfigMissing ? Colors.red : Colors.grey,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),

            const Spacer(),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: canRefill ? () => _refillOne(cs.type) : null,
                icon: isLoadingThis
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.refresh, size: 18),
                label: Text(
                  cs.isFull
                      ? 'Pieno'
                      : cs.isConfigMissing
                          ? 'Configura'
                          : 'Refill',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            '$label:',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.grey,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
