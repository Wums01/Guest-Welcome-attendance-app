// lib/services/fcm_service.dart
//
// Manages FCM device token registration and FCM message routing.
// Call FcmService.initialize(staffId) once after staff logs in.
// Call FcmService.setRouter(router) once the GoRouter is available.

import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/logger.dart';
import '../core/notifications.dart';

class FcmService {
  FcmService._();

  static const _tag = 'FcmService';
  static const _tokensTable = 'device_tokens';
  static GoRouter? _router;

  /// Call once after the router is built (in AttendanceApp.build).
  static void setRouter(GoRouter router) => _router = router;

  /// Initializes FCM: requests permission, registers token, sets up
  /// foreground / background / terminated message handlers.
  static Future<void> initialize(String staffId) async {
    final messaging = FirebaseMessaging.instance;

    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    AppLogger.info(
        _tag, 'FCM permission: ${settings.authorizationStatus}');

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      AppLogger.warn(_tag, 'FCM permission denied — push will not work');
      return;
    }

    // Register current token
    final token = await messaging.getToken();
    if (token != null) await _upsertToken(staffId, token);

    // Keep token fresh when FCM rotates it
    messaging.onTokenRefresh.listen((newToken) {
      _upsertToken(staffId, newToken);
    });

    // ── Foreground messages ──────────────────────────────────────────
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      AppLogger.info(
          _tag, 'FCM foreground: ${message.notification?.title}');
      final n = message.notification;
      if (n != null) {
        NotificationService.showFcmBanner(n.title ?? '', n.body ?? '');
      }
    });

    // ── Background tap ───────────────────────────────────────────────
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleNotificationTap(message.data);
    });

    // ── Terminated tap ───────────────────────────────────────────────
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) _handleNotificationTap(initial.data);
  }

  /// Removes this device's token from Supabase and deletes it from FCM.
  static Future<void> deleteToken() async {
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) return;
    try {
      await Supabase.instance.client
          .from(_tokensTable)
          .delete()
          .eq('token', token);
      await FirebaseMessaging.instance.deleteToken();
      AppLogger.info(_tag, 'FCM token deleted on logout');
    } catch (e, stack) {
      AppLogger.error(_tag, 'deleteToken failed', e, stack);
    }
  }

  static Future<void> _upsertToken(String staffId, String token) async {
    final platform = Platform.isAndroid ? 'android' : 'ios';
    try {
      await Supabase.instance.client.from(_tokensTable).upsert(
        {
          'staff_id': staffId,
          'token': token,
          'platform': platform,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'token',
      );
      AppLogger.info(_tag, 'FCM token upserted ($platform)');
    } catch (e, stack) {
      AppLogger.error(_tag, '_upsertToken failed', e, stack);
    }
  }

  static void _handleNotificationTap(Map<String, dynamic> data) {
    final route = data['route'] as String?;
    if (route == null || _router == null) return;
    AppLogger.info(_tag, 'FCM tap → $route');
    _router!.go(route);
  }
}
