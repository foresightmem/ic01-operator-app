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

// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'app/env.dart';
/// Entry point dell'applicazione IC-01 Refill.
///
/// - Inizializza il binding di Flutter.
/// - Inizializza Supabase con le configurazioni definite in [AppEnv].
/// - Wrappa l'app all'interno di [ProviderScope] per abilitare Riverpod.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: AppEnv.supabaseUrl,
    anonKey: AppEnv.supabaseAnonKey,
  );

  runApp(const ProviderScope(child: IC01App()));
}
