// lib/services/attendance_service.dart
//
// Dart equivalent of lib/core/clockins.ts — the most critical service.
//
// Preserves the full attendance state machine:
//   absent  → present/excused  (upgrade)
//   present/excused → LOCKED   (immutable)
//
// Business rules from clockInByOfflineCode:
//   - 'absent' cannot be set via offline_code
//
// Business rule from finalizeSessionAbsences:
//   - Sunday sessions scope to the expected team per service name
//   - All other sessions scope to ALL members

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:uuid/uuid.dart';

import '../models/clock_in.dart';
import '../models/follow_up_action.dart';
import '../models/member.dart';
import '../models/enums.dart';
import '../core/logger.dart';
import 'member_service.dart';
import 'offline_sync_service.dart';

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final attendanceServiceProvider = Provider<AttendanceService>(
  (ref) => AttendanceService(
    Supabase.instance.client,
    ref.read(memberServiceProvider),
  ),
);

// ---------------------------------------------------------------------------
// AttendanceService
// ---------------------------------------------------------------------------

class AttendanceService {
  AttendanceService(this._client, this._memberService);

  final SupabaseClient _client;
  final MemberService _memberService;

  static const _table = 'clock_ins';
  static const _followUpActionsTable = 'member_follow_up_actions';
  static const _tag = 'AttendanceService';

  // ── Read ──────────────────────────────────────────────────────────────────

  Future<List<ClockIn>> getClockInsBySession(String sessionId) async {
    AppLogger.info(_tag, 'getClockInsBySession($sessionId)');
    try {
      final data = await _client
          .from(_table)
          .select()
          .eq('session_id', sessionId);
      final list = (data as List).map((e) => ClockIn.fromJson(e)).toList();
      AppLogger.info(_tag, 'getClockInsBySession($sessionId) → ${list.length} records');
      return list;
    } catch (e, stack) {
      AppLogger.error(_tag, 'getClockInsBySession($sessionId) failed', e, stack);
      rethrow;
    }
  }

  Future<int> getClockInCountBySession(String sessionId) async {
    try {
      final data = await _client
          .from(_table)
          .select('id')
          .eq('session_id', sessionId);
      final count = (data as List).length;
      AppLogger.debug(_tag, 'getClockInCountBySession($sessionId) → $count');
      return count;
    } catch (e, stack) {
      AppLogger.error(_tag, 'getClockInCountBySession($sessionId) failed', e, stack);
      rethrow;
    }
  }

  Future<ClockIn?> _findExisting(
      String sessionId, String memberId) async {
    final data = await _client
        .from(_table)
        .select()
        .eq('session_id', sessionId)
        .eq('member_id', memberId)
        .maybeSingle();
    return data == null ? null : ClockIn.fromJson(data);
  }

  // ── Core write — clockInMember ────────────────────────────────────────────
  //
  // Direct translation of the TypeScript clockInMember() state machine.
  //
  // Outcomes:
  //   ┌─ Existing = present/excused ──▶ throws 'Already marked'
  //   ├─ Existing = absent           ──▶ UPDATE to new status (upgrade)
  //   └─ No existing                 ──▶ INSERT new record

  Future<ClockIn> clockInMember({
    required String sessionId,
    required String memberId,
    AttendanceStatus status = AttendanceStatus.present,
    ClockInMethod method = ClockInMethod.offlineCode,
  }) async {
    AppLogger.info(
      _tag,
      'clockInMember(session=$sessionId, member=$memberId, status=${status.value})',
    );
    try {
      final existing = await _findExisting(sessionId, memberId);

      if (existing != null) {
        if (existing.status.isTerminal) {
          AppLogger.warn(
            _tag,
            'clockInMember → member $memberId already ${existing.status.value} (terminal)',
          );
          throw Exception('Already marked');
        }

        // Upgrade absent → present/excused
        AppLogger.info(
          _tag,
          'clockInMember → upgrading member $memberId: absent → ${status.value}',
        );
        final now = DateTime.now().toIso8601String();
        await _client.from(_table).update({
          'status': status.value,
          'method': method.value,
          'clocked_at': now,
        }).eq('id', existing.id);

        AppLogger.info(_tag, 'clockInMember → upgrade ok (id: ${existing.id})');
        return existing.copyWith(
          status: status,
          method: method,
          clockedAt: DateTime.parse(now),
        );
      }

      // New record
      AppLogger.info(_tag, 'clockInMember → inserting new record for member $memberId');
      final insert = {
        'session_id': sessionId,
        'member_id': memberId,
        'status': status.value,
        'method': method.value,
        'clocked_at': DateTime.now().toIso8601String(),
      };
      final data =
          await _client.from(_table).insert(insert).select().single();
      final clockIn = ClockIn.fromJson(data);
      AppLogger.info(_tag, 'clockInMember → inserted (id: ${clockIn.id})');
      return clockIn;
    } catch (e, stack) {
      // Don't log "Already marked" as an error — it's an expected business rule
      if (e.toString().contains('Already marked')) rethrow;
      AppLogger.error(
        _tag,
        'clockInMember(session=$sessionId, member=$memberId) failed',
        e,
        stack,
      );
      rethrow;
    }
  }

