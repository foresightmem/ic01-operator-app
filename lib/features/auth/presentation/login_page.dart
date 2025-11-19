// lib/features/auth/presentation/login_page.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _errorMessage = 'Inserisci email e password';
      });
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    final supabase = Supabase.instance.client;

    try {
      final response = await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.session == null || response.user == null) {
        setState(() {
          _errorMessage = 'Login non riuscito';
        });
        return;
      }

      final userId = response.user!.id;

      // Recuperiamo il ruolo dal profilo
      String role = 'refill_operator';
      final profileList = await supabase
          .from('profiles')
          .select('role')
          .eq('id', userId)
          .limit(1);

      if (profileList.isNotEmpty) {
        final row = profileList.first;
        final dbRole = row['role'] as String?;
        if (dbRole != null && dbRole.isNotEmpty) {
          role = dbRole;
        }
      }

      if (!mounted) return;

      if (role == 'technician') {
        context.go('/maintenance');
      } else {
        // refill_operator o admin → dashboard refill
        context.go('/dashboard');
      }
    } on AuthException catch (e) {
      setState(() {
        _errorMessage = e.message;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Errore imprevisto: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('IC-01 Login'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                  ),
                ),
                const SizedBox(height: 16),
                if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _signIn,
                    child: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Text('Accedi'),
                  ),
                ),
              ],
            ),
          ),
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
