// lib/features/machines/presentation/machine_detail_page.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/ui/app_design_system.dart';

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
/// - Mostra il solo fattore monitorato per il tipo macchina (hot/cold).
/// - Per il fattore abilitato, mostra bottone singolo "Refill"
///   che chiama RPC:
///     perform_refill_consumable(p_machine_id, p_type)
///   (reset current_units = capacity_units in modo atomico lato DB)
/// ===============================================================

enum ConsumableType { hot, cold, coffee, milk, powder, water }

ConsumableType? consumableTypeFromDb(String s) {
  switch (s) {
    case 'hot':
      return ConsumableType.hot;
    case 'cold':
      return ConsumableType.cold;
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
    case ConsumableType.hot:
      return 'hot';
    case ConsumableType.cold:
      return 'cold';
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
    case ConsumableType.hot:
      return 'Caldo';
    case ConsumableType.cold:
      return 'Freddo';
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
    case ConsumableType.hot:
      return Icons.local_fire_department;
    case ConsumableType.cold:
      return Icons.ac_unit;
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

  bool get isFull =>
      isEnabled && capacityUnits > 0 && currentUnits >= capacityUnits;
  bool get isConfigMissing => isEnabled && capacityUnits <= 0;

  factory ConsumableState.fromMap(Map<String, dynamic> map) {
    final t = consumableTypeFromDb(map['type'] as String? ?? '');
    if (t == null) {
      throw Exception('Consumable type sconosciuto: ${map['type']}');
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

  const MachineDetailPage({super.key, required this.machineId});

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
            'machine_id, machine_code, site_name, client_name, effective_operator_id, type, capacity_units, current_units',
          )
          .eq('machine_id', widget.machineId);

      final list = (rows as List).cast<Map<String, dynamic>>();
      if (list.isEmpty) {
        throw Exception(
          'Macchina non trovata o nessun consumabile disponibile.',
        );
      }

      // Guardrail: l’utente deve essere l’assegnatario effettivo
      final effectiveOperatorId =
          list.first['effective_operator_id'] as String?;
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
    if (percent <= 10) return AppColors.stopped;
    if (percent <= 20) return AppColors.danger;
    if (percent <= 40) return AppColors.warning;
    return AppColors.success;
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
      await supabase.rpc(
        'perform_refill_consumable',
        params: {
          'p_machine_id': header.machineId,
          'p_type': consumableTypeToDb(type),
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Refill ${consumableLabel(type)} registrato.'),
          ),
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
      ConsumableType.hot,
      ConsumableType.cold,
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
      appBar: AppBar(title: Text(header?.machineCode ?? 'Macchina')),
      body: _loading
          ? const AppLoading()
          : _error != null
          ? AppErrorState(message: _error!, onRetry: _loadAll)
          : header == null
          ? const AppEmptyState(
              title: 'Macchina non trovata',
              icon: Icons.coffee_maker_outlined,
            )
          : RefreshIndicator(
              onRefresh: _loadAll,
              child: ListView(
                padding: context.responsive.pagePadding,
                children: [
                  _buildInfoCard(header),
                  const SizedBox(height: AppSpacing.md),
                  _buildCalibrationCard(header),
                  const SizedBox(height: AppSpacing.md),
                  _buildConsumablesGrid(),
                  const SizedBox(height: AppSpacing.md),
                  if (_refillError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: AppStatusPill(
                        label: _refillError!,
                        color: AppColors.danger,
                        icon: Icons.error_outline,
                      ),
                    ),
                  const SizedBox(height: AppSpacing.lg),
                ],
              ),
            ),
    );
  }

  Widget _buildInfoCard(MachineHeaderModel header) {
    return AppSectionCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Informazioni macchina',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.sm),
          _infoRow(
            'Cliente',
            (header.clientName ?? '').isEmpty ? '-' : header.clientName!,
          ),
          if ((header.siteName ?? '').isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xxs),
            _infoRow('Sede', header.siteName!),
          ],
          const SizedBox(height: AppSpacing.xxs),
          _infoRow('Codice macchina', header.machineCode),
        ],
      ),
    );
  }

  Widget _buildCalibrationCard(MachineHeaderModel header) {
    return AppSectionCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.petroleumSoft,
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: const Icon(Icons.tune, color: AppColors.petroleum),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Calibrazione',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  'BLE IC01',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          FilledButton.icon(
            onPressed: () =>
                context.push('/machines/${header.machineId}/calibration'),
            icon: const Icon(Icons.bluetooth_searching),
            label: const Text('Apri'),
          ),
        ],
      ),
    );
  }

  Widget _buildConsumablesGrid() {
    final types = _orderedTypes();

    final items = <ConsumableType>[];
    for (final t in types) {
      final cs = _consumables[t];
      if (cs == null) continue;
      if (!cs.isEnabled) continue;
      items.add(t);
    }

    if (items.isEmpty) {
      return const AppEmptyState(
        title: 'Nessun consumabile configurato',
        icon: Icons.inventory_2_outlined,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (items.length == 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Fattore monitorato (dosi)',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: AppSpacing.sm),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: _buildConsumableCard(_consumables[items.first]!),
                ),
              ),
            ],
          );
        }

        final responsive = AppResponsive(constraints.maxWidth);
        final crossAxisCount = responsive.columnsFor(
          minTileWidth: 300,
          maxColumns: 3,
        );
        final ratio = crossAxisCount == 1
            ? 0.92
            : crossAxisCount == 2
            ? 0.82
            : 0.9;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Fattore monitorato (dosi)',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.sm),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: AppSpacing.sm,
                mainAxisSpacing: AppSpacing.sm,
                childAspectRatio: ratio,
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
    final canRefill =
        cs.isEnabled && !cs.isConfigMissing && !cs.isFull && !isLoadingThis;

    return AppSectionCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final gaugeSize = (constraints.maxWidth * 0.58).clamp(180.0, 320.0);
          final strokeWidth = (gaugeSize * 0.075).clamp(12.0, 22.0);
          final percentFontSize = (gaugeSize * 0.18).clamp(32.0, 56.0);
          final labelFontSize = (gaugeSize * 0.09).clamp(16.0, 28.0);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    consumableIcon(cs.type),
                    size: 24,
                    color: AppColors.muted,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    consumableLabel(cs.type),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: gaugeSize,
                height: gaugeSize,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: gaugeSize,
                      height: gaugeSize,
                      child: CircularProgressIndicator(
                        value: percent / 100.0,
                        strokeWidth: strokeWidth,
                        strokeCap: StrokeCap.round,
                        backgroundColor: color.withValues(alpha: 0.12),
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${percent.toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontSize: percentFontSize,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: labelFontSize,
                            fontWeight: FontWeight.w800,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                cs.isConfigMissing
                    ? 'Capacità non impostata'
                    : '${cs.currentUnits} / ${cs.capacityUnits} dosi',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: cs.isConfigMissing
                      ? AppColors.danger
                      : AppColors.muted,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xl),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: canRefill ? () => _refillOne(cs.type) : null,
                    icon: isLoadingThis
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.refresh, size: 22),
                    label: Text(
                      cs.isFull
                          ? 'Pieno'
                          : cs.isConfigMissing
                          ? 'Configura'
                          : 'Refill',
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: context.responsive.isCompact ? 104 : 140,
          child: Text(
            '$label:',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.muted,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}