  // ── clockInByOfflineCode ──────────────────────────────────────────────────
  //
  // Direct translation of the TypeScript clockInByOfflineCode().
  //
  // Rules:
  //   - Resolves member by 6-digit code
  //   - Only 'present' and 'excused' are allowed (never 'absent' via code)

  Future<ClockIn> clockInByOfflineCode({
    required String sessionId,
    required String code,
    AttendanceStatus status = AttendanceStatus.present,
  }) async {
    AppLogger.info(_tag, 'clockInByOfflineCode(session=$sessionId, code=$code)');

    if (status == AttendanceStatus.absent) {
      AppLogger.warn(_tag, 'clockInByOfflineCode → rejected: absent status via code');
      throw Exception(
          "This status cannot be used with the offline code.");
    }

    final member = await _memberService.getMemberByOfflineCode(code);
    if (member == null) {
      AppLogger.warn(_tag, 'clockInByOfflineCode → member not found for code $code');
      throw Exception('The code entered does not match any member. Please check and try again.');
    }

    AppLogger.info(_tag, 'clockInByOfflineCode → resolved member: "${member.fullName}"');
    return clockInMember(
      sessionId: sessionId,
      memberId: member.id,
      status: status,
      method: ClockInMethod.offlineCode,
    );
  }

  // ── finalizeSessionAbsences ───────────────────────────────────────────────
  //
  // Batch-marks all expected members who were NOT clocked in as 'absent'.
  //
  // Sunday session scoping (mirrors TypeScript inferSundayServiceTeam):
  //   "service 1" / "first"  → Team A
  //   "service 2" / "second" → Team B
  //   "service 3" / "third"  → Team C
  //
  // All other sessions → ALL members.

  Future<void> finalizeSessionAbsences({
    required String sessionId,
    required String sessionName,
    required bool isSundayProgram,
  }) async {
    AppLogger.info(
      _tag,
      'finalizeSessionAbsences(session=$sessionId, name="$sessionName", sunday=$isSundayProgram)',
    );
    try {
      final allMembers = await _memberService.getMembers();
      final existingClockIns = await getClockInsBySession(sessionId);

      // Members already marked as present or excused
      final markedIds = existingClockIns
          .where((c) => c.status.isTerminal)
          .map((c) => c.memberId)
          .toSet();

      // Members already in the clock_ins table (any status)
      final anyMarkedIds =
          existingClockIns.map((c) => c.memberId).toSet();

      // Determine team scope for Sunday sessions
      final expectedTeam = isSundayProgram
          ? _inferSundayServiceTeam(sessionName)
          : null;

      AppLogger.debug(
        _tag,
        'finalizeSessionAbsences → scope: ${expectedTeam?.value ?? 'all members'}',
      );

      List<Member> expectedMembers;
      if (isSundayProgram && expectedTeam != null) {
        expectedMembers =
            allMembers.where((m) => m.team == expectedTeam).toList();
      } else {
        expectedMembers = allMembers;
      }

      // Build absent records for everyone not yet in the table
      final toInsert = expectedMembers
          .where((m) => !markedIds.contains(m.id) && !anyMarkedIds.contains(m.id))
          .map((m) => {
                'session_id': sessionId,
                'member_id': m.id,
                'status': AttendanceStatus.absent.value,
                'method': ClockInMethod.manual.value,
                'clocked_at': DateTime.now().toIso8601String(),
              })
          .toList();

      if (toInsert.isEmpty) {
        AppLogger.info(_tag, 'finalizeSessionAbsences → nothing to insert (all accounted for)');
        return;
      }

      AppLogger.info(_tag, 'finalizeSessionAbsences → inserting ${toInsert.length} absent records');
      await _client.from(_table).insert(toInsert);
      AppLogger.info(_tag, 'finalizeSessionAbsences → done');
    } catch (e, stack) {
      AppLogger.error(_tag, 'finalizeSessionAbsences($sessionId) failed', e, stack);
      rethrow;
    }
  }

