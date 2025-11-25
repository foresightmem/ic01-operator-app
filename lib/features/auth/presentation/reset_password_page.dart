// lib/features/auth/presentation/reset_password_page.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({super.key});

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _loading = false;
  String? _errorMessage;
  String? _successMessage;
  bool _checkingSession = true;

  @override
  void initState() {
    super.initState();
    _checkRecoverySession();
  }

  Future<void> _checkRecoverySession() async {
    // Qui verifichiamo se Supabase "vede" un utente (cioè il link di recovery ha creato una sessione)
    final supabase = Supabase.instance.client;
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        setState(() {
          _errorMessage =
              'Link non valido o scaduto. Richiedi una nuova email di recupero.';
        });
      }
    } catch (_) {
      setState(() {
        _errorMessage =
            'Errore nel verificare la sessione di recupero. Richiedi una nuova email.';
      });
    } finally {
      setState(() {
        _checkingSession = false;
      });
    }
  }

  Future<void> _updatePassword() async {
    final newPassword = _passwordController.text.trim();
    final confirmPassword = _confirmController.text.trim();

    if (newPassword.length < 6) {
      setState(() {
        _errorMessage = 'La password deve avere almeno 6 caratteri.';
      });
      return;
    }

    if (newPassword != confirmPassword) {
      setState(() {
        _errorMessage = 'Le password non coincidono.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    final supabase = Supabase.instance.client;

    try {
      await supabase.auth.updateUser(
        UserAttributes(password: newPassword),
      );

      if (!mounted) return;

      setState(() {
        _successMessage = 'Password aggiornata con successo! Ora puoi accedere.';
      });

      // Dopo 1.5s torni alla pagina di login
      await Future.delayed(const Duration(milliseconds: 1500));
      if (!mounted) return;
      context.go('/login');
    } on AuthException catch (e) {
      setState(() {
        _errorMessage = e.message;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Errore durante l’aggiornamento della password: $e';
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
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reimposta password'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                child: _checkingSession
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Imposta una nuova password',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Hai richiesto il recupero della password. Inserisci la nuova password per il tuo account.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey,
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

                          if (_successMessage != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: Text(
                                _successMessage!,
                                style: const TextStyle(
                                  color: Colors.green,
                                  fontSize: 13,
                                ),
                              ),
                            ),

                          // Nuova password
                          TextField(
                            controller: _passwordController,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'Nuova password',
                              prefixIcon: Icon(Icons.lock_outline),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Conferma password
                          TextField(
                            controller: _confirmController,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'Conferma password',
                              prefixIcon: Icon(Icons.lock_outline),
                            ),
                          ),

                          const SizedBox(height: 16),

                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed:
                                  _loading || _errorMessage?.contains('Link non valido') == true
                                      ? null
                                      : _updatePassword,
                              child: _loading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text('Aggiorna password'),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
