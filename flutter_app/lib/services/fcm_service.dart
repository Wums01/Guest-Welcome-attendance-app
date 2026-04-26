// lib/services/fcm_service.dart
//
// Manages FCM device token registration and FCM message routing.
// Call FcmService.initialize(staffId) once after staff logs in.
// Call FcmService.setRouter(router) once the GoRouter is available.

import 'dart:io';
import 'dart:async';
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
  static String? _currentStaffId;
  static String? _initializedStaffId;
  static bool _listenersAttached = false;
  static Timer? _retryTimer;

  /// Call once after the router is built (in AttendanceApp.build).
  static void setRouter(GoRouter router) => _router = router;

  /// Initializes FCM: requests permission, registers token, sets up
  /// foreground / background / terminated message handlers.
  static Future<void> initialize(String staffId) async {
    AppLogger.info(_tag, 'Initializing FCM for staffId=$staffId on ${Platform.operatingSystem}');
    _currentStaffId = staffId;
    if (_initializedStaffId == staffId) {
      AppLogger.debug(_tag, 'FCM already initialized for staffId=$staffId');
      return;
    }

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

    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
    AppLogger.debug(_tag, 'Foreground notification presentation options configured');

    final apnsToken = await _awaitApnsToken(messaging);
    AppLogger.info(
      _tag,
      'APNs token ${apnsToken == null ? 'not yet available' : 'available'}'
      '${apnsToken == null ? '' : ': ${_tokenPreview(apnsToken)}'}',
    );

    final registered = await _registerCurrentToken(messaging, staffId);
    if (!registered) {
      _scheduleRetry();
    }

    // Keep token fresh when FCM rotates it
    if (!_listenersAttached) {
      messaging.onTokenRefresh.listen((newToken) {
        AppLogger.info(_tag, 'FCM token refreshed: ${_tokenPreview(newToken)}');
        final activeStaffId = _currentStaffId;
        if (activeStaffId == null) {
          AppLogger.warn(_tag, 'Ignoring token refresh because no active staffId is set');
          return;
        }
        _upsertToken(activeStaffId, newToken);
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

      _listenersAttached = true;
      AppLogger.debug(_tag, 'FCM listeners attached');
    }

    // ── Terminated tap ───────────────────────────────────────────────
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) _handleNotificationTap(initial.data);
    if (registered) {
      _initializedStaffId = staffId;
      _retryTimer?.cancel();
      _retryTimer = null;
      AppLogger.info(_tag, 'FCM initialization completed for staffId=$staffId');
    }
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
      _currentStaffId = null;
      _initializedStaffId = null;
      _retryTimer?.cancel();
      _retryTimer = null;
      AppLogger.info(_tag, 'FCM token deleted on logout');
    } catch (e, stack) {
      AppLogger.error(_tag, 'deleteToken failed', e, stack);
    }
  }

  static Future<void> _upsertToken(String staffId, String token) async {
    final platform = Platform.isAndroid ? 'android' : 'ios';
    try {
      AppLogger.info(
        _tag,
        'Upserting FCM token for staffId=$staffId platform=$platform token=${_tokenPreview(token)}',
      );
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

  static String _tokenPreview(String token) {
    if (token.length <= 12) return token;
    return '${token.substring(0, 6)}...${token.substring(token.length - 6)}';
  }

  static Future<String?> _awaitApnsToken(FirebaseMessaging messaging) async {
    if (!Platform.isIOS) return null;

    for (var attempt = 0; attempt < 20; attempt++) {
      final apnsToken = await messaging.getAPNSToken();
      if (apnsToken != null && apnsToken.isNotEmpty) {
        AppLogger.debug(_tag, 'APNs token became available on attempt ${attempt + 1}');
        return apnsToken;
      }
      AppLogger.debug(_tag, 'APNs token unavailable on attempt ${attempt + 1}/20');
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }

    return null;
  }

  static Future<bool> _registerCurrentToken(
    FirebaseMessaging messaging,
    String staffId,
  ) async {
    try {
      AppLogger.debug(_tag, 'Requesting current FCM token for staffId=$staffId');
      final token = await messaging.getToken();
      if (token == null || token.isEmpty) {
        AppLogger.warn(_tag, 'FCM token is null');
        return false;
      }

      AppLogger.info(_tag, 'FCM token acquired: ${_tokenPreview(token)}');
      await _upsertToken(staffId, token);
      return true;
    } catch (e, stack) {
      AppLogger.error(_tag, 'getToken failed', e, stack);
      return false;
    }
  }

  static void _scheduleRetry() {
    if (_retryTimer != null) return;

    AppLogger.warn(_tag, 'Scheduling FCM token retry');
    _retryTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      final staffId = _currentStaffId;
      if (staffId == null) {
        AppLogger.warn(_tag, 'Stopping FCM retry because there is no active staffId');
        timer.cancel();
        _retryTimer = null;
        return;
      }

      AppLogger.debug(_tag, 'Running scheduled FCM retry for staffId=$staffId');
      final ok = await _registerCurrentToken(FirebaseMessaging.instance, staffId);
      if (ok) {
        _initializedStaffId = staffId;
        timer.cancel();
        _retryTimer = null;
        AppLogger.info(_tag, 'FCM retry succeeded');
      }
    });
  }
}
