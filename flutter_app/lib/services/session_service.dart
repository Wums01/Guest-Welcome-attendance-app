// lib/services/session_service.dart
//
// Dart equivalent of lib/core/sessions.ts
// All localStorage operations replaced with Supabase queries.
//
// Key business rules preserved:
//   - createSundaySessions: auto-creates "Service 1/2/3" for Sunday programs
//   - createWednesdaySessions: auto-creates "Switch Service"
//   - deleteSessionsByProgram: not needed here — DB CASCADE handles it

import 'package:flutter_riverpod/flutter_riverpod.dart';
// hide Session: gotrue (via supabase_flutter) also exports a Session type.
// Hiding it here means 'Session' in this file unambiguously refers to our model.
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import '../models/session.dart';
import '../core/logger.dart';

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final sessionServiceProvider = Provider<SessionService>(
  (ref) => SessionService(Supabase.instance.client),
);

// ---------------------------------------------------------------------------
// SessionService
// ---------------------------------------------------------------------------

class SessionService {
  SessionService(this._client);
  final SupabaseClient _client;

  static const _table = 'sessions';
  static const _tag = 'SessionService';

  // ── Read ──────────────────────────────────────────────────────────────────

  Future<List<Session>> getSessions() async {
    AppLogger.info(_tag, 'getSessions()');
    try {
      final data = await _client
          .from(_table)
          .select()
          .order('date', ascending: false);
      final sessions = (data as List).map((e) => Session.fromJson(e)).toList();
      AppLogger.info(_tag, 'getSessions → ${sessions.length} sessions');
      return sessions;
    } catch (e, stack) {
      AppLogger.error(_tag, 'getSessions failed', e, stack);
      rethrow;
    }
  }

  Future<Session?> getSessionById(String id) async {
    AppLogger.info(_tag, 'getSessionById($id)');
    try {
      final data = await _client
          .from(_table)
          .select()
          .eq('id', id)
          .maybeSingle();
      if (data == null) {
        AppLogger.warn(_tag, 'getSessionById($id) → not found');
        return null;
      }
      final session = Session.fromJson(data);
      AppLogger.info(_tag, 'getSessionById($id) → "${session.name}"');
      return session;
    } catch (e, stack) {
      AppLogger.error(_tag, 'getSessionById($id) failed', e, stack);
      rethrow;
    }
  }

  /// Returns sessions for a specific date. Format: "YYYY-MM-DD".
  Future<List<Session>> getSessionsByDate(String date) async {
    AppLogger.info(_tag, 'getSessionsByDate($date)');
    try {
      final data = await _client
          .from(_table)
          .select()
          .eq('date', date)
          .order('name');
      final sessions = (data as List).map((e) => Session.fromJson(e)).toList();
      AppLogger.info(_tag, 'getSessionsByDate($date) → ${sessions.length} sessions');
      return sessions;
    } catch (e, stack) {
      AppLogger.error(_tag, 'getSessionsByDate($date) failed', e, stack);
      rethrow;
    }
  }

  /// Returns all sessions belonging to a program.
  Future<List<Session>> getSessionsByProgram(String programId) async {
    AppLogger.info(_tag, 'getSessionsByProgram($programId)');
    try {
      final data = await _client
          .from(_table)
          .select()
          .eq('program_id', programId)
          .order('date', ascending: true);
      final sessions = (data as List).map((e) => Session.fromJson(e)).toList();
      AppLogger.info(_tag, 'getSessionsByProgram($programId) → ${sessions.length} sessions');
      return sessions;
    } catch (e, stack) {
      AppLogger.error(_tag, 'getSessionsByProgram($programId) failed', e, stack);
      rethrow;
    }
  }

  /// Returns sessions in a given month. [yearMonth] format: "YYYY-MM".
  Future<List<Session>> getSessionsByMonth(String yearMonth) async {
    AppLogger.info(_tag, 'getSessionsByMonth($yearMonth)');
    try {
      final data = await _client
          .from(_table)
          .select()
          .like('date', '$yearMonth%')
          .order('date', ascending: true);
      final sessions = (data as List).map((e) => Session.fromJson(e)).toList();
      AppLogger.info(_tag, 'getSessionsByMonth($yearMonth) → ${sessions.length} sessions');
      return sessions;
    } catch (e, stack) {
      AppLogger.error(_tag, 'getSessionsByMonth($yearMonth) failed', e, stack);
      rethrow;
    }
  }

