// lib/features/machines/presentation/machine_detail_page.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// ===============================================================
/// MachineDetailPage
///
/// Dettaglio di una macchina (distributore):
/// - Riceve machineId dalla route.
/// - Carica i dati dalla view `machine_effective_assignment`
///   (rispetta assegnazioni temporanee).
/// - Mostra:
///     - percentuale autonomia (current_fill_percent)
///     - stato colore (green/yellow/red/black) calcolato da fill (fallback)
///     - info cliente/sede/codice macchina
///     - erogazioni anno (yearly_shots)
/// - Bottone "Refill fatto":
///     - chiama RPC `perform_refill(p_machine_id)`
///       che inserisce una riga in `refills` e aggiorna `machines`
///       in modo atomico (security definer).
///     - ricarica i dati (auto refresh).
/// ===============================================================

class MachineStateModel {
  final String machineId;
  final String code;
  final String clientName;
  final String? siteName;
  final double currentFillPercent;
  final String state;
  final int? yearlyShots;

  MachineStateModel({
    required this.machineId,
    required this.code,
    required this.clientName,
    required this.siteName,
    required this.currentFillPercent,
    required this.state,
    required this.yearlyShots,
  });

  static String _stateFromFill(double fill) {
    if (fill <= 10) return 'black';
    if (fill <= 20) return 'red';
    if (fill <= 40) return 'yellow';
    return 'green';
  }

  factory MachineStateModel.fromEffectiveMap(Map<String, dynamic> map) {
    final fill = (map['current_fill_percent'] as num?)?.toDouble() ?? 0.0;
    final state = (map['state'] as String?) ?? _stateFromFill(fill);

    return MachineStateModel(
      machineId: (map['machine_id'] as String?) ?? (map['id'] as String),
      code: (map['machine_code'] as String?) ?? (map['code'] as String?) ?? 'N/D',
      clientName: (map['client_name'] as String?) ?? '',
      siteName: map['site_name'] as String?,
      currentFillPercent: fill,
      state: state,
      yearlyShots: map['yearly_shots'] as int?,
    );
  }

  MachineStateModel copyWith({
    String? clientName,
    String? siteName,
    double? currentFillPercent,
    String? state,
    int? yearlyShots,
  }) {
    return MachineStateModel(
      machineId: machineId,
      code: code,
      clientName: clientName ?? this.clientName,
      siteName: siteName ?? this.siteName,
      currentFillPercent: currentFillPercent ?? this.currentFillPercent,
      state: state ?? this.state,
      yearlyShots: yearlyShots ?? this.yearlyShots,
    );
  }
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
  MachineStateModel? _machine;
  bool _loading = true;
  bool _refillLoading = false;
  String? _error;
  String? _refillError;

  @override
  void initState() {
    super.initState();
    _loadMachine();
  }

  Future<void> _loadMachine() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (user == null) {
        setState(() {
          _error = 'Utente non autenticato.';
          _loading = false;
        });
        return;
      }

      // Carica da view "effective" (rispetta assegnazioni temporanee)
      final data = await supabase
          .from('machine_effective_assignment')
          .select(
            'machine_id, machine_code, current_fill_percent, yearly_shots, site_name, client_name, effective_operator_id',
          )
          .eq('machine_id', widget.machineId)
          .maybeSingle();

      if (data == null) {
        setState(() {
          _error = 'Macchina non trovata.';
          _loading = false;
        });
        return;
      }

      // Guardrail applicativo: l’operatore deve essere assegnatario effettivo
      final effectiveOperatorId = data['effective_operator_id'] as String?;
      if (effectiveOperatorId != null && effectiveOperatorId != user.id) {
        setState(() {
          _error = 'Non sei assegnato a questa macchina.';
          _loading = false;
        });
        return;
      }

      final base = MachineStateModel.fromEffectiveMap({
        ...data,
        'client_name': data['client_name'],
        'site_name': data['site_name'],
      });

      setState(() {
        _machine = base.copyWith(
          clientName: (data['client_name'] as String?) ?? base.clientName,
          siteName: (data['site_name'] as String?) ?? base.siteName,
          currentFillPercent:
              (data['current_fill_percent'] as num?)?.toDouble() ?? base.currentFillPercent,
          yearlyShots: data['yearly_shots'] as int?,
        );
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Errore nel caricamento: $e';
        _loading = false;
      });
    }
  }

  Color _stateColor(String state) {
    switch (state) {
      case 'green':
        return Colors.green;
      case 'yellow':
        return Colors.orange;
      case 'red':
        return Colors.red;
      case 'black':
        return Colors.black;
      default:
        return Colors.grey;
    }
  }

  String _stateLabel(String state) {
    switch (state) {
      case 'green':
        return 'OK';
      case 'yellow':
        return 'Attenzione';
      case 'red':
        return 'Critico';
      case 'black':
        return 'Fermo';
      default:
        return 'Sconosciuto';
    }
  }

  Future<void> _onRefillPressed() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    final machine = _machine;

    if (user == null || machine == null) return;

    setState(() {
      _refillLoading = true;
      _refillError = null;
    });

    try {
      // Esegue refill in modo atomico lato DB (insert refills + update machines)
      await supabase.rpc('perform_refill', params: {
        'p_machine_id': machine.machineId,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Refill registrato.')),
        );
      }

      await _loadMachine();
    } catch (e) {
      setState(() {
        _refillError = 'Errore durante il refill: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _refillLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final machine = _machine;

    return Scaffold(
      appBar: AppBar(
        title: Text(machine?.code ?? 'Macchina'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : machine == null
                  ? const Center(child: Text('Macchina non trovata.'))
                  : RefreshIndicator(
                      onRefresh: _loadMachine,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          _buildStateCard(machine),
                          const SizedBox(height: 16),
                          _buildInfoCard(machine),
                          const SizedBox(height: 24),
                          if (_refillError != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: Text(
                                _refillError!,
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          _buildRefillButton(),
                        ],
                      ),
                    ),
    );
  }

  Widget _buildStateCard(MachineStateModel machine) {
    final percent = machine.currentFillPercent.clamp(0, 100);
    final color = _stateColor(machine.state);
    final label = _stateLabel(machine.state);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text(
              'Stato macchina',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: SizedBox(
                width: 120,
                height: 120,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 120,
                      height: 120,
                      child: CircularProgressIndicator(
                        value: percent / 100.0,
                        strokeWidth: 10,
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
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (machine.yearlyShots != null)
              Text(
                'Erogazioni anno: ${machine.yearlyShots}',
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.grey,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(MachineStateModel machine) {
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
            _infoRow('Cliente', machine.clientName.isEmpty ? '-' : machine.clientName),
            if (machine.siteName != null) ...[
              const SizedBox(height: 4),
              _infoRow('Sede', machine.siteName!),
            ],
            const SizedBox(height: 4),
            _infoRow('Codice macchina', machine.code),
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

  Widget _buildRefillButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _refillLoading ? null : _onRefillPressed,
        icon: _refillLoading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.refresh),
        label: Text(_refillLoading ? 'Refill in corso...' : 'Refill fatto'),
      ),
    );
  }
}
