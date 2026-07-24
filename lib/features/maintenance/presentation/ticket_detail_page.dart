/// ===============================================================
/// FILE: features/maintenance/presentation/ticket_detail_page.dart
///
/// Dettaglio singolo ticket di manutenzione:
/// - Route: /maintenance/:ticketId
/// - Carica i dati del ticket dalla view ticket_list (eq ticket_id).
/// - Mostra:
///     - stato (open/assigned/in_progress/closed)
///     - cliente, sede, macchina
///     - descrizione
///     - date principali (created_at, ecc.)
/// - Azioni sul ticket:
///     - open       -> "Prendi in carico"    -> status = assigned
///     - assigned   -> "Avvia intervento"    -> status = in_progress
///     - in_progress-> "Chiudi ticket"       -> status = closed
///
/// COSA TIPICAMENTE SI MODIFICA:
/// - Workflow degli stati (aggiungere 'on_hold', 'canceled', ecc.).
/// - Dettagli mostrati (es. note interne, tempo intervento).
/// - Testi dei bottoni.
///
/// COSA È MEGLIO NON TOCCARE:
/// - La logica che inserisce la visita su chiusura ticket.
/// - L'uso di ticket_id dalla route (pathParameters).
/// ===============================================================
library;

// lib/features/maintenance/presentation/ticket_detail_page.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../public_support/presentation/public_support_page.dart';

class TicketDetailPage extends StatefulWidget {
  final String ticketId;
  const TicketDetailPage({super.key, required this.ticketId});

  @override
  State<TicketDetailPage> createState() => _TicketDetailPageState();
}

class _TicketDetailPageState extends State<TicketDetailPage> {
  Map<String, dynamic>? _ticket;
  bool _loading = true;
  bool _actionLoading = false;

  // Ruolo utente per sola-lettura admin
  String? _role;
  bool _loadingRole = true;

  @override
  void initState() {
    super.initState();
    _loadTicket();
    _loadRole();
  }

