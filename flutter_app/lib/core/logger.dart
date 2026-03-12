// lib/core/logger.dart
//
// Thin structured logger backed by dart:developer.
// Uses the Flutter DevTools "Logging" tab — no extra packages needed.
//
// Usage:
//   AppLogger.info('SessionService', 'Fetched ${list.length} sessions');
//   AppLogger.error('AttendanceService', 'clockIn failed', e, stack);

import 'dart:developer' as dev;

class AppLogger {
  AppLogger._();

  static void info(String tag, String msg) =>
      dev.log(msg, name: tag);

  static void warn(String tag, String msg) =>
      dev.log('[WARN] $msg', name: tag, level: 900);

  static void error(
    String tag,
    String msg, [
    Object? error,
    StackTrace? stack,
  ]) =>
      dev.log(
        '[ERROR] $msg',
        name: tag,
        error: error,
        stackTrace: stack,
        level: 1000,
      );

  static void debug(String tag, String msg) =>
      dev.log('[DEBUG] $msg', name: tag, level: 500);
}
