/// ===============================================================
/// FILE: app/app.dart
///
/// Root widget dell'app:
/// - Registra il GoRouter globale (appRouter).
/// - Applica il tema (ThemeData).
/// - Gestisce eventuali provider globali (es. Riverpod).
///
/// COSA TIPICAMENTE SI MODIFICA:
/// - Tema (colori, font, stile AppBar).
/// - Localizzazione (lingua, formati data/numero).
///
/// COSA È MEGLIO NON TOCCARE:
/// - L'uso di appRouter come routerDelegate, per non rompere
///   la navigazione.
/// ===============================================================
library;

// lib/app/app.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';

/// Widget root dell'app IC-01.
///
/// Configura:
/// - titolo dell'app
/// - tema Material 3
/// - routing tramite [appRouter]

class IC01App extends ConsumerWidget {
  const IC01App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'IC-01 Track&Plan',
      debugShowCheckedModeBanner: false,
      routerConfig: appRouter,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
    );
  }
}