  Future<void> _loadRole() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user == null) {
      setState(() {
        _role = null;
        _loadingRole = false;
      });
      return;
    }

    try {
      final data = await supabase
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();

      setState(() {
        _role = data?['role'] as String?;
        _loadingRole = false;
      });
    } catch (_) {
      setState(() {
        _role = null;
        _loadingRole = false;
      });
    }
  }

  Future<void> _loadTicket() async {
    final supabase = Supabase.instance.client;

    try {
      final data = await supabase
          .from('ticket_list')
          .select()
          .eq('ticket_id', widget.ticketId)
          .maybeSingle();

      setState(() {
        _ticket = data;
        _loading = false;
      });
    } catch (e) {
      // ignore: avoid_print
      print("Errore load ticket: $e");
      setState(() => _loading = false);
    }
  }

  Future<void> _updateStatus(String newStatus) async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user == null) return;

    setState(() => _actionLoading = true);

    try {
      final updated = await supabase
          .from('tickets')
          .update({
            'status': newStatus,
            if (newStatus == 'in_progress') 'assigned_technician_id': user.id,
            if (newStatus == 'assigned') 'assigned_technician_id': user.id,
            if (newStatus == 'in_progress')
              'assigned_at': DateTime.now().toIso8601String(),
            if (newStatus == 'resolved')
              'resolved_at': DateTime.now().toIso8601String(),
            if (newStatus == 'resolved')
              'closed_at': DateTime.now().toIso8601String(),
          })
          .eq('id', widget.ticketId)
          .select('id')
          .maybeSingle();

      if (updated == null) {
        throw Exception(
          'Ticket non aggiornato: permessi insufficienti o ticket non più disponibile.',
        );
      }

      // Se risolto -> crea una visita
      if (newStatus == 'resolved') {
        await supabase.from('visits').insert({
          'operator_id': user.id,
          'client_id': _ticket!['client_id'],
          'site_id': _ticket!['site_id'],
          'ticket_id': widget.ticketId,
          'visit_type': 'maintenance',
          'notes': 'Ticket chiuso tramite app',
        });
      }

      await _loadTicket();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore aggiornamento ticket: $e')),
      );
    } finally {
      if (mounted) setState(() => _actionLoading = false);
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
      case 'resolved':
      case 'closed':
        return Colors.green;
      case 'cancelled':
        return Colors.grey;
      default:
        return Colors.grey;
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
      case 'resolved':
      case 'closed':
        return 'Risolto';
      case 'cancelled':
        return 'Annullato';
      default:
        return status;
    }
  }

  String _formatDurationSeconds(dynamic seconds) {
    final value = (seconds as num?)?.toInt();
    if (value == null || value < 0) return '-';
    final minutes = value ~/ 60;
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final restMinutes = minutes % 60;
    if (hours < 24) return '$hours h $restMinutes min';
    final days = hours ~/ 24;
    final restHours = hours % 24;
    return '$days g $restHours h';
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final bool isAdmin = _role == 'admin';

    return Scaffold(
      appBar: AppBar(
        // Admin: back esplicito verso la lista manutenzioni
        leading: isAdmin
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.go('/maintenance'),
              )
            : null,
        title: const Text('Dettaglio ticket'),
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
      body: (_loading || _loadingRole)
          ? const Center(child: CircularProgressIndicator())
          : _ticket == null
          ? const Center(child: Text('Ticket non trovato'))
          : _buildDetail(),
    );
  }

  Widget _buildDetail() {
    final t = _ticket!;
    final statusColor = _statusColor(t['status']);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // STATO
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Stato:',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                _statusLabel(t['status']),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: statusColor,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // INFO CLIENTE
        Text('Cliente: ${t['client_name']}'),
        if (t['site_name'] != null) Text('Sede: ${t['site_name']}'),
        Text('Macchina: ${t['machine_code']}'),
        if (t['reason'] != null)
          Text('Motivo: ${publicTicketReasonLabel(t['reason'] as String)}'),
        const SizedBox(height: 12),

        // DESCRIZIONE
        if (t['description'] != null &&
            (t['description'] as String).trim().isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Descrizione:',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(t['description'], style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 12),
            ],
          ),

        // DATA
        Text(
          'Aperto il: ${DateTime.parse(t['created_at']).toLocal()}'
              .split('.')
              .first,
          style: const TextStyle(color: Colors.grey),
        ),
        if (t['resolved_at'] != null)
          Text(
            'Risolto il: ${DateTime.parse(t['resolved_at']).toLocal()}'
                .split('.')
                .first,
            style: const TextStyle(color: Colors.grey),
          ),
        Text(
          'Tempo risoluzione: ${_formatDurationSeconds(t['resolution_time_seconds'])}',
          style: const TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 30),

        // AZIONI
        _actionLoading
            ? const Center(child: CircularProgressIndicator())
            : _buildActions(t),
      ],
    );
  }

  Widget _buildActions(Map<String, dynamic> t) {
    final status = t['status'];
    final assignedTech = t['assigned_technician_id'];
    final currentUser = Supabase.instance.client.auth.currentUser;

    final bool assignedToMe = assignedTech == currentUser?.id;
    final bool isAdmin = _role == 'admin';

    if (isAdmin) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton(
            onPressed: status == 'open' ? null : () => _updateStatus('open'),
            child: const Text('Riapri'),
          ),
          OutlinedButton(
            onPressed: status == 'in_progress'
                ? null
                : () => _updateStatus('in_progress'),
            child: const Text('In corso'),
          ),
          ElevatedButton(
            onPressed: status == 'resolved' || status == 'closed'
                ? null
                : () => _updateStatus('resolved'),
            child: const Text('Risolvi'),
          ),
          OutlinedButton(
            onPressed: status == 'cancelled'
                ? null
                : () => _updateStatus('cancelled'),
            child: const Text('Annulla'),
          ),
        ],
      );
    }

    // 👷 Tecnico: logica originale
    if (status == 'resolved' || status == 'closed') {
      return const Text(
        'Ticket risolto',
        style: TextStyle(fontSize: 16, color: Colors.green),
      );
    }

    if (status == 'cancelled') {
      return const Text(
        'Ticket annullato',
        style: TextStyle(fontSize: 16, color: Colors.grey),
      );
    }

    if (status == 'open') {
      return ElevatedButton(
        onPressed: () => _updateStatus('assigned'),
        child: const Text('Prendi in carico'),
      );
    }

    if (status == 'assigned' && assignedToMe) {
      return ElevatedButton(
        onPressed: () => _updateStatus('in_progress'),
        child: const Text('Avvia intervento'),
      );
    }

    if (status == 'in_progress' && assignedToMe) {
      return ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
        onPressed: () => _updateStatus('resolved'),
        child: const Text('Risolvi ticket'),
      );
    }

    return const Text(
      'Assegnato ad altro tecnico',
      style: TextStyle(color: Colors.orange),
    );
  }
}
