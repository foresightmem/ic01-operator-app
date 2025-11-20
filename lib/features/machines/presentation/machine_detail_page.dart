// lib/features/machines/presentation/machine_detail_page.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// ===============================================================
/// MachineDetailPage
///
/// Dettaglio di una macchina (distributore):
/// - Riceve machineId dalla route.
/// - Carica i dati dalla view `machine_states`.
/// - In più carica:
///     - nome sede da `sites`
///     - nome cliente da `clients`
/// - Mostra:
///     - percentuale autonomia (current_fill_percent)
///     - stato colore (green/yellow/red/black)
///     - info cliente/sede/codice macchina
///     - erogazioni anno (yearly_shots)
/// - Bottone "Refill fatto":
///     - crea una riga in `refills`
///     - resetta `current_fill_percent` a 100% su `machines`
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

  /// Crea un modello solo con i dati di base dalla view `machine_states`.
  /// Il nome cliente e quello della sede potranno essere arricchiti dopo,
  /// a partire da site_id.
  factory MachineStateModel.fromMap(Map<String, dynamic> map) {
    return MachineStateModel(
      machineId: map['machine_id'] as String? ??
          map['id'] as String, // fallback se la view usa 'id'
      code: map['code'] as String? ?? map['machine_code'] as String,
      clientName:
          (map['client_name'] as String?) ?? '', // spesso non presente nella view
      siteName: map['site_name'] as String?, // potrebbe non esserci
      currentFillPercent: (map['current_fill_percent'] as num).toDouble(),
      state: map['state'] as String? ?? 'unknown',
      yearlyShots: map['yearly_shots'] as int?,
    );
  }

  MachineStateModel copyWith({
    String? clientName,
    String? siteName,
  }) {
    return MachineStateModel(
      machineId: machineId,
      code: code,
      clientName: clientName ?? this.clientName,
      siteName: siteName ?? this.siteName,
      currentFillPercent: currentFillPercent,
      state: state,
      yearlyShots: yearlyShots,
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

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // 1) Leggiamo la macchina dalla view machine_states
      final data = await supabase
          .from('machine_states')
          .select()
          .eq('machine_id', widget.machineId)
          .maybeSingle();

      if (data == null) {
        setState(() {
          _error = 'Macchina non trovata.';
          _loading = false;
        });
        return;
      }

      final baseMachine = MachineStateModel.fromMap(data);
      String? siteName = baseMachine.siteName;
      String clientName = baseMachine.clientName;

      // 2) Recuperiamo site_id dalla view (se presente)
      final siteId = data['site_id'] as String?;
      if (siteId != null) {
        // 2a) Leggiamo la sede
        final site = await supabase
            .from('sites')
            .select('name, client_id')
            .eq('id', siteId)
            .maybeSingle();

        if (site != null) {
          siteName = site['name'] as String?;
          final clientId = site['client_id'] as String?;

          // 2b) Da client_id recuperiamo il nome cliente
          if (clientId != null) {
            final client = await supabase
                .from('clients')
                .select('name')
                .eq('id', clientId)
                .maybeSingle();

            if (client != null) {
              clientName = client['name'] as String;
            }
          }
        }
      }

      setState(() {
        _machine = baseMachine.copyWith(
          clientName: clientName,
          siteName: siteName,
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
      // 1) Inserisci nella tabella refills
      await supabase.from('refills').insert({
        'machine_id': machine.machineId,
        'operator_id': user.id,
        'previous_fill_percent': machine.currentFillPercent,
        'new_fill_percent': 100,
      });

      // 2) Aggiorna la macchina a 100%
      await supabase
          .from('machines')
          .update({'current_fill_percent': 100})
          .eq('id', machine.machineId);

      // 3) Ricarica lo stato macchina
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
            // cerchio grande con percentuale
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
