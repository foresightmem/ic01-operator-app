import 'package:flutter/material.dart';

import 'package:ic01_operator_app/models/admin_event.dart';

class AdminActivitiesPage extends StatelessWidget {
  final List<AdminEvent> events;

  const AdminActivitiesPage({
    super.key,
    required this.events,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attività recenti'),
      ),
      body: events.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Nessuna attività recente.'),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: events.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final e = events[index];
                return ListTile(
                  leading: CircleAvatar(
                    radius: 18,
                    backgroundColor:
                        Theme.of(context).colorScheme.primary.withAlpha(20),
                    child: Icon(
                      e.icon,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  title: Text(e.title, style: const TextStyle(fontSize: 14)),
                  subtitle:
                      Text(e.subtitle, style: const TextStyle(fontSize: 12)),
                  trailing: Text(
                    _timeAgo(e.timestamp),
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                );
              },
            ),
    );
  }

  static String _timeAgo(DateTime time) {
    final diff = DateTime.now().toUtc().difference(time.toUtc());
    if (diff.inMinutes < 1) return 'Ora';
    if (diff.inHours < 1) return '${diff.inMinutes} min fa';
    if (diff.inHours < 24) return '${diff.inHours} h fa';
    if (diff.inDays < 7) return '${diff.inDays} g fa';
    final weeks = (diff.inDays / 7).floor();
    if (weeks < 4) return '$weeks sett fa';
    final months = (diff.inDays / 30).floor();
    return '$months mesi fa';
  }
}
