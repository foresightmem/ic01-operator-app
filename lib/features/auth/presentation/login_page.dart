// lib/features/auth/presentation/login_page.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// ===============================================================
/// LoginPage
///
/// Schermata di login:
/// - Form email + password.
/// - Usa Supabase Auth (signInWithPassword).
/// - Dopo il login:
///     - legge il ruolo da public.profiles.role
///     - se role == 'technician' → va a /maintenance
///     - altrimenti → va a /dashboard
///
/// UI:
/// - Branding IC-01 con card centrale.
/// - Messaggi di errore chiari.
/// - Bottone "Password dimenticata?" che invia email di reset.
/// ===============================================================
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _loading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final supabase = Supabase.instance.client;
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _errorMessage = 'Inserisci email e password.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final response = await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      final user = response.user;
      if (user == null) {
        setState(() {
          _errorMessage = 'Credenziali non valide.';
          _loading = false;
        });
        return;
      }

      // Leggiamo il ruolo dal profilo
      final profileData = await supabase
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();

      final role = profileData != null ? profileData['role'] as String? : null;

      if (!mounted) return;

      if (role == 'technician') {
        context.go('/maintenance');
      } else {
        context.go('/dashboard');
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Errore di accesso: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _sendPasswordReset() async {
    final supabase = Supabase.instance.client;
    final email = _emailController.text.trim();

    if (email.isEmpty) {
      setState(() {
        _errorMessage = 'Inserisci la tua email per il recupero password.';
      });
      return;
    }

    setState(() {
      _errorMessage = null;
    });

    try {
      await supabase.auth.resetPasswordForEmail(
        email,
        // opzionale: se hai configurato l’URL di redirect in Supabase
        redirectTo: 'http://localhost:63803/reset-password',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Email di recupero password inviata, se l’email esiste.'),
        ),
      );
    } catch (e) {
      setState(() {
        _errorMessage = 'Errore durante l’invio dell’email: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Branding IC-01
                const SizedBox(height: 16),
                Text(
                  'IC-01',
                  style: TextStyle(
                    fontSize: 46,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Refill & Maintenance',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 24),

                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Accedi al tuo account',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Usa le credenziali fornite da IC-01 / GEDA.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Email
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            prefixIcon: Icon(Icons.email_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Password
                        TextField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _signIn(),
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        if (_errorMessage != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 13,
                              ),
                            ),
                          ),

                        // Bottone login
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
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('Accedi'),
                          ),
                        ),

                        const SizedBox(height: 8),

                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _loading ? null : _sendPasswordReset,
                            child: const Text('Password dimenticata?'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),
                const Text(
                  'IC-01 v.1 by MAGMA S.r.l',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey,
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
