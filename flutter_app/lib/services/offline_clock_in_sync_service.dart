// lib/services/offline_clock_in_sync_service.dart
//
// Handles syncing pending clock-ins to Supabase when connection is restored.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/enums.dart';
import '../core/logger.dart';
import 'offline_sync_service.dart';
import 'attendance_service.dart';

final offlineClockInSyncServiceProvider =
    Provider<OfflineClockInSyncService>((ref) {
  return OfflineClockInSyncService(
    ref.watch(offlineSyncServiceProvider),
    ref.watch(attendanceServiceProvider),
  );
});

/// Service that syncs pending offline clock-ins when connection is restored.
class OfflineClockInSyncService {
  OfflineClockInSyncService(this._offlineService, this._attendanceService);

  final OfflineSyncService _offlineService;
  final AttendanceService _attendanceService;

  static const _tag = 'OfflineClockInSyncService';

  /// Attempt to sync all pending clock-ins to Supabase.
  /// Returns the number of successfully synced records.
  Future<int> syncPendingClockIns() async {
    try {
      final pending = await _offlineService.getPendingClockIns();

      if (pending.isEmpty) {
        AppLogger.info(_tag, 'No pending clock-ins to sync');
        return 0;
      }

      AppLogger.info(
          _tag, 'Starting sync of ${pending.length} pending clock-ins');

      int syncedCount = 0;
      for (final record in pending) {
        try {
          final sessionId = record['session_id'] as String;
          final memberId = record['member_id'] as String;
          final statusStr = record['status'] as String;
          final methodStr = record['method'] as String;
          final clockInId = record['id'] as String;
          final positionLabel = record['position_label'] as String?;

          final status = AttendanceStatus.values.firstWhere(
            (e) => e.value == statusStr,
            orElse: () => AttendanceStatus.present,
          );
          final method = ClockInMethod.values.firstWhere(
            (e) => e.value == methodStr,
            orElse: () => ClockInMethod.manual,
          );

          // Attempt to clock in to Supabase
          await _attendanceService.clockInMember(
            sessionId: sessionId,
            memberId: memberId,
            status: status,
            method: method,
            positionLabel: positionLabel,
          );

          // Mark as synced
          await _offlineService.markAsSynced(clockInId);
          syncedCount++;

          AppLogger.info(
            _tag,
            'Synced clock-in: $memberId in $sessionId (id: $clockInId)',
          );
        } catch (e) {
          AppLogger.warn(
            _tag,
            'Failed to sync individual clock-in: $e',
          );
          // Continue with next record instead of failing completely
        }
      }

      AppLogger.info(_tag,
          'Sync completed: $syncedCount/${pending.length} records synced');
      return syncedCount;
    } catch (e, stack) {
      AppLogger.error(_tag, 'syncPendingClockIns failed', e, stack);
      return 0;
    }
  }

  /// Delete a pending clock-in (manual removal from queue).
  Future<void> removePendingClockIn(String clockInId) async {
    try {
      await _offlineService.deletePendingClockIn(clockInId);
      AppLogger.info(_tag, 'Removed pending clock-in: $clockInId');
    } catch (e, stack) {
      AppLogger.error(_tag, 'Failed to remove pending clock-in', e, stack);
    }
  }

  /// Clear all pending clock-ins (use with caution).
  Future<void> clearAllPending() async {
    try {
      await _offlineService.clearAllPending();
      AppLogger.warn(_tag, 'Cleared all pending clock-ins');
    } catch (e, stack) {
      AppLogger.error(_tag, 'Failed to clear pending clock-ins', e, stack);
    }
  }
}
