// lib/features/sessions/session_detail_screen.dart
//
// Stitch UI redesign — Mirrors app/(dashboard)/sessions/[id]/page.tsx
//
// AppBar: back arrow, session name + date in title column, 3-dot menu.
// 3 stat cards (PRESENT / ABSENT / EXCUSED), filter chips,
// "MEMBERS (N)" row, member list with MemberAvatar + TeamBadge + StatusBadge,
// pinned bottom bar with "Finalize Absences" button.

import 'dart:async';

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
import '../../core/utils/date_utils.dart';

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
    FutureProvider.autoDispose.family<Session?, String>((ref, id) {
  return ref.read(sessionServiceProvider).getSessionById(id);
});

final _clockInsProvider =
    FutureProvider.autoDispose.family<List<ClockIn>, String>((ref, sessionId) {
  return ref.read(attendanceServiceProvider).getClockInsBySession(sessionId);
});

final _clockInsWithMembersProvider = FutureProvider.autoDispose
    .family<List<_ClockInEntry>, String>((ref, sessionId) async {
  final clockIns =
      await ref.read(attendanceServiceProvider).getClockInsBySession(sessionId);
  final members = await ref.read(memberServiceProvider).getMembers();
  final memberMap = {for (final m in members) m.id: m};
  return clockIns
      .map((c) => _ClockInEntry(clockIn: c, member: memberMap[c.memberId]))
      .toList();
});