  /// Returns members who have zero `present` OR `excused` clock-ins across all
  /// Sunday sessions since [sinceDate] (format: "YYYY-MM-DD").
  /// Excused members are excluded because they are accounted for; only truly
  /// unaccounted absences trigger follow-up.
  /// Used for the "follow-up needed" section on the home screen.
  Future<List<Member>> getAbsentMembersSince(String sinceDate) async {
    AppLogger.info(_tag, 'getAbsentMembersSince($sinceDate)');
    try {
      final sessionIds = await _getSundaySessionIds(sinceDate: sinceDate);

      if (sessionIds.isEmpty) {
        AppLogger.info(_tag, 'getAbsentMembersSince → no Sunday sessions found since $sinceDate');
        return [];
      }

      // Get all members
      final allMembers = await _memberService.getMembers();

      // Get member IDs who have at least one `present` or `excused` clock-in.
      // Excused members are accounted for and should not appear in follow-up.
      final clockInsData = await _client
          .from('clock_ins')
          .select('member_id')
          .inFilter('session_id', sessionIds)
          .inFilter('status', ['present', 'excused']);
      final accountedMemberIds = (clockInsData as List)
          .map((c) => c['member_id'] as String)
          .toSet();

      // Members with no present/excused record in those sessions
      final absent = allMembers
          .where((m) => m.team != Team.none && !accountedMemberIds.contains(m.id))
          .toList();
      AppLogger.info(_tag, 'getAbsentMembersSince → ${absent.length} unaccounted members');
      return absent;
    } catch (e, s) {
      AppLogger.error(_tag, 'getAbsentMembersSince($sinceDate) failed', e, s);
      rethrow;
    }
  }

  /// Returns members who still need follow-up after excluding members whose
  /// current absence streak has already been marked as contacted by staff.
  Future<List<Member>> getActiveAbsentMembersSince(String sinceDate) async {
    AppLogger.info(_tag, 'getActiveAbsentMembersSince($sinceDate)');
    try {
      final absentMembers = await getAbsentMembersSince(sinceDate);
      if (absentMembers.isEmpty) {
        return [];
      }

      final latestActions =
          await _getLatestFollowUpActions(absentMembers.map((m) => m.id).toList());
      if (latestActions.isEmpty) {
        AppLogger.info(_tag, 'getActiveAbsentMembersSince → no follow-up actions yet');
        return absentMembers;
      }

      final sundaySessionIds = await _getSundaySessionIds();
      final accountedAfterAction = await _getLatestAccountedSundayClockIns(
        memberIds: latestActions.keys.toList(),
        sundaySessionIds: sundaySessionIds,
      );

      final active = absentMembers.where((member) {
        final latestAction = latestActions[member.id];
        if (latestAction == null) return true;

        final latestAttendance = accountedAfterAction[member.id];
        if (latestAttendance == null) {
          return false;
        }

        return latestAttendance.isAfter(latestAction.createdAt);
      }).toList();

      AppLogger.info(
        _tag,
        'getActiveAbsentMembersSince → ${active.length} active follow-up members',
      );
      return active;
    } catch (e, s) {
      AppLogger.error(_tag, 'getActiveAbsentMembersSince($sinceDate) failed', e, s);
      rethrow;
    }
  }

  /// Records that staff contacted a member and dismissed the current follow-up.
  /// The member stays hidden until they attend a Sunday session again.
  Future<void> markFollowUpContacted({
    required String memberId,
    required String staffId,
    String? note,
  }) async {
    AppLogger.info(
      _tag,
      'markFollowUpContacted(member=$memberId, staff=$staffId)',
    );
    try {
      await _client.from(_followUpActionsTable).insert({
        'member_id': memberId,
        'action': 'contacted',
        'created_by_staff_id': staffId,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      });
      AppLogger.info(_tag, 'markFollowUpContacted → action saved');
    } catch (e, s) {
      AppLogger.error(_tag, 'markFollowUpContacted failed', e, s);
      rethrow;
    }
  }

  /// Returns all clock-ins for a member, most recent first.
  /// Used on the Member Detail screen to show attendance history.
  Future<List<ClockIn>> getClockInsByMember(String memberId,
      {int limit = 20}) async {
    AppLogger.info(_tag, 'getClockInsByMember($memberId)');
    try {
      final data = await _client
          .from(_table)
          .select()
          .eq('member_id', memberId)
          .order('clocked_at', ascending: false)
          .limit(limit);
      final list = (data as List).map((e) => ClockIn.fromJson(e)).toList();
      AppLogger.info(
          _tag, 'getClockInsByMember($memberId) → ${list.length} records');
      return list;
    } catch (e, stack) {
      AppLogger.error(
          _tag, 'getClockInsByMember($memberId) failed', e, stack);
      rethrow;
    }
  }

