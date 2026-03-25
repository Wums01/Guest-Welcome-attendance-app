// lib/core/notifications.dart
//
// Local notification service for the Guest Welcome Attendance app.
// Handles birthday alerts, anniversary alerts, and absence follow-up alerts.
//
// Uses flutter_local_notifications (no FCM/server needed).
// All notifications are device-local and fire at scheduled times.

import 'dart:math';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/member.dart';
import 'logger.dart';

class NotificationService {
  NotificationService._();

  static const _tag = 'NotificationService';
  static final _plugin = FlutterLocalNotificationsPlugin();

  static const _channelId = 'attendance_alerts';
  static const _channelName = 'Attendance Alerts';
  static const _channelDesc =
      'Birthday, anniversary, and absence follow-up alerts';

  // ── Initialise ─────────────────────────────────────────────────────────────

  static Future<void> init() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(initSettings);
    AppLogger.info(_tag, 'NotificationService initialised');

    // Request Android 13+ notification permission
    final android =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      final granted = await android.requestNotificationsPermission();
      AppLogger.info(_tag, 'Notification permission granted: $granted');
    }
  }

  // ── Birthday / Anniversary ──────────────────────────────────────────────────

  /// Show an immediate birthday notification for [member].
  static Future<void> showBirthdayNotification(Member member) async {
    AppLogger.info(_tag, 'showBirthdayNotification: ${member.fullName}');
    await _plugin.show(
      member.id.hashCode & 0x7FFFFFFF,
      '🎂 Birthday Today!',
      '${member.fullName} is celebrating their birthday today. Send them a warm welcome!',
      _details(),
    );
  }

  /// Show an immediate anniversary notification for [member].
  static Future<void> showAnniversaryNotification(Member member) async {
    AppLogger.info(_tag, 'showAnniversaryNotification: ${member.fullName}');
    await _plugin.show(
      (member.id.hashCode & 0x7FFFFFFF) + 1,
      '💑 Anniversary Today!',
      '${member.fullName} is celebrating their wedding anniversary today!',
      _details(),
    );
  }

  // ── Absence Alert ─────────────────────────────────────────────────────────

  /// Show a follow-up alert when [members] have been absent for 2+ Sundays.
  static Future<void> showAbsenceAlert(List<Member> members) async {
    if (members.isEmpty) return;
    AppLogger.info(
        _tag, 'showAbsenceAlert: ${members.length} absent members');
    final names = members.take(3).map((m) => m.fullName).join(', ');
    final extra = members.length > 3 ? ' and ${members.length - 3} more' : '';
    await _plugin.show(
      99999,
      '⚠️  Follow-up Needed',
      '$names$extra ${members.length == 1 ? 'has' : 'have'} not attended in 2+ Sundays.',
      _details(),
    );
  }

  /// Show a notification when weekly sessions are generated.
  ///
  /// Messages are based on the A.S.H.L.I.E values (Accountability, Service,
  /// Humility, Love, Integrity, Excellence).
  static Future<void> showWeeklySessionGenerationNotification(int createdCount) async {
    if (createdCount <= 0) return;

    const messages = [
      'Accountability: Your team is ready — sessions are now set for the week!',
      'Service: New sessions have been created. Let’s serve well this week!',
      'Humility: A fresh start is ready for your team — let’s keep growing.',
      'Love: These sessions are an opportunity to love people well — go be present.',
      'Integrity: Your schedule is built. Now lead with consistency and care.',
      'Excellence: You’re set up for an excellent week — keep the momentum going!',
    ];

    final message = messages[Random().nextInt(messages.length)];

    await _plugin.show(
      100000,
      '✅ Weekly sessions ready',
      'Generated $createdCount session${createdCount == 1 ? '' : 's'}. $message',
      _details(),
    );
  }

  // ── Internal ──────────────────────────────────────────────────────────────

  static NotificationDetails _details() {
    const android = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    return const NotificationDetails(android: android);
  }
}
