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
}
