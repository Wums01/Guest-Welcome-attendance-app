// lib/services/report_service.dart
//
// Dart equivalent of lib/core/reports.ts and lib/core/leaderboard.ts
//
// Uses the Supabase views created in the migration:
//   - session_attendance_summary  (daily reports)
//   - monthly_leaderboard         (leaderboard + yearly)

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/attendance_summary.dart';
import '../models/attendance_export_entry.dart';
import '../models/leaderboard_entry.dart';
import '../core/logger.dart';

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final reportServiceProvider = Provider<ReportService>(
  (ref) => ReportService(Supabase.instance.client),
);

// ---------------------------------------------------------------------------
// ReportService
// ---------------------------------------------------------------------------

class ReportService {
  ReportService(this._client);
  final SupabaseClient _client;

  static const _tag = 'ReportService';

  // ── Daily report ──────────────────────────────────────────────────────────

  /// Returns attendance summaries for all sessions on a given date.
  /// [date] format: "YYYY-MM-DD"
  Future<List<AttendanceSummary>> getDailyReport(String date) async {
    AppLogger.info(_tag, 'getDailyReport($date)');
    try {
      final data = await _client
          .from('session_attendance_summary')
          .select()
          .eq('session_date', date)
          .order('session_name');
      final summaries = (data as List)
          .map((e) => AttendanceSummary.fromJson(e))
          .toList();
      AppLogger.info(_tag, 'getDailyReport($date) → ${summaries.length} summaries');
      return summaries;
    } catch (e, stack) {
      AppLogger.error(_tag, 'getDailyReport($date) failed', e, stack);
      rethrow;
    }
  }

  // ── Monthly leaderboard ───────────────────────────────────────────────────

  /// Returns the attendance leaderboard for [yearMonth] (format: "YYYY-MM"),
  /// sorted by present_count descending, with rank assigned.
  Future<List<LeaderboardEntry>> getMonthlyLeaderboard(
      String yearMonth) async {
    AppLogger.info(_tag, 'getMonthlyLeaderboard($yearMonth)');
    try {
      final data = await _client
          .from('monthly_leaderboard')
          .select()
          .eq('year_month', yearMonth)
          .order('present_count', ascending: false);

      final entries = (data as List)
          .asMap()
          .entries
          .map((e) => LeaderboardEntry.fromJson(e.value, rank: e.key + 1))
          .toList();
      AppLogger.info(_tag, 'getMonthlyLeaderboard($yearMonth) → ${entries.length} entries');
      return entries;
    } catch (e, stack) {
      AppLogger.error(_tag, 'getMonthlyLeaderboard($yearMonth) failed', e, stack);
      rethrow;
    }
  }

  // ── Yearly leaderboard ────────────────────────────────────────────────────

  /// Aggregates all months in [year] (format: "YYYY") into a single ranking.
  Future<List<LeaderboardEntry>> getYearlyLeaderboard(String year) async {
    AppLogger.info(_tag, 'getYearlyLeaderboard($year)');
    try {
      final data = await _client
          .from('monthly_leaderboard')
          .select()
          .like('year_month', '$year%');

      // Aggregate present_count per member across all months
      final Map<String, Map<String, dynamic>> aggregated = {};
      for (final row in data as List) {
        final id = row['member_id'] as String;
        if (aggregated.containsKey(id)) {
          aggregated[id]!['present_count'] =
              (aggregated[id]!['present_count'] as int) +
                  ((row['present_count'] as num?)?.toInt() ?? 0);
        } else {
          aggregated[id] = Map<String, dynamic>.from(row);
          // Use the year as the year_month label
          aggregated[id]!['year_month'] = year;
        }
      }

      final sorted = aggregated.values.toList()
        ..sort((a, b) => (b['present_count'] as int)
            .compareTo(a['present_count'] as int));

      final entries = sorted
          .asMap()
          .entries
          .map((e) => LeaderboardEntry.fromJson(e.value, rank: e.key + 1))
          .toList();
      AppLogger.info(_tag, 'getYearlyLeaderboard($year) → ${entries.length} entries');
      return entries;
    } catch (e, stack) {
      AppLogger.error(_tag, 'getYearlyLeaderboard($year) failed', e, stack);
      rethrow;
    }
  }

  // ── Sessions by date range ────────────────────────────────────────────────

