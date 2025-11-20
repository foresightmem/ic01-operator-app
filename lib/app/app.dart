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
      theme: _buildLightTheme(),
    );
  }
}

/// Costruisce il tema light dell’app.
/// Palette:
/// - Primary: blu IC-01
/// - Background leggermente grigio
/// - Card arrotondate con ombra morbida
ThemeData _buildLightTheme() {
  const primaryColor = Color(0xFF0052CC); // blu IC-01
  const secondaryColor = Color(0xFF1B73E8);
  const scaffoldBg = Color(0xFFF5F5F7);
  const errorColor = Color(0xFFB00020);

  final base = ThemeData.light();

  final colorScheme = ColorScheme.fromSeed(
    seedColor: primaryColor,
    primary: primaryColor,
    secondary: secondaryColor,
    surface: Colors.white,
    error: errorColor,
  );

  return base.copyWith(
    colorScheme: colorScheme,
    primaryColor: primaryColor,
    scaffoldBackgroundColor: scaffoldBg,

    appBarTheme: AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: Colors.black87,
      elevation: 0.5,
      centerTitle: false,
      titleTextStyle: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: Colors.black87,
      ),
      iconTheme: const IconThemeData(color: Colors.black87),
    ),

    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 1.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      margin: EdgeInsets.zero,
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primaryColor,
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: primaryColor, width: 1.5),
      ),
    ),

    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      elevation: 3,
      indicatorColor: primaryColor.withValues(alpha: 0.12),
      labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>(
        (states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          );
        },
      ),
    ),

    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
  );
}
