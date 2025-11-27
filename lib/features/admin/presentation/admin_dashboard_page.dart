import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  late Future<bool> _isAdminFuture;

  @override
  void initState() {
    super.initState();
    _isAdminFuture = _checkIfAdmin();
  }

  Future<bool> _checkIfAdmin() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user == null) {
      return false;
    }

    final data = await supabase
        .from('profiles')
        .select('role')
        .eq('id', user.id)
        .maybeSingle();

    if (data == null) return false;
    return data['role'] == 'admin';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _isAdminFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          // loading
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final isAdmin = snapshot.data ?? false;

        if (!isAdmin) {
          // ⛔ Non admin → blocco accesso
          return Scaffold(
            appBar: AppBar(
              title: const Text('Area admin'),
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock, size: 72),
                    const SizedBox(height: 16),
                    const Text(
                      'Questa sezione è riservata agli admin.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      child: const Text('Torna indietro'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        // ✅ QUI SEI SICURAMENTE ADMIN
        return Scaffold(
          appBar: AppBar(
            title: const Text('Dashboard Admin'),
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              // layout responsive: 1 colonna su mobile, 2-3 su web
              int crossAxisCount = 1;
              if (constraints.maxWidth >= 1000) {
                crossAxisCount = 3;
              } else if (constraints.maxWidth >= 600) {
                crossAxisCount = 2;
              }

              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      kIsWeb
                          ? 'Overview flotta (web)'
                          : 'Overview flotta (app)',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),

                    // KPI cards
                    GridView.count(
                      crossAxisCount: crossAxisCount,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      children: const [
                        _AdminKpiCard(
                          label: 'Clienti totali',
                          value: '—',
                          subtitle: 'Da collegare ai dati',
                          icon: Icons.apartment,
                        ),
                        _AdminKpiCard(
                          label: 'Macchine totali',
                          value: '—',
                          subtitle: 'Da collegare ai dati',
                          icon: Icons.coffee,
                        ),
                        _AdminKpiCard(
                          label: 'Ticket aperti',
                          value: '—',
                          subtitle: 'status = open',
                          icon: Icons.report_problem,
                        ),
                        _AdminKpiCard(
                          label: 'Ticket in corso',
                          value: '—',
                          subtitle: 'status = in_progress',
                          icon: Icons.build,
                        ),
                        _AdminKpiCard(
                          label: 'Refill oggi',
                          value: '—',
                          subtitle: 'refills.created_at = today',
                          icon: Icons.local_cafe,
                        ),
                        _AdminKpiCard(
                          label: 'Visite oggi',
                          value: '—',
                          subtitle: 'visits.created_at = today',
                          icon: Icons.route,
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    Text(
                      'Attività recenti',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),

                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.coffee),
                        title: const Text('Ultimi refill'),
                        subtitle: const Text(
                          'Qui metteremo una lista dei refill più recenti (per admin).',
                        ),
                        onTap: () {
                          // TODO: navigare a pagina dettagli se vuoi
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.build),
                        title: const Text('Ultime manutenzioni'),
                        subtitle: const Text(
                          'Qui metteremo le visite di tipo "maintenance" / ticket.',
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _AdminKpiCard extends StatelessWidget {
  final String label;
  final String value;
  final String subtitle;
  final IconData icon;

  const _AdminKpiCard({
    required this.label,
    required this.value,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
