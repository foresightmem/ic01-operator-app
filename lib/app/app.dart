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

import '../core/ui/app_design_system.dart';
import 'router.dart';

/// ===============================================================
/// IC01App
///
/// Root widget dell'app IC-01 Operator.
///
/// - Registra il GoRouter globale (appRouter).
/// - Applica il tema light brandizzato IC-01.
/// ===============================================================
class IC01App extends StatelessWidget {
  const IC01App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'IC-01 Operator',
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
      theme: buildMagmaLightTheme(),
    );
  }
}
