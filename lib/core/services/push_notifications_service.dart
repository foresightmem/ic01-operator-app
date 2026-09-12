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

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../app/router.dart';

class PushNotificationsService {
  PushNotificationsService._();

  static final PushNotificationsService instance = PushNotificationsService._();

  FirebaseMessaging? _messaging;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final Uuid _uuid = const Uuid();

  bool _initialized = false;
  String? _deviceId;
  String? _lastToken;
  SharedPreferences? _prefs;

  static const AndroidNotificationChannel _androidChannel =
      AndroidNotificationChannel(
        'ic01_push_default',
        'Notifiche',
        description: 'Notifiche push dell’app',
        importance: Importance.high,
      );

  Future<void> init() async {
    if (_initialized) return;
    if (kIsWeb) {
      // Firebase Messaging + local notifications are not configured for web here.
      _initialized = true;
      return;
    }

    try {
      await Firebase.initializeApp().timeout(const Duration(seconds: 8));
      _messaging ??= FirebaseMessaging.instance;
      _prefs ??= await SharedPreferences.getInstance().timeout(
        const Duration(seconds: 4),
      );
      await _initLocalNotifications().timeout(const Duration(seconds: 4));
      await _requestPermissions().timeout(const Duration(seconds: 8));
      await _messaging
          ?.setForegroundNotificationPresentationOptions(
            alert: true,
            badge: true,
            sound: true,
          )
          .timeout(const Duration(seconds: 4));
      _deviceId ??= _prefs?.getString('push_device_id');
      if (_deviceId == null) {
        _deviceId = _uuid.v4();
        await _prefs?.setString('push_device_id', _deviceId!);
      }

      final token = await _messaging?.getToken().timeout(
        const Duration(seconds: 8),
        onTimeout: () => null,
      );
      _lastToken = token;
      debugPrint('[FCM] token: $token');
      debugPrint('[FCM] deviceId: $_deviceId');
      if (token != null) {
        await _upsertToken(token).timeout(const Duration(seconds: 8));
      }

      _messaging?.onTokenRefresh.listen((newToken) async {
        _lastToken = newToken;
        debugPrint('[FCM] token refresh: $newToken');
        await _upsertToken(newToken);
      });

      FirebaseMessaging.onMessage.listen((message) {
        final notification = message.notification;
        final title = notification?.title ?? (message.data['title'] as String?);
        final body = notification?.body ?? (message.data['body'] as String?);
        if (title == null && body == null) return;

        _localNotifications.show(
          message.hashCode,
          title,
          body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              _androidChannel.id,
              _androidChannel.name,
              channelDescription: _androidChannel.description,
              importance: Importance.high,
              priority: Priority.high,
              icon: notification?.android?.smallIcon ?? 'ic_launcher',
            ),
            iOS: const DarwinNotificationDetails(),
          ),
          payload: message.data['route'] as String? ?? '/dashboard',
        );
      });

      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        final route = message.data['route'] as String? ?? '/dashboard';
        appRouter.go(route);
      });

      final initialMessage = await _messaging?.getInitialMessage().timeout(
        const Duration(seconds: 4),
        onTimeout: () => null,
      );
      if (initialMessage != null) {
        final route = initialMessage.data['route'] as String? ?? '/dashboard';
        appRouter.go(route);
      }
    } catch (error) {
      debugPrint('[FCM] init skipped: $error');
    } finally {
      _initialized = true;
    }
  }

  Future<void> syncTokenForCurrentUser() async {
    if (kIsWeb) return;
    await init();
    final token = _lastToken ?? await _messaging?.getToken();
    if (token != null) {
      _lastToken = token;
      await _upsertToken(token);
    }
  }

  Future<void> _requestPermissions() async {
    await _messaging?.requestPermission(alert: true, badge: true, sound: true);
  }

  Future<void> _initLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('ic_launcher');
    const iosInit = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        final route = response.payload ?? '/dashboard';
        appRouter.go(route);
      },
    );

    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await androidPlugin?.createNotificationChannel(_androidChannel);
    }
  }

  Future<void> _upsertToken(String token) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final platform = defaultTargetPlatform == TargetPlatform.android
        ? 'android'
        : 'ios';

    await Supabase.instance.client.from('push_tokens').upsert({
      'user_id': user.id,
      'device_id': _deviceId,
      'platform': platform,
      'token': token,
    }, onConflict: 'user_id,device_id,platform');
  }
}
