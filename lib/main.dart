/// ===============================================================
/// FILE: main.dart
///
/// Entry point dell'app IC-01 Operator.
/// - Inizializza Supabase e qualsiasi altro servizio globale.
/// - Crea l'istanza di IC01App (root widget) e la avvia.
/// - Può contenere ProviderScope (Riverpod) e tema globale.
///
/// COSA TIPICAMENTE SI MODIFICA:
/// - Configurazione Supabase (url/anon key) in fase di deploy.
/// - Tema globale dell'app se non è in app.dart.
///
/// COSA È MEGLIO NON TOCCARE:
/// - La logica di runApp / inizializzazione async, per evitare
///   problemi di bootstrap.
/// ===============================================================
library;

import 'dart:async';

// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'app/env.dart';
import 'core/services/push_notifications_service.dart';

/// Entry point dell'applicazione IC-01 Refill.
///
/// - Inizializza il binding di Flutter.
/// - Inizializza Supabase con le configurazioni definite in [AppEnv].
/// - Wrappa l'app all'interno di [ProviderScope] per abilitare Riverpod.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    AppEnv.validate();
  } on StateError catch (error) {
    runApp(_ConfigurationErrorApp(message: error.message));
    return;
  }

  await Supabase.initialize(
    url: AppEnv.supabaseUrl,
    anonKey: AppEnv.supabaseAnonKey,
  );

  runApp(const ProviderScope(child: IC01App()));

  unawaited(PushNotificationsService.instance.init());
}

class _ConfigurationErrorApp extends StatelessWidget {
  const _ConfigurationErrorApp({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Configurazione Supabase mancante',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(message),
                  const SizedBox(height: 16),
                  const SelectableText(
                    'Avvia con:\n'
                    'flutter run -d chrome '
                    '--dart-define=SUPABASE_URL=https://<project-ref>.supabase.co '
                    '--dart-define=SUPABASE_PUBLISHABLE_KEY=<publishable-key>',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
