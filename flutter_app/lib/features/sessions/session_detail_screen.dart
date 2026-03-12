// lib/features/sessions/session_detail_screen.dart
//
// Stitch UI redesign — Mirrors app/(dashboard)/sessions/[id]/page.tsx
//
// AppBar: back arrow, session name + date in title column, 3-dot menu.
// 3 stat cards (PRESENT / ABSENT / EXCUSED), filter chips,
// "MEMBERS (N)" row, member list with MemberAvatar + TeamBadge + StatusBadge,
// pinned bottom bar with "Finalize Absences" button.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/session.dart';
import '../../models/clock_in.dart';
import '../../models/member.dart';
import '../../models/enums.dart';
import '../../models/program.dart';
import '../../services/session_service.dart';
import '../../services/attendance_service.dart';
import '../../services/member_service.dart';
import '../../services/program_service.dart';
import '../../app_theme/app_theme.dart';
import '../../widgets/team_badge.dart';
import '../../widgets/status_badge.dart';
import '../../widgets/avatar_widget.dart';

// ---------------------------------------------------------------------------
// Data class
// ---------------------------------------------------------------------------

class _ClockInEntry {
  const _ClockInEntry({required this.clockIn, required this.member});
  final ClockIn clockIn;
  final Member? member;
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final _sessionDetailProvider =
    FutureProvider.family<Session?, String>((ref, id) {
  return ref.read(sessionServiceProvider).getSessionById(id);
});

final _clockInsProvider =
    FutureProvider.family<List<ClockIn>, String>((ref, sessionId) {
  return ref.read(attendanceServiceProvider).getClockInsBySession(sessionId);
});

final _clockInsWithMembersProvider =
    FutureProvider.family<List<_ClockInEntry>, String>(
        (ref, sessionId) async {
  final clockIns =
      await ref.read(attendanceServiceProvider).getClockInsBySession(sessionId);
  final members = await ref.read(memberServiceProvider).getMembers();
  final memberMap = {for (final m in members) m.id: m};
  return clockIns
      .map((c) =>
          _ClockInEntry(clockIn: c, member: memberMap[c.memberId]))
      .toList();
});

final _sessionProgramProvider =
    FutureProvider.family<Program?, String>((ref, programId) {
  return ref.read(programServiceProvider).getProgramById(programId);
});

// ---------------------------------------------------------------------------
// SessionDetailScreen
// ---------------------------------------------------------------------------

class SessionDetailScreen extends ConsumerStatefulWidget {
  const SessionDetailScreen({super.key, required this.sessionId});
  final String sessionId;

  @override
  ConsumerState<SessionDetailScreen> createState() =>
      _SessionDetailScreenState();
}

class _SessionDetailScreenState
    extends ConsumerState<SessionDetailScreen> {
  // 'all' | 'present' | 'absent' | 'excused'
  String _statusFilter = 'all';
  bool _finalizing = false;

  Future<void> _finalizeAbsences(
      Session session, Program? program) async {
    setState(() => _finalizing = true);
    try {
      await ref
          .read(attendanceServiceProvider)
          .finalizeSessionAbsences(
            sessionId: widget.sessionId,
            sessionName: session.name,
            isSundayProgram: program?.programType == ProgramType.sunday ||
                _looksLikeSundayService(session.name),
          );
      ref.invalidate(_clockInsProvider(widget.sessionId));
      ref.invalidate(
          _clockInsWithMembersProvider(widget.sessionId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Absences finalized.'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _finalizing = false);
    }
  }

  /// Mirrors React's isSundaySession name-based fallback:
  /// a session qualifies as a Sunday service even when its program type
  /// is not explicitly 'sunday' (e.g. legacy data).
  bool _looksLikeSundayService(String name) {
    final n = name.toLowerCase();
    return n.contains('service 1') ||
        n.contains('first') ||
        n.contains('service 2') ||
        n.contains('second') ||
        n.contains('service 3') ||
        n.contains('third');
  }

  @override
  Widget build(BuildContext context) {
    final sessionAsync =
        ref.watch(_sessionDetailProvider(widget.sessionId));
    final entriesAsync =
        ref.watch(_clockInsWithMembersProvider(widget.sessionId));

    return sessionAsync.when(
      loading: () => Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
            leading: BackButton(
                onPressed: () => context.go('/sessions'))),
        body:
            const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
            leading: BackButton(
                onPressed: () => context.go('/sessions'))),
        body: Center(child: Text('Error: $e')),
      ),
      data: (session) {
        if (session == null) {
          return Scaffold(
            backgroundColor: AppTheme.background,
            appBar: AppBar(
                leading: BackButton(
                    onPressed: () => context.go('/sessions'))),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Session not found.'),
                  TextButton(
                      onPressed: () => context.go('/sessions'),
                      child: const Text('Go back')),
                ],
              ),
            ),
          );
        }

        final programAsync =
            ref.watch(_sessionProgramProvider(session.programId));
        final program = programAsync.valueOrNull;

