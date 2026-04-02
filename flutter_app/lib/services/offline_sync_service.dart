// lib/services/offline_sync_service.dart
//
// Offline support: Queues clock-ins locally when offline,
// syncs them to Supabase when connection is restored.

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../models/enums.dart';
import '../core/logger.dart';

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final offlineSyncServiceProvider = Provider<OfflineSyncService>((ref) {
  return OfflineSyncService();
});

// Monitor connectivity state
final connectivityProvider = StreamProvider<ConnectivityResult>((ref) {
  return Connectivity().onConnectivityChanged.cast<ConnectivityResult>();
});

// ---------------------------------------------------------------------------
// OfflineSyncService
// ---------------------------------------------------------------------------

class OfflineSyncService {
  static const _tag = 'OfflineSyncService';
  Database? _db;

  Future<Database> _getDb() async {
    if (_db != null && _db!.isOpen) return _db!;

    final dbPath = await getDatabasesPath();
    final path = '$dbPath/attendance_offline.db';

    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE pending_clockins (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            member_id TEXT NOT NULL,
            status TEXT NOT NULL,
            method TEXT NOT NULL,
            clocked_at TEXT NOT NULL,
            created_at TEXT NOT NULL,
            synced INTEGER DEFAULT 0
          )
        ''');
      },
    );

    return _db!;
  }

  /// Save a pending clock-in locally (offline fallback)
  Future<void> addPendingClockIn({
    required String id,
    required String sessionId,
    required String memberId,
    required AttendanceStatus status,
    required ClockInMethod method,
    required DateTime clockedAt,
  }) async {
    try {
      final db = await _getDb();
      await db.insert(
        'pending_clockins',
        {
          'id': id,
          'session_id': sessionId,
          'member_id': memberId,
          'status': status.value,
          'method': method.value,
          'clocked_at': clockedAt.toIso8601String(),
          'created_at': DateTime.now().toIso8601String(),
          'synced': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      AppLogger.info(_tag, 'Pending offline clock-in saved: $memberId in $sessionId');
    } catch (e) {
      AppLogger.error(_tag, 'Failed to save pending clock-in: $e', e, null);
    }
  }

  /// Get all pending (unsynced) clock-ins
  Future<List<Map<String, dynamic>>> getPendingClockIns() async {
    try {
      final db = await _getDb();
      return await db.query(
        'pending_clockins',
        where: 'synced = 0',
        orderBy: 'created_at ASC',
      );
    } catch (e) {
      AppLogger.error(_tag, 'Failed to query pending clock-ins: $e', e, null);
      return [];
    }
  }

  /// Mark a pending clock-in as synced
  Future<void> markAsSynced(String clockInId) async {
    try {
      final db = await _getDb();
      await db.update(
        'pending_clockins',
        {'synced': 1},
        where: 'id = ?',
        whereArgs: [clockInId],
      );
      AppLogger.info(_tag, 'Marked $clockInId as synced');
    } catch (e) {
      AppLogger.error(_tag, 'Failed to mark as synced: $e', e, null);
    }
  }

  /// Delete a pending clock-in (after successful sync or manual deletion)
  Future<void> deletePendingClockIn(String clockInId) async {
    try {
      final db = await _getDb();
      await db.delete(
        'pending_clockins',
        where: 'id = ?',
        whereArgs: [clockInId],
      );
      AppLogger.info(_tag, 'Deleted pending clock-in: $clockInId');
    } catch (e) {
      AppLogger.error(_tag, 'Failed to delete pending clock-in: $e', e, null);
    }
  }

  /// Clear all pending clock-ins
  Future<void> clearAllPending() async {
    try {
      final db = await _getDb();
      await db.delete('pending_clockins');
      AppLogger.info(_tag, 'All pending clock-ins cleared');
    } catch (e) {
      AppLogger.error(_tag, 'Failed to clear pending clock-ins: $e', e, null);
    }
  }

  /// Close database connection
  Future<void> close() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
    }
  }
}

// ---------------------------------------------------------------------------
// Utilities
// ---------------------------------------------------------------------------

Future<bool> isOnline() async {
  final connectivity = Connectivity();
  final result = await connectivity.checkConnectivity();
  // ConnectivityResult is used directly; none means no connection
  return !result.contains(ConnectivityResult.none);
}

Stream<bool> onConnectivityChanged() {
  return Connectivity()
      .onConnectivityChanged
      .map((result) => !result.contains(ConnectivityResult.none));
}
