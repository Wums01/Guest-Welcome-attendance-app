// lib/core/app_logger.dart
//
// Structured logger built on dart:developer.
// Output appears in Flutter DevTools (Logging tab) and the IDE debug console.
//
// Levels:
//   debug  → verbose tracing, heavy hot-paths
//   info   → normal lifecycle events (init, navigation, CRUD success)
//   warn   → recoverable issues (not-found, empty result where one expected)
//   error  → exceptions, failed DB calls (always includes error + stack)
//
// Usage:
//   AppLogger.info('Members loaded', tag: 'MemberService', data: '42 records');
//   AppLogger.error('Clock-in failed', tag: 'Attendance', error: e, stack: s);

import 'dart:developer' as dev;

class AppLogger {
  AppLogger._();

  // ── Public API ─────────────────────────────────────────────────────────────

  static void debug(String msg, {String tag = 'App', Object? data}) =>
      _emit(800, '🔍', tag, msg, data: data);

  static void info(String msg, {String tag = 'App', Object? data}) =>
      _emit(900, 'ℹ️ ', tag, msg, data: data);

  static void warn(String msg, {String tag = 'App', Object? data}) =>
      _emit(1000, '⚠️ ', tag, msg, data: data);

  static void error(
    String msg, {
    String tag = 'App',
    Object? error,
    StackTrace? stack,
  }) =>
      _emit(1200, '❌', tag, msg, error: error, stack: stack);

  // ── Internal ───────────────────────────────────────────────────────────────

  static void _emit(
    int level,
    String icon,
    String tag,
    String msg, {
    Object? data,
    Object? error,
    StackTrace? stack,
  }) {
    final body = data != null ? '$msg  →  $data' : msg;
    dev.log(
      '$icon [$tag] $body',
      name: tag,
      level: level,
      error: error,
      stackTrace: stack,
    );
  }
}
