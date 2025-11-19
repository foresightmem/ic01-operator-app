/// ===============================================================
/// FILE: features/maintenance/presentation/maintenance_tickets_page.dart
///
/// Lista chiamate di manutenzione straordinaria:
/// - Legge dalla view ticket_list:
///     - ticket_id, status, description, created_at
///     - client_name, site_name, machine_code
/// - Mostra tutti i ticket con stato 'open' o 'assigned'.
/// - Azioni rapide:
///     - "Prendo in carico" -> assegna il ticket all'utente corrente.
/// - Tap sulla card -> apre TicketDetailPage (/maintenance/:ticketId).
/// - AppBar mostra email utente + icona logout.
///
/// COSA TIPICAMENTE SI MODIFICA:
/// - Filtri sui ticket (aggiungere 'in_progress', filtrare per tecnico, ecc.).
/// - Layout delle card, testi, colori.
/// - Logica di assegnazione (es. evitare double-assign).
///
/// COSA È MEGLIO NON TOCCARE:
/// - La query base su ticket_list (nome dei campi ticket_id, client_name...).
/// - La costruzione di TicketItem.fromMap (deve restare allineata alla view).
/// ===============================================================
library;

// lib/features/maintenance/presentation/maintenance_tickets_page.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Modello per rappresentare un ticket nella lista
class TicketItem {
  final String ticketId;
  final String status;
  final String? description;
  final DateTime createdAt;
  final String clientName;
  final String? siteName;
  final String machineCode;
  final String? assignedTechnicianId;

  TicketItem({
    required this.ticketId,
    required this.status,
    required this.description,
    required this.createdAt,
    required this.clientName,
    required this.siteName,
    required this.machineCode,
    required this.assignedTechnicianId,
  });

  factory TicketItem.fromMap(Map<String, dynamic> map) {
    return TicketItem(
      ticketId: map['ticket_id'] as String,
      status: map['status'] as String,
      description: map['description'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      clientName: map['client_name'] as String,
      siteName: map['site_name'] as String?,
      machineCode: map['machine_code'] as String,
      assignedTechnicianId: map['assigned_technician_id'] as String?,
    );
  }
}

/// Pagina per visualizzare e assegnare i ticket di manutenzione
class MaintenanceTicketsPage extends StatefulWidget {
  const MaintenanceTicketsPage({super.key});

  @override
  State<MaintenanceTicketsPage> createState() =>
      _MaintenanceTicketsPageState();
}

class _MaintenanceTicketsPageState extends State<MaintenanceTicketsPage> {
  late Future<List<TicketItem>> _futureTickets;
  bool _loadingAction = false;

  @override
  void initState() {
    super.initState();
    _futureTickets = _loadTickets();
  }

  Future<List<TicketItem>> _loadTickets() async {
    final supabase = Supabase.instance.client;

    final data = await supabase
        .from('ticket_list')
        .select()
        .inFilter('status', ['open', 'assigned'])
        .order('created_at', ascending: true);

    return (data as List<dynamic>)
        .map((row) => TicketItem.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  Future<void> _refresh() async {
    setState(() {
      _futureTickets = _loadTickets();
    });
  }

  Future<void> _assignTicket(TicketItem ticket) async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) return;

    setState(() => _loadingAction = true);

    try {
      await supabase.from('tickets').update({
        'assigned_technician_id': user.id,
        'status': 'assigned',
        'assigned_at': DateTime.now().toIso8601String(),
      }).eq('id', ticket.ticketId);

      await _refresh();
    } catch (e) {
      // ignore: avoid_print
      print('Errore assegnazione ticket: $e');
    } finally {
      if (mounted) setState(() => _loadingAction = false);
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'open':
        return 'Aperto';
      case 'assigned':
        return 'Assegnato';
      case 'in_progress':
        return 'In corso';
      case 'closed':
        return 'Chiuso';
      default:
        return status;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'open':
        return Colors.red;
      case 'assigned':
        return Colors.orange;
      case 'in_progress':
        return Colors.blue;
      case 'closed':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manutenzioni straordinarie'),
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
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<TicketItem>>(
          future: _futureTickets,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(
                child: Text('Errore nel caricamento: ${snapshot.error}'),
              );
            }

            final tickets = snapshot.data ?? [];

            if (tickets.isEmpty) {
              return const Center(
                child: Text('Nessuna chiamata di manutenzione aperta.'),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: tickets.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final t = tickets[index];
                final userId = user?.id;
                final isAssignedToMe = t.assignedTechnicianId == userId;
                final isUnassigned = t.assignedTechnicianId == null;
                final statusColor = _statusColor(t.status);

                return GestureDetector(
                  onTap: () {
                    context.push('/maintenance/${t.ticketId}');
                  },
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // CLIENTE + STATO
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  t.clientName,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 4, horizontal: 8),
                                decoration: BoxDecoration(
                                  color:
                                      statusColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  _statusLabel(t.status),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: statusColor,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 4),

                          // SEDE + MACCHINA
                          Text(
                            [
                              if (t.siteName != null) t.siteName!,
                              'Macchina: ${t.machineCode}',
                            ].join(' • '),
                            style: const TextStyle(fontSize: 13),
                          ),

                          const SizedBox(height: 8),

                          // DESCRIZIONE
                          if (t.description != null &&
                              t.description!.trim().isNotEmpty)
                            Text(
                              t.description!,
                              style: const TextStyle(fontSize: 13),
                            ),

                          const SizedBox(height: 10),

                          // FOOTER
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Aperto il ${t.createdAt.toLocal().toString().split(".").first}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                              ),
                              _buildActionsForTicket(
                                t,
                                isAssignedToMe: isAssignedToMe,
                                isUnassigned: isUnassigned,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildActionsForTicket(
    TicketItem ticket, {
    required bool isAssignedToMe,
    required bool isUnassigned,
  }) {
    if (_loadingAction) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    if (isAssignedToMe) {
      return const Text(
        'Assegnato a te',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.green,
        ),
      );
    }

    if (isUnassigned) {
      return TextButton(
        onPressed: () => _assignTicket(ticket),
        child: const Text('Prendo in carico'),
      );
    }

    return const Text(
      'Assegnato ad altro tecnico',
      style: TextStyle(
        fontSize: 12,
        color: Colors.orange,
      ),
    );
  }
}