        return entriesAsync.when(
          loading: () => _buildScaffold(
              session: session,
              program: program,
              entries: const [],
              loading: true),
          error: (e, _) => _buildScaffold(
              session: session,
              program: program,
              entries: const [],
              loading: false),
          data: (entries) => _buildScaffold(
              session: session,
              program: program,
              entries: entries,
              loading: false),
        );
      },
    );
  }

  Widget _buildScaffold({
    required Session session,
    required Program? program,
    required List<_ClockInEntry> entries,
    required bool loading,
  }) {
    final presentCount = entries
        .where((e) => e.clockIn.status == AttendanceStatus.present)
        .length;
    final absentCount = entries
        .where((e) => e.clockIn.status == AttendanceStatus.absent)
        .length;
    final excusedCount = entries
        .where((e) => e.clockIn.status == AttendanceStatus.excused)
        .length;

    List<_ClockInEntry> filtered;
    if (_statusFilter == 'present') {
      filtered = entries
          .where((e) => e.clockIn.status == AttendanceStatus.present)
          .toList();
    } else if (_statusFilter == 'absent') {
      filtered = entries
          .where((e) => e.clockIn.status == AttendanceStatus.absent)
          .toList();
    } else if (_statusFilter == 'excused') {
      filtered = entries
          .where((e) => e.clockIn.status == AttendanceStatus.excused)
          .toList();
    } else {
      filtered = entries;
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        leading: BackButton(onPressed: () => context.go('/sessions')),
        centerTitle: true,
        title: Column(
          children: [
            Text(
              session.name,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700),
            ),
            Text(
              session.date,
              style: const TextStyle(
                  fontSize: 12, color: AppTheme.slate500),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Start Check-in',
            onPressed: () =>
                context.push('/sessions/${widget.sessionId}/checkin'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ── 3 Stat cards ───────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      value: presentCount,
                      label: 'PRESENT',
                      bg: AppTheme.successBg,
                      valueColor: AppTheme.success,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _StatCard(
                      value: absentCount,
                      label: 'ABSENT',
                      bg: AppTheme.errorBg,
                      valueColor: AppTheme.error,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _StatCard(
                      value: excusedCount,
                      label: 'EXCUSED',
                      bg: AppTheme.amberBg,
                      valueColor: AppTheme.amber,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ── Filter chips ───────────────────────────────────────────
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _StatusFilterChip(
                    label: 'All',
                    selected: _statusFilter == 'all',
                    onTap: () =>
                        setState(() => _statusFilter = 'all'),
                  ),
                  const SizedBox(width: 8),
                  _StatusFilterChip(
                    label: 'Present',
                    selected: _statusFilter == 'present',
                    onTap: () =>
                        setState(() => _statusFilter = 'present'),
                  ),
                  const SizedBox(width: 8),
                  _StatusFilterChip(
                    label: 'Absent',
                    selected: _statusFilter == 'absent',
                    onTap: () =>
                        setState(() => _statusFilter = 'absent'),
                  ),
                  const SizedBox(width: 8),
                  _StatusFilterChip(
                    label: 'Excused',
                    selected: _statusFilter == 'excused',
                    onTap: () =>
                        setState(() => _statusFilter = 'excused'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ── "MEMBERS (N)" header ────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    'MEMBERS (${filtered.length})',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.slate500,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const Spacer(),
                  const Icon(Icons.sort,
                      size: 18, color: AppTheme.slate500),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // ── Member list ────────────────────────────────────────────
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                      ? const Center(
                          child: Text(
                            'No members match this filter.',
                            style: TextStyle(color: AppTheme.slate500),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(
                              16, 0, 16, 8),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (ctx, i) {
                            final entry = filtered[i];
                            final member = entry.member;
                            final clockIn = entry.clockIn;
                            final timeStr =
                                '${clockIn.clockedAt.hour.toString().padLeft(2, '0')}:${clockIn.clockedAt.minute.toString().padLeft(2, '0')}';
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 12),
                              decoration: BoxDecoration(
                                color: AppTheme.surface,
                                borderRadius:
                                    BorderRadius.circular(12),
                                border: Border.all(
                                    color: AppTheme.slate200),
                              ),
                              child: Row(
                                children: [
                                  MemberAvatar(
                                    fullName:
                                        member?.fullName ?? '?',
                                    radius: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          member?.fullName ??
                                              clockIn.memberId,
                                          style: const TextStyle(
                                            fontWeight:
                                                FontWeight.w700,
                                            fontSize: 14,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        if (member != null)
                                          TeamBadge(
                                              team: member.team),
                                      ],
                                    ),
                                  ),
                                  StatusBadge(
                                    status: clockIn.status,
                                    clockedAt: clockIn.status ==
                                            AttendanceStatus.present
                                        ? timeStr
                                        : null,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
            ),

            // ── Bottom pinned bar ──────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: const BoxDecoration(
                color: AppTheme.surface,
                border: Border(
                    top: BorderSide(color: AppTheme.slate200)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppTheme.amber,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Session in Progress  ·  $absentCount member${absentCount == 1 ? '' : 's'} haven\'t checked in yet',
                          style: const TextStyle(
                              fontSize: 12, color: AppTheme.slate500),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _finalizing
                          ? null
                          : () => _finalizeAbsences(session, program),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.amber,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 48),
                      ),
                      child: _finalizing
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white),
                            )
                          : const Text('Finalize Absences'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _StatCard
// ---------------------------------------------------------------------------

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.value,
    required this.label,
    required this.bg,
    required this.valueColor,
  });
  final int value;
  final String label;
  final Color bg;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            '$value',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: valueColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppTheme.slate500,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _StatusFilterChip
// ---------------------------------------------------------------------------

class _StatusFilterChip extends StatelessWidget {
  const _StatusFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppTheme.primary : AppTheme.slate200,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppTheme.slate500,
          ),
        ),
      ),
    );
  }
}