  /// Clears ALL clock-ins for a session. Use with caution (admin only).
  Future<void> clearSessionClockIns(String sessionId) async {
    AppLogger.warn(_tag, 'clearSessionClockIns($sessionId) — DESTRUCTIVE');
    try {
      await _client.from(_table).delete().eq('session_id', sessionId);
      AppLogger.info(_tag, 'clearSessionClockIns($sessionId) → ok');
    } catch (e, stack) {
      AppLogger.error(_tag, 'clearSessionClockIns($sessionId) failed', e, stack);
      rethrow;
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Infers which team is expected for a Sunday service session.
  /// Mirrors inferSundayServiceTeam() in clockins.ts.
  Team? _inferSundayServiceTeam(String sessionName) {
    final n = sessionName.toLowerCase();
    if (n.contains('service 1') || n.contains('first')) return Team.teamA;
    if (n.contains('service 2') || n.contains('second')) return Team.teamB;
    if (n.contains('service 3') || n.contains('third')) return Team.teamC;
    return null;
  }

  Future<List<String>> _getSundaySessionIds({String? sinceDate}) async {
    final query = _client
        .from('sessions')
        .select('id')
        .or('name.ilike.%Service 1%,name.ilike.%Service 2%,name.ilike.%Service 3%');

    final data = sinceDate == null ? await query : await query.gte('date', sinceDate);
    return (data as List).map((s) => s['id'] as String).toList();
  }

  Future<Map<String, FollowUpAction>> _getLatestFollowUpActions(
    List<String> memberIds,
  ) async {
    if (memberIds.isEmpty) return <String, FollowUpAction>{};

    final data = await _client
        .from(_followUpActionsTable)
        .select()
        .inFilter('member_id', memberIds)
        .order('created_at', ascending: false);

    final latest = <String, FollowUpAction>{};
    for (final row in data as List) {
      final action = FollowUpAction.fromJson(row as Map<String, dynamic>);
      latest.putIfAbsent(action.memberId, () => action);
    }
    return latest;
  }

  Future<Map<String, DateTime>> _getLatestAccountedSundayClockIns({
    required List<String> memberIds,
    required List<String> sundaySessionIds,
  }) async {
    if (memberIds.isEmpty || sundaySessionIds.isEmpty) {
      return <String, DateTime>{};
    }

    final data = await _client
        .from(_table)
        .select('member_id, clocked_at')
        .inFilter('member_id', memberIds)
        .inFilter('session_id', sundaySessionIds)
        .inFilter('status', ['present', 'excused'])
        .order('clocked_at', ascending: false);

    final latest = <String, DateTime>{};
    for (final row in data as List) {
      final map = row as Map<String, dynamic>;
      final memberId = map['member_id'] as String;
      latest.putIfAbsent(
        memberId,
        () => DateTime.parse(map['clocked_at'] as String),
      );
    }
    return latest;
  }

  // ── Offline Support ───────────────────────────────────────────────────────────

  /// Clock in by offline code with offline fallback support.
  /// If offline, saves to local database and syncs when connection restored.
  Future<ClockIn> clockInByOfflineCodeWithOfflineSupport({
    required String sessionId,
    required String code,
    required OfflineSyncService offlineService,
    AttendanceStatus status = AttendanceStatus.present,
  }) async {
    AppLogger.info(
      _tag,
      'clockInByOfflineCodeWithOfflineSupport(session=$sessionId, code=$code)',
    );

    // Check connectivity
    final connectivity = await _isOnline();

    if (!connectivity) {
      // Offline: save locally and return a pending record
      AppLogger.warn(_tag, 'Offline — saving attendance locally');
      try {
        final member = await _memberService.getMemberByOfflineCode(code);
        if (member == null) {
          throw Exception('The code entered does not match any member. Please check and try again.');
        }

        final now = DateTime.now();
        final id = const Uuid().v4();
        await offlineService.addPendingClockIn(
          id: id,
          sessionId: sessionId,
          memberId: member.id,
          status: status,
          method: ClockInMethod.offlineCode,
          clockedAt: now,
        );

        // Return a pending clock-in record locally
        return ClockIn(
          id: id,
          sessionId: sessionId,
          memberId: member.id,
          status: status,
          method: ClockInMethod.offlineCode,
          clockedAt: now,
        );
      } catch (e) {
        AppLogger.error(_tag, 'Offline save failed: $e', e, null);
        rethrow;
      }
    }

    // Online: use normal flow
    return clockInByOfflineCode(
      sessionId: sessionId,
      code: code,
      status: status,
    );
  }

  /// Check online status
  Future<bool> _isOnline() async {
    try {
      final connectivity = await Connectivity().checkConnectivity();
      return !connectivity.contains(ConnectivityResult.none);
    } catch (e) {
      AppLogger.warn(_tag, 'Connectivity check failed: $e');
      return true; // Assume online on error
    }
  }
}

