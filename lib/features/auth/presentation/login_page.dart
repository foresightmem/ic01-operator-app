// lib/features/auth/presentation/login_page.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';

/// Schermata di login per gli operatori.
///
/// Permette l'accesso tramite email e password usando Supabase Auth.

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  /// Controller per il campo email.
  final _emailCtrl = TextEditingController();

  /// Controller per il campo password.
  final _passwordCtrl = TextEditingController();

  /// Indica se è in corso una chiamata di login.
  bool _loading = false;
  String? _error;

  /// Effettua il login tramite Supabase usando email e password inserite.
  ///
  /// In caso di successo:
  /// - naviga verso la dashboard.
  ///
  /// In caso di errore:
  /// - mostra uno [SnackBar] con il messaggio di errore.

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final authResponse = await Supabase.instance.client.auth.signInWithPassword(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text.trim(),
      );

      // Se non c'è sessione, consideriamo il login fallito
      if (authResponse.session == null) {
        setState(() {
          _error = 'Login fallito: nessuna sessione ricevuta.';
        });
      } else {
        // Login OK -> vai in dashboard
        if (mounted) {
          context.go('/dashboard');
        }
      }
    } catch (e) {
      setState(() {
        _error = 'Login fallito: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

// override spiegati in basso!

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = _loading;

    return Scaffold(
      appBar: AppBar(title: const Text('Login IC-01')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _emailCtrl,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordCtrl,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
            const SizedBox(height: 24),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ElevatedButton(
              onPressed: isLoading ? null : _login,
              child: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Entra'),
            ),
          ],
        ),
      ),
    );
  }
}
/*
───────────────────────────────────────────────────────────────────────────────
SPIEGAZIONE DEGLI @override IN QUESTO FILE
───────────────────────────────────────────────────────────────────────────────

In login_page.dart ci sono tre override principali. Servono a riscrivere metodi
che Flutter mette a disposizione nelle classi StatefulWidget e State.

1. @override createState()
   ---------------------------------------------------------------------------
   Si trova dentro la classe LoginPage (che estende StatefulWidget).
   Questo metodo deve restituire un'istanza della classe di stato associata
   (_LoginPageState). Quando Flutter crea il widget, questo metodo dice al
   framework quale oggetto State deve essere usato per gestire logica e UI.

   In breve: collega il widget alla sua logica/stato.

2. @override dispose()
   ---------------------------------------------------------------------------
   Si trova dentro _LoginPageState.
   Questo metodo viene chiamato automaticamente da Flutter quando il widget
   viene rimosso dallo schermo in modo definitivo.

   In questo file viene usato per:
   - chiudere i controller dei campi di testo (email e password)
   - evitare memory leak
   - poi chiamare super.dispose() per completare la pulizia interna del framework

   In breve: serve a liberare risorse quando il widget non esiste più.

3. @override build()
   ---------------------------------------------------------------------------
   Si trova dentro _LoginPageState.
   È il metodo più importante: Flutter lo chiama ogni volta che deve
   disegnare l'interfaccia grafica del widget.

   Qui viene costruita tutta la UI: campi email/password, bottone, loader ecc.

   In breve: descrive come deve apparire la schermata di login.

───────────────────────────────────────────────────────────────────────────────
Riassunto
- createState() → collega il widget al suo oggetto State
- dispose() → pulisce risorse alla fine
- build() → costruisce la UI del widget

Gli override servono per sostituire i metodi base del ciclo di vita dei widget
con versioni personalizzate specifiche per questa pagina.
───────────────────────────────────────────────────────────────────────────────
*/
