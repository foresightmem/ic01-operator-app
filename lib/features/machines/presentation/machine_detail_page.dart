/// ===============================================================
/// FILE: features/machines/presentation/machine_detail_page.dart
///
/// Dettaglio di una macchina (distributore):
/// - Riceve machineId dalla route.
/// - Carica i dati dalla view machine_states o dalla tabella machines.
/// - Mostra:
///     - stato percentuale (current_fill_percent).
///     - stato colore (green/yellow/red/black).
///     - info cliente/sede.
/// - Contiene il bottone "Refill fatto":
///     - crea una riga nella tabella refills.
///     - resetta current_fill_percent a 100%.
///     - aggiorna la UI (auto refresh).
///
/// COSA TIPICAMENTE SI MODIFICA:
/// - Layout delle informazioni della macchina.
/// - Logica di "Refill fatto" (es. chiedere conferma, undo).
///
/// COSA È MEGLIO NON TOCCARE:
/// - La chiamata Supabase che crea il refill + update della macchina.
/// - Il mapping dei campi macchina (percentuale, id, ecc.).
/// ===============================================================
library;

// lib/features/machines/presentation/machine_detail_page.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MachineDetail {
  final String id;
  final String code;
  final double currentFillPercent;
  final String state;
  final int yearlyShots;

  MachineDetail({
    required this.id,
    required this.code,
    required this.currentFillPercent,
    required this.state,
    required this.yearlyShots,
  });

  factory MachineDetail.fromMap(Map<String, dynamic> map) {
    return MachineDetail(
      id: map['machine_id'] as String,
      code: map['code'] as String,
      currentFillPercent:
          (map['current_fill_percent'] as num).toDouble(),
      state: map['state'] as String,
      yearlyShots: (map['yearly_shots'] as int?) ?? 0,
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
  MachineDetail? _machine;
  bool _loading = true;
  bool _refilling = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMachine();
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

  Future<void> _loadMachine() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final supabase = Supabase.instance.client;

      // Leggiamo dalla view machine_states per avere stato + percentuale + shots.
      final data = await supabase
          .from('machine_states')
          .select()
          .eq('machine_id', widget.machineId)
          .maybeSingle();

      if (data == null) {
        setState(() {
          _error = 'Macchina non trovata';
        });
        return;
      }

      setState(() {
        _machine =
            MachineDetail.fromMap(data);
      });
    } catch (e) {
      setState(() {
        _error = 'Errore nel caricamento: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _performRefill() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user == null) {
      setState(() {
        _error = 'Utente non autenticato. Effettua di nuovo il login.';
      });
      return;
    }

    setState(() {
      _refilling = true;
      _error = null;
    });

    try {
      // Recupero la percentuale attuale per salvarla come previous_fill_percent
      final machineRow = await supabase
          .from('machines')
          .select('current_fill_percent')
          .eq('id', widget.machineId)
          .single();

      final prev =
          (machineRow['current_fill_percent'] as num?)?.toDouble() ??
              0.0;

      // Inserisco un refill: il trigger aggiornerà machines.current_fill_percent a 100.
      await supabase.from('refills').insert({
        'machine_id': widget.machineId,
        'operator_id': user.id,
        'previous_fill_percent': prev,
        'new_fill_percent': 100,
      });

      // Rileggo lo stato macchina aggiornato dalla view machine_states
      await _loadMachine();
    } catch (e) {
      setState(() {
        _error = 'Errore durante il refill: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _refilling = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final machine = _machine;

    return Scaffold(
      appBar: AppBar(
        title: Text(machine?.code ?? 'Dettaglio macchina'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : machine == null
              ? Center(
                  child: Text(_error ?? 'Macchina non trovata'),
                )
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Stato macchina',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge,
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: Column(
                          children: [
                            CircleAvatar(
                              radius: 40,
                              backgroundColor:
                                  _stateColor(machine.state),
                              child: Text(
                                '${machine.currentFillPercent.toStringAsFixed(0)}%',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _stateLabel(machine.state),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Erogazioni anno: ${machine.yearlyShots}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      if (_error != null)
                        Padding(
                          padding:
                              const EdgeInsets.only(bottom: 12),
                          child: Text(
                            _error!,
                            style: const TextStyle(
                              color: Colors.red,
                            ),
                          ),
                        ),
                      ElevatedButton.icon(
                        onPressed: _refilling ? null : _performRefill,
                        icon: _refilling
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.refresh),
                        label: const Text('Refill fatto'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            vertical: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