  /// Returns AttendanceSummary for all sessions between [startDate] and
  /// [endDate] inclusive.  Format: "YYYY-MM-DD".
  Future<List<AttendanceSummary>> getSessionsByDateRange(
      String startDate, String endDate) async {
    AppLogger.info(_tag, 'getSessionsByDateRange($startDate → $endDate)');
    try {
      final data = await _client
          .from('session_attendance_summary')
          .select()
          .gte('session_date', startDate)
          .lte('session_date', endDate)
          .order('session_date')
          .order('session_name');
      final summaries = (data as List)
          .map((e) => AttendanceSummary.fromJson(e))
          .toList();
      AppLogger.info(
          _tag, 'getSessionsByDateRange → ${summaries.length} summaries');
      return summaries;
    } catch (e, stack) {
      AppLogger.error(
          _tag,
          'getSessionsByDateRange($startDate → $endDate) failed',
          e,
          stack);
      rethrow;
    }
  }

  /// Returns the total manually-entered guest count for a month.
  /// [yearMonth] format: "YYYY-MM".
  Future<int> getMonthlyGuestTotal(String yearMonth) async {
    AppLogger.info(_tag, 'getMonthlyGuestTotal($yearMonth)');
    try {
      final data = await _client
          .from('sessions')
          .select('new_guest_count')
          .like('date', '$yearMonth%');

      final total = (data as List).fold<int>(
        0,
        (sum, row) => sum + ((row['new_guest_count'] as num?)?.toInt() ?? 0),
      );
      AppLogger.info(_tag, 'getMonthlyGuestTotal($yearMonth) → $total guests');
      return total;
    } catch (e, stack) {
      AppLogger.error(_tag, 'getMonthlyGuestTotal($yearMonth) failed', e, stack);
      rethrow;
    }
  }

  /// Returns raw attendance rows for all sessions on a date.
  /// Used for workbook export where each session gets its own sheet.
  Future<List<AttendanceExportEntry>> getAttendanceExportRows(String date) async {
    AppLogger.info(_tag, 'getAttendanceExportRows($date)');
    try {
      final sessions = await _client
          .from('sessions')
          .select('id')
          .eq('date', date)
          .order('name');

      final sessionIds = (sessions as List)
          .map((row) => row['id'] as String)
          .toList();

      if (sessionIds.isEmpty) {
        AppLogger.info(_tag, 'getAttendanceExportRows($date) → 0 rows');
        return [];
      }

      final data = await _client
          .from('clock_ins')
          .select(
            'session_id,status,clocked_at,'
            'members!clock_ins_member_id_fkey(full_name),'
            'sessions!clock_ins_session_id_fkey(name)',
          )
          .inFilter('session_id', sessionIds)
          .order('session_id')
          .order('clocked_at');

      final rows = (data as List)
          .map((row) => AttendanceExportEntry.fromJson(row))
          .toList();
      AppLogger.info(_tag, 'getAttendanceExportRows($date) → ${rows.length} rows');
      return rows;
    } catch (e, stack) {
      AppLogger.error(_tag, 'getAttendanceExportRows($date) failed', e, stack);
      rethrow;
    }
  }

  Future<List<AttendanceExportEntry>> getAttendanceExportRowsByDateRange(
    String startDate,
    String endDate,
  ) async {
    AppLogger.info(_tag, 'getAttendanceExportRowsByDateRange($startDate → $endDate)');
    try {
      final sessions = await _client
          .from('sessions')
          .select('id')
          .gte('date', startDate)
          .lte('date', endDate)
          .order('date')
          .order('name');

      final sessionIds = (sessions as List)
          .map((row) => row['id'] as String)
          .toList();

      if (sessionIds.isEmpty) {
        AppLogger.info(
          _tag,
          'getAttendanceExportRowsByDateRange($startDate → $endDate) → 0 rows',
        );
        return [];
      }

      final data = await _client
          .from('clock_ins')
          .select(
            'session_id,status,clocked_at,'
            'members!clock_ins_member_id_fkey(full_name),'
            'sessions!clock_ins_session_id_fkey(name)',
          )
          .inFilter('session_id', sessionIds)
          .order('session_id')
          .order('clocked_at');

      final rows = (data as List)
          .map((row) => AttendanceExportEntry.fromJson(row))
          .toList();
      AppLogger.info(
        _tag,
        'getAttendanceExportRowsByDateRange($startDate → $endDate) → ${rows.length} rows',
      );
      return rows;
    } catch (e, stack) {
      AppLogger.error(
        _tag,
        'getAttendanceExportRowsByDateRange($startDate → $endDate) failed',
        e,
        stack,
      );
      rethrow;
    }
  }
}
