/// ===============================================================
/// FILE: app/main_shell.dart
///
/// Shell principale con bottom navigation:
/// - Mostra sempre il child (pagina corrente).
/// - Gestisce la bottom nav con 3 sezioni:
///     0 = Oggi/Domani (dashboard)
///     1 = Tutti i clienti
///     2 = Manutenzioni straordinarie
/// - Legge il ruolo dell'utente da Supabase (profiles.role).
/// - Se role == 'technician':
///     - disabilita (grigie) le icone Oggi/Domani e Tutti.
///     - permette solo la sezione Manutenzioni.
///
/// COSA TIPICAMENTE SI MODIFICA:
/// - Aggiungere nuove icone di navigazione.
/// - Cambiare la politica di abilitazione/disabilitazione per ruolo.
///
/// COSA È MEGLIO NON TOCCARE:
/// - La logica di mapping index -> path (/dashboard, /clients, /maintenance).
/// - Il caricamento del ruolo, per non rompere UX tecnici/operatori.
/// ===============================================================
library;

// lib/app/main_shell.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MainShell extends StatefulWidget {
  final Widget child;
  final int currentIndex;

  const MainShell({
    super.key,
    required this.child,
    required this.currentIndex,
  });

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  String? _role;
  bool _loadingRole = true;

  @override
  void initState() {
    super.initState();
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
          .limit(1);

      String? role;
      if (data.isNotEmpty) {
        final row = data.first;
        role = row['role'] as String?;
      }

      setState(() {
        _role = role;
        _loadingRole = false;
      });
    } catch (_) {
      setState(() {
        _role = null;
        _loadingRole = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTechnician = _role == 'technician';
    final isAdmin = _role == 'admin';
    final disabledColor = Theme.of(context).disabledColor;

    return Scaffold(
      body: widget.child,
      bottomNavigationBar: 
      isAdmin? null
      :NavigationBar(
        selectedIndex: widget.currentIndex,
        onDestinationSelected: (index) {
          if (_loadingRole) return;

          // Tecnico: può usare solo Manutenzioni (index 2)
          if (isTechnician && index != 2) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content:
                    Text('Questa sezione non è disponibile per il tuo profilo.'),
                duration: Duration(seconds: 2),
              ),
            );
            return;
          }

          if (index == 0) {
            context.go('/dashboard');
          } else if (index == 1) {
            context.go('/clients');
          } else if (index == 2) {
            context.go('/maintenance');
          }
        },
        destinations: [
          NavigationDestination(
            icon: Icon(
              Icons.today_outlined,
              color: isTechnician ? disabledColor : null,
            ),
            selectedIcon: Icon(
              Icons.today,
              color: isTechnician ? disabledColor : null,
            ),
            label: 'Oggi/Domani',
          ),
          NavigationDestination(
            icon: Icon(
              Icons.list_alt_outlined,
              color: isTechnician ? disabledColor : null,
            ),
            selectedIcon: Icon(
              Icons.list_alt,
              color: isTechnician ? disabledColor : null,
            ),
            label: 'Tutti',
          ),
          const NavigationDestination(
            icon: Icon(Icons.build_outlined),
            selectedIcon: Icon(Icons.build),
            label: 'Manutenzioni',
          ),
        ],
      ),
    );
  }
}