final _sessionProgramProvider =
    FutureProvider.autoDispose.family<Program?, String>((ref, programId) {
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

class _SessionDetailScreenState extends ConsumerState<SessionDetailScreen> {
  // 'all' | 'present' | 'absent' | 'excused'
  String _statusFilter = 'all';
  bool _finalizing = false;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    // Refresh countdown display every 10 seconds if service is tooEarly
    _countdownTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _finalizeAbsences(Session session, Program? program) async {
    setState(() => _finalizing = true);
    try {
      await ref.read(attendanceServiceProvider).finalizeSessionAbsences(
            sessionId: widget.sessionId,
            sessionName: session.name,
            isSundayProgram: program?.programType == ProgramType.sunday ||
                _looksLikeSundayService(session.name),
          );
      ref.invalidate(_clockInsProvider(widget.sessionId));
      ref.invalidate(_clockInsWithMembersProvider(widget.sessionId));
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
          const SnackBar(
            content: Text('Unable to finalize absences. Please try again.'),
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

  /// Upgrades an absent member to excused after staff confirmation.
  /// Only callable on absent clock-ins (terminal status guard is in the service).
  Future<void> _markAsExcused(BuildContext context, _ClockInEntry entry) async {
    final memberName = entry.member?.fullName ?? entry.clockIn.memberId;
    final messenger = ScaffoldMessenger.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark as Excused'),
        content: Text(
            'Mark $memberName as excused for this session?\n\nThis cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: AppTheme.amber, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Mark Excused'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      await ref.read(attendanceServiceProvider).clockInMember(
            sessionId: widget.sessionId,
            memberId: entry.clockIn.memberId,
            status: AttendanceStatus.excused,
            method: ClockInMethod.manual,
          );
      ref.invalidate(_clockInsProvider(widget.sessionId));
      ref.invalidate(_clockInsWithMembersProvider(widget.sessionId));
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('$memberName marked as excused.'),
            backgroundColor: AppTheme.amber,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  /// Prompts the user to update the "new guests" count for this session.
  Future<void> _editNewGuestCount(BuildContext context, Session session) async {
    final controller =
        TextEditingController(text: session.newGuestCount.toString());
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Guests'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'New guest count',
            hintText: 'Enter number of guests',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primary,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final raw = controller.text.trim();
    final value = int.tryParse(raw);
    if (value == null || value < 0) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid non-negative number.'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    try {
      await ref.read(sessionServiceProvider).updateSession(
            session.id,
            newGuestCount: value,
          );
      ref.invalidate(_sessionDetailProvider(widget.sessionId));
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('New guest count updated to $value.'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  // ── Gate State Helpers ────────────────────────────────────────────────

  Widget _buildQRButton(Session session) {
    final now = nowInLagos();
    final todayISO = formatDateISO(now);
    final isToday = session.date == todayISO;

    if (!isToday) {
      // Past or future session - disable button
      return const Tooltip(
        message: 'Check-in only available on session date',
        child: IconButton(
          icon: Icon(Icons.qr_code_scanner),
          onPressed: null, // disabled
        ),
      );
    }

    final gate = sessionGateState(session.startTime, session.endTime, now);

    switch (gate) {
      case SessionGateState.open:
      case SessionGateState.noGate:
        // Service is open or has no time gate
        return IconButton(
          icon: const Icon(Icons.qr_code_scanner),
          tooltip: 'Start Check-in',
          onPressed: () =>
              context.push('/sessions/${widget.sessionId}/checkin'),
        );
      case SessionGateState.tooEarly:
        final ms = msUntilTime(session.startTime!, now);
        final countdown = msToCountdown(ms);
        return Tooltip(
          message: countdown,
          child: const IconButton(
            icon: Icon(Icons.qr_code_scanner),
            onPressed: null, // disabled - service not open yet
          ),
        );
      case SessionGateState.closed:
        return const Tooltip(
          message: 'Check-in is closed',
          child: IconButton(
            icon: Icon(Icons.qr_code_scanner),
            onPressed: null, // disabled - service is closed
          ),
        );
    }
  }

  Widget _buildGateBanner(Session session) {
    final now = nowInLagos();
    final todayISO = formatDateISO(now);
    final isToday = session.date == todayISO;

    if (!isToday || session.startTime == null) {
      return const SizedBox.shrink(); // No banner needed
    }

    final gate = sessionGateState(session.startTime, session.endTime, now);

    switch (gate) {
      case SessionGateState.open:
      case SessionGateState.noGate:
        return const SizedBox.shrink(); // No banner when open
      case SessionGateState.tooEarly:
        final ms = msUntilTime(session.startTime!, now);
        final countdown = msToCountdown(ms);
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.amberBg,
            border: Border.all(color: AppTheme.amber),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(Icons.schedule, size: 18, color: AppTheme.amber),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Service Not Open Yet',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: AppTheme.amber,
                      ),
                    ),
                    Text(
                      countdown,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.amber,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      case SessionGateState.closed:
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(
            color: AppTheme.errorBg,
            border: Border(
              top: BorderSide(color: AppTheme.error),
              bottom: BorderSide(color: AppTheme.error),
              left: BorderSide(color: AppTheme.error),
              right: BorderSide(color: AppTheme.error),
            ),
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
          child: const Row(
            children: [
              Icon(Icons.lock, size: 18, color: AppTheme.error),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Check-in is now closed',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: AppTheme.error,
                  ),
                ),
              ),
            ],
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessionAsync = ref.watch(_sessionDetailProvider(widget.sessionId));
    final entriesAsync =
        ref.watch(_clockInsWithMembersProvider(widget.sessionId));

    return sessionAsync.when(
      loading: () => Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
            leading: BackButton(onPressed: () => context.go('/sessions'))),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
            leading: BackButton(onPressed: () => context.go('/sessions'))),
        body: Center(child: Text('Error: $e')),
      ),
      data: (session) {
        if (session == null) {
          return Scaffold(
            backgroundColor: AppTheme.background,
            appBar: AppBar(
                leading: BackButton(onPressed: () => context.go('/sessions'))),
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
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            Text(
              session.date,
              style: const TextStyle(fontSize: 12, color: AppTheme.slate500),
            ),
          ],
        ),
        actions: [
          _buildQRButton(session),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ── Service Gate Status (countdown or closed) ─────
            _buildGateBanner(session),

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

            // ── New guest count (editable) ──────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'New guests: ${session.newGuestCount}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.slate500,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit, size: 20),
                    tooltip: 'Edit new guest count',
                    onPressed: () => _editNewGuestCount(context, session),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // ── Filter chips ───────────────────────────────────────────
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _StatusFilterChip(
                    label: 'All',
                    selected: _statusFilter == 'all',
                    onTap: () => setState(() => _statusFilter = 'all'),
                  ),
                  const SizedBox(width: 8),
                  _StatusFilterChip(
                    label: 'Present',
                    selected: _statusFilter == 'present',
                    onTap: () => setState(() => _statusFilter = 'present'),
                  ),
                  const SizedBox(width: 8),
                  _StatusFilterChip(
                    label: 'Absent',
                    selected: _statusFilter == 'absent',
                    onTap: () => setState(() => _statusFilter = 'absent'),
                  ),
                  const SizedBox(width: 8),
                  _StatusFilterChip(
                    label: 'Excused',
                    selected: _statusFilter == 'excused',
                    onTap: () => setState(() => _statusFilter = 'excused'),
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
                  const Icon(Icons.sort, size: 18, color: AppTheme.slate500),
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
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (ctx, i) {
                            final entry = filtered[i];
                            final member = entry.member;
                            final clockIn = entry.clockIn;
                            final timeStr =
                                '${clockIn.clockedAt.hour.toString().padLeft(2, '0')}:${clockIn.clockedAt.minute.toString().padLeft(2, '0')}';
                            final isAbsent =
                                clockIn.status == AttendanceStatus.absent;
                            return GestureDetector(
                              onLongPress: isAbsent
                                  ? () => _markAsExcused(ctx, entry)
                                  : null,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 12),
                                decoration: BoxDecoration(
                                  color: AppTheme.surface,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AppTheme.slate200),
                                ),
                                child: Row(
                                  children: [
                                    MemberAvatar(
                                      fullName: member?.fullName ?? '?',
                                      imageUrl: member?.photoUrl,
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
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          if (member != null)
                                            TeamBadge(team: member.team),
                                          if (clockIn.positionLabel != null &&
                                              clockIn.positionLabel!
                                                  .isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(
                                                  Icons.place_outlined,
                                                  size: 12,
                                                  color: AppTheme.primary,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  'Position ${clockIn.positionLabel}',
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w700,
                                                    color: AppTheme.primary,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                          if (isAbsent) ...[
                                            const SizedBox(height: 4),
                                            const Text(
                                              'Hold to excuse',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: AppTheme.amber,
                                              ),
                                            ),
                                          ],
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
                border: Border(top: BorderSide(color: AppTheme.slate200)),
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
                                  strokeWidth: 2, color: Colors.white),
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
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