  // ── Write ─────────────────────────────────────────────────────────────────

  Future<Session> createSession({
    required String programId,
    required String name,
    required String date,
    String? startTime,
    String? endTime,
    bool clockInRequired = true,
  }) async {
    AppLogger.info(_tag, 'createSession(name: "$name", date: $date)');
    try {
      final insert = {
        'program_id': programId,
        'name': name.trim(),
        'date': date,
        'start_time': startTime,
        'end_time': endTime,
        'clock_in_required': clockInRequired,
      };
      final data =
          await _client.from(_table).insert(insert).select().single();
      final session = Session.fromJson(data);
      AppLogger.info(_tag, 'createSession → created "${session.name}" (${session.id})');
      return session;
    } catch (e, stack) {
      AppLogger.error(_tag, 'createSession(name: "$name") failed', e, stack);
      rethrow;
    }
  }

  /// Sunday helper: creates Service 1, Service 2, Service 3 for the given date.
  /// Mirrors createSundaySessions() in sessions.ts.
  Future<List<Session>> createSundaySessions({
    required String programId,
    required String date,
  }) async {
    AppLogger.info(_tag, 'createSundaySessions(date: $date)');
    const services = [
      ('Service 1', '06:30', '08:30'),
      ('Service 2', '08:30', '11:00'),
      ('Service 3', '11:00', '13:30'),
    ];
    final futures = services.map(
      (s) => createSession(
        programId: programId,
        name: s.$1,
        date: date,
        startTime: s.$2,
        endTime: s.$3,
      ),
    );
    final sessions = await Future.wait(futures);
    AppLogger.info(_tag, 'createSundaySessions → created ${sessions.length} sessions');
    return sessions;
  }

  /// Wednesday helper: creates a single "Switch Service" session.
  /// Mirrors createWednesdaySessions() in sessions.ts.
  Future<List<Session>> createWednesdaySessions({
    required String programId,
    required String date,
  }) async {
    AppLogger.info(_tag, 'createWednesdaySessions(date: $date)');
    final session = await createSession(
      programId: programId,
      name: 'Switch Service',
      date: date,
    );
    AppLogger.info(_tag, 'createWednesdaySessions → created "${session.name}"');
    return [session];
  }

  Future<void> updateSession(
    String sessionId, {
    String? name,
    String? date,
    String? startTime,
    String? endTime,
    bool? clockInRequired,
  }) async {
    AppLogger.info(_tag, 'updateSession($sessionId)');
    try {
      final patch = <String, dynamic>{};
      if (name != null) patch['name'] = name.trim();
      if (date != null) patch['date'] = date;
      if (startTime != null) patch['start_time'] = startTime;
      if (endTime != null) patch['end_time'] = endTime;
      if (clockInRequired != null) patch['clock_in_required'] = clockInRequired;
      if (patch.isEmpty) {
        AppLogger.warn(_tag, 'updateSession($sessionId) called with no changes');
        return;
      }
      AppLogger.debug(_tag, 'updateSession patch: $patch');
      await _client.from(_table).update(patch).eq('id', sessionId);
      AppLogger.info(_tag, 'updateSession($sessionId) → ok');
    } catch (e, stack) {
      AppLogger.error(_tag, 'updateSession($sessionId) failed', e, stack);
      rethrow;
    }
  }

  Future<void> deleteSession(String sessionId) async {
    AppLogger.info(_tag, 'deleteSession($sessionId)');
    try {
      // DB CASCADE on clock_ins.session_id handles attendance cleanup.
      await _client.from(_table).delete().eq('id', sessionId);
      AppLogger.info(_tag, 'deleteSession($sessionId) → ok');
    } catch (e, stack) {
      AppLogger.error(_tag, 'deleteSession($sessionId) failed', e, stack);
      rethrow;
    }
  }
}
