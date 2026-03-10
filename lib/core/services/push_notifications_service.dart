/// ===============================================================
/// FILE: core/services/push_notifications_service.dart
///
/// Gestione FCM (Android) e registrazione token in Supabase.
/// - Inizializza Firebase e FirebaseMessaging.
/// - Richiede permessi notifiche (Android 13+).
/// - Salva token in `push_tokens`.
/// - Gestisce tap sulle notifiche (route dashboard).
/// ===============================================================
library;

import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../app/router.dart';

class PushNotificationsService {
  PushNotificationsService._();

  static final PushNotificationsService instance = PushNotificationsService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final Uuid _uuid = const Uuid();

  bool _initialized = false;
  String? _deviceId;
  String? _lastToken;

  Future<void> init() async {
    if (_initialized) return;

    await Firebase.initializeApp();
    await _requestPermissions();
    _deviceId ??= _uuid.v4();

    final token = await _messaging.getToken();
    _lastToken = token;
    if (token != null) {
      await _upsertToken(token);
    }

    _messaging.onTokenRefresh.listen((newToken) async {
      _lastToken = newToken;
      await _upsertToken(newToken);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final route = message.data['route'] as String? ?? '/dashboard';
      appRouter.go(route);
    });

    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      final route = initialMessage.data['route'] as String? ?? '/dashboard';
      appRouter.go(route);
    }

    _initialized = true;
  }

  Future<void> syncTokenForCurrentUser() async {
    await init();
    final token = _lastToken ?? await _messaging.getToken();
    if (token != null) {
      _lastToken = token;
      await _upsertToken(token);
    }
  }

  Future<void> _requestPermissions() async {
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  Future<void> _upsertToken(String token) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final platform = Platform.isAndroid ? 'android' : 'ios';

    await Supabase.instance.client.from('push_tokens').upsert(
      {
        'user_id': user.id,
        'device_id': _deviceId,
        'platform': platform,
        'token': token,
      },
      onConflict: 'device_id,platform',
    );
  }
}
