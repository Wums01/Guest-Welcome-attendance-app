import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;
import 'package:url_launcher/url_launcher.dart';

import '../../models/member.dart';
import '../../models/session.dart';
import '../../services/member_service.dart';
import '../../services/session_service.dart';
import '../../core/utils/date_utils.dart';
import '../../app_theme/app_theme.dart';
import '../../widgets/avatar_widget.dart';
import '../../widgets/team_badge.dart';
import '../../core/notifications.dart';
import '../../services/attendance_service.dart';
import '../../providers/auth_provider.dart';

// ── Providers ────────────────────────────────────────────────────────────────

final _membersProvider = FutureProvider<List<Member>>((ref) {
  return ref.read(memberServiceProvider).getMembers();
});

final _todaySessionsProvider = FutureProvider<List<Session>>((ref) {
  final today = formatDateISO(nowInLagos());
  return ref.read(sessionServiceProvider).getSessionsByDate(today);
});

/// Picks the best "upcoming" session for today:
/// 1. Currently open/no-gate session wins
/// 2. Falls back to earliest tooEarly session
/// 3. Returns null when all sessions are closed (or no sessions)
final _upcomingSessionProvider = FutureProvider<Session?>((ref) async {
  final today = formatDateISO(nowInLagos());
  final sessions =
      await ref.read(sessionServiceProvider).getSessionsByDate(today);
  if (sessions.isEmpty) return null;
  final now = nowInLagos();
  final open = sessions.where((s) {
    final g = sessionGateState(s.startTime, s.endTime, now);
    return g == SessionGateState.open || g == SessionGateState.noGate;
  }).toList();
  if (open.isNotEmpty) return open.first;
  final soon = sessions
      .where((s) =>
          sessionGateState(s.startTime, s.endTime, now) ==
          SessionGateState.tooEarly)
      .toList()
    ..sort((a, b) => (a.startTime ?? '').compareTo(b.startTime ?? ''));
  return soon.isEmpty ? null : soon.first;
});

// Absence follow-up: members with no Sunday attendance in last 2 weeks
final _absentMembersProvider = FutureProvider<List<Member>>((ref) async {
  final now = nowInLagos();
  // Go back 14 days to cover 2 Sundays
  final since = now.subtract(const Duration(days: 14));
  final sinceDate = formatDateISO(since);
  return ref.read(attendanceServiceProvider).getAbsentMembersSince(sinceDate);
});

// Top 3 members by present count this calendar month
typedef _LeaderEntry = ({Member member, int pts});

final _topMembersProvider =
    FutureProvider.autoDispose<List<_LeaderEntry>>((ref) async {
  final now = nowInLagos();
  final yearMonth =
      '${now.year}-${now.month.toString().padLeft(2, '0')}';
  final sessions =
      await ref.read(sessionServiceProvider).getSessionsByMonth(yearMonth);
  if (sessions.isEmpty) return [];

  final sessionIds = sessions.map((s) => s.id).toList();
  final data = await Supabase.instance.client
      .from('clock_ins')
      .select('member_id')
      .inFilter('session_id', sessionIds)
      .eq('status', 'present');

  final counts = <String, int>{};
  for (final row in data as List) {
    final mid = row['member_id'] as String;
    counts[mid] = (counts[mid] ?? 0) + 1;
  }
  if (counts.isEmpty) return [];

  final sorted = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final members = await ref.read(memberServiceProvider).getMembers();
  final memberMap = {for (final m in members) m.id: m};
  return sorted
      .take(3)
      .where((e) => memberMap.containsKey(e.key))
      .map<_LeaderEntry>((e) => (member: memberMap[e.key]!, pts: e.value))
      .toList();
});

// ── HomeScreen ────────────────────────────────────────────────────────────────

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(_membersProvider);
    final sessionsAsync = ref.watch(_todaySessionsProvider);
    final upcomingAsync = ref.watch(_upcomingSessionProvider);
    final staff = ref.watch(currentStaffProvider).valueOrNull;
    final lagosNow = nowInLagos();
    final todayMMDD = formatMMDD(lagosNow);
    final todayFormatted = DateFormat('EEEE, MMMM d, y').format(lagosNow);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    ref.listen(_absentMembersProvider, (_, next) {
      next.whenData((members) {
        if (members.isNotEmpty) {
          NotificationService.showAbsenceAlert(members);
        }
      });
    });

    ref.listen(_membersProvider, (_, next) {
      next.whenData((members) {
        final today = formatMMDD(nowInLagos());
        for (final m in members) {
          if (m.birthdayMD == today) {
            NotificationService.showBirthdayNotification(m);
          }
          if (m.anniversaryMD != null && m.anniversaryMD == today) {
            NotificationService.showAnniversaryNotification(m);
          }
        }
      });
    });

    return RefreshIndicator(
      color: AppTheme.primary,
      onRefresh: () async {
        ref.invalidate(_membersProvider);
        ref.invalidate(_todaySessionsProvider);
        ref.invalidate(_upcomingSessionProvider);
        ref.invalidate(_absentMembersProvider);
        ref.invalidate(_topMembersProvider);
      },
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // ── Header ─────────────────────────────────────────────────────────
          Container(
            color: isDark ? AppTheme.darkSurface : AppTheme.surface,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                // Profile avatar → /profile
                GestureDetector(
                  onTap: () => context.push('/profile'),
                  child: Builder(builder: (ctx) {
                    final initials = staff == null
                        ? '?'
                        : staff.fullName
                            .trim()
                            .split(' ')
                            .where((p) => p.isNotEmpty)
                            .take(2)
                            .map((p) => p[0].toUpperCase())
                            .join();
                    return CircleAvatar(
                      radius: 22,
                      backgroundColor: AppTheme.primaryBg,
                      backgroundImage: staff?.avatarUrl != null
                          ? NetworkImage(staff!.avatarUrl!)
                          : null,
                      child: staff?.avatarUrl == null
                          ? Text(
                              initials,
                              style: const TextStyle(
                                color: AppTheme.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            )
                          : null,
                    );
                  }),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${greetingFromHour(lagosNow.hour)}, ${staff?.fullName.split(' ').first ?? 'Admin'}',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: isDark ? AppTheme.darkOnSurface : const Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        staff?.role.displayName ?? 'Guest Team Lead',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? AppTheme.darkOnSurfaceVariant : AppTheme.slate500,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                // Bell — birthday/anniversary count badge
                membersAsync.maybeWhen(
                  data: (members) {
                    final count = members
                        .where((m) =>
                            m.birthdayMD == todayMMDD ||
                            m.anniversaryMD == todayMMDD)
                        .length;
                    return GestureDetector(
                      onTap: () => context.push('/celebrations'),
                      child: Container(
                        height: 40,
                        width: 40,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryBg,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Stack(
                          children: [
                            const Center(
                              child: Icon(
                                Icons.notifications_outlined,
                                color: AppTheme.primary,
                                size: 22,
                              ),
                            ),
                            if (count > 0)
                              Positioned(
                                top: 6,
                                right: 6,
                                child: Container(
                                  width: 16,
                                  height: 16,
                                  decoration: const BoxDecoration(
                                    color: AppTheme.error,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Text(
                                      count > 9 ? '9+' : '$count',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                  orElse: () => GestureDetector(
                    onTap: () => context.push('/celebrations'),
                    child: Container(
                      height: 40,
                      width: 40,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryBg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.notifications_outlined,
                        color: AppTheme.primary,
                        size: 22,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => context.push('/settings'),
                  child: Container(
                    height: 40,
                    width: 40,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.settings_outlined,
                      color: AppTheme.primary,
                      size: 22,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              todayFormatted,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.slate500,
              ),
            ),
          ),

          // ── Upcoming Session card ───────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: upcomingAsync.when(
              loading: () => _UpcomingSessionCard.loading(),
              error: (_, __) => _UpcomingSessionCard.empty(context),
              data: (session) => _UpcomingSessionCard(
                session: session,
                onCheckIn: session == null
                    ? () => context.go('/programs')
                    : () => context.push('/sessions/${session.id}/checkin'),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Stats row ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: membersAsync.when(
              loading: () => const _StatsRow(registered: null, sessions: null),
              error: (_, __) => const _StatsRow(registered: 0, sessions: 0),
              data: (members) => sessionsAsync.when(
                loading: () => _StatsRow(registered: members.length, sessions: null),
                error: (_, __) => _StatsRow(registered: members.length, sessions: 0),
                data: (sessions) => _StatsRow(
                  registered: members.length,
                  sessions: sessions.length,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ── Top Members this month ────────────────────────────────────────
          Consumer(builder: (ctx, ref, _) {
            final topAsync = ref.watch(_topMembersProvider);
            return topAsync.maybeWhen(
              data: (leaders) => _TopMembersSection(leaders: leaders),
              orElse: () => const SizedBox.shrink(),
            );
          }),

          // ── Birthdays & Anniversaries ─────────────────────────────────────
          membersAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (members) {
              final celebrations = _buildCelebrations(members, todayMMDD, lagosNow);
              if (celebrations.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Birthdays & Anniversaries',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        TextButton(
                          onPressed: () => context.push('/celebrations'),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 0),
                          ),
                          child: const Text('See All'),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 164,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      itemCount: celebrations.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (ctx, i) =>
                          _CelebrationCard(data: celebrations[i]),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              );
            },
          ),

          // ── Follow-up section ──────────────────────────────────────────────
          Consumer(builder: (ctx, ref, _) {
            final absentAsync = ref.watch(_absentMembersProvider);
            return absentAsync.maybeWhen(
              data: (members) => _FollowUpSection(members: members),
              orElse: () => const SizedBox.shrink(),
            );
          }),
        ],
      ),
    );
  }

  List<_CelebrationData> _buildCelebrations(
      List<Member> members, String todayMMDD, DateTime lagosNow) {
    final result = <_CelebrationData>[];
    for (final m in members) {
      if (m.birthdayMD == todayMMDD) {
        result.add(_CelebrationData(
            member: m, isBirthday: true, label: 'Today'));
      } else if (m.birthdayMD.isNotEmpty && isWithinDays(m.birthdayMD, 7)) {
        result.add(_CelebrationData(
            member: m,
            isBirthday: true,
            label: _mmddToMonthDay(m.birthdayMD, lagosNow.year)));
      }
      if (m.anniversaryMD != null) {
        if (m.anniversaryMD == todayMMDD) {
          result.add(_CelebrationData(
              member: m, isBirthday: false, label: 'Today'));
        } else if (isWithinDays(m.anniversaryMD!, 7)) {
          result.add(_CelebrationData(
              member: m,
              isBirthday: false,
              label: _mmddToMonthDay(m.anniversaryMD!, lagosNow.year)));
        }
      }
    }
    return result;
  }

  String _mmddToMonthDay(String mmdd, int year) {
    final parts = mmdd.split('-');
    final dt = DateTime(year, int.parse(parts[0]), int.parse(parts[1]));
    return DateFormat('MMM d').format(dt);
  }
}

// ── _UpcomingSessionCard ─────────────────────────────────────────────────────

class _UpcomingSessionCard extends StatelessWidget {
  const _UpcomingSessionCard({
    required this.session,
    required this.onCheckIn,
  });

  final Session? session;
  final VoidCallback? onCheckIn;

  factory _UpcomingSessionCard.loading() => const _UpcomingSessionCard(
        session: null,
        onCheckIn: null,
      );

  factory _UpcomingSessionCard.empty(BuildContext context) =>
      _UpcomingSessionCard(
        session: null,
        onCheckIn: () => context.go('/programs'),
      );

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurfaceContainer : AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppTheme.darkOutlineVariant : AppTheme.slate200,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark 
              ? Colors.black.withValues(alpha: 0.2)
              : Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image area with gradient overlay
          Stack(
            children: [
              Container(
                height: 140,
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: isDark
                      ? const [Color(0xFF242E45), Color(0xFF141B2E)]
                      : const [Color(0xFF1E3A5F), Color(0xFF0F49BD)],
                  ),
                ),
                child: const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Image(
                      image: AssetImage('assets/images/elevation-logo.png'),
                      height: 120,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
              Container(
                height: 140,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: isDark
                      ? [Colors.transparent, Colors.black87]
                      : [Colors.transparent, Colors.black54],
                  ),
                ),
              ),
              Positioned(
                bottom: 12,
                left: 16,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    session == null ? 'NO SESSION TODAY' : 'UPCOMING SESSION',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
            ],
          ),

          // Details
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Builder(builder: (ctx) {
                  final isDark = Theme.of(ctx).brightness == Brightness.dark;
                  return Text(
                    session?.name ?? 'No sessions today',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  );
                }),
                if (session?.startTime != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.schedule,
                          size: 16, color: AppTheme.slate500),
                      const SizedBox(width: 6),
                      Text(
                        '${session!.startTime}'
                        '${session!.endTime != null ? ' – ${session!.endTime}' : ''}',
                        style: const TextStyle(
                            fontSize: 13, color: AppTheme.slate500),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: onCheckIn,
                    icon: const Icon(Icons.how_to_reg, size: 18),
                    label: Text(
                        session == null ? 'Create Program' : 'Start Check-in'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── _StatsRow ────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.registered, required this.sessions});

  final int? registered;
  final int? sessions;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            label: 'REGISTERED',
            value: registered == null ? '—' : '$registered',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            label: "TODAY'S SESSIONS",
            value: sessions == null ? '—' : '$sessions',
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppTheme.slate500,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Celebration card ─────────────────────────────────────────────────────────

class _CelebrationData {
  const _CelebrationData({
    required this.member,
    required this.isBirthday,
    required this.label,
  });
  final Member member;
  final bool isBirthday;
  final String label;
}

class _CelebrationCard extends StatelessWidget {
  const _CelebrationCard({required this.data});
  final _CelebrationData data;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      width: 140,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurfaceContainer : AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppTheme.darkOutlineVariant : AppTheme.slate200,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              MemberAvatar(fullName: data.member.fullName, radius: 32),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: data.isBirthday
                      ? const Color(0xFFEC4899)
                      : AppTheme.amber,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDark ? AppTheme.darkSurface : Colors.white,
                    width: 2,
                  ),
                ),
                child: Icon(
                  data.isBirthday ? Icons.cake : Icons.favorite,
                  size: 10,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            data.member.fullName.split(' ').first,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: isDark ? AppTheme.darkOnSurface : const Color(0xFF0F172A),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            data.label,
            style: const TextStyle(
              fontSize: 11,
              color: AppTheme.slate500,
            ),
          ),
        ],
      ),
    );
  }
}

// ── _FollowUpSection ──────────────────────────────────────────────────────────

class _FollowUpSection extends StatelessWidget {
  const _FollowUpSection({required this.members});
  final List<Member> members;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (members.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Row(
            children: [
              const Icon(Icons.person_off_outlined,
                  size: 16, color: AppTheme.error),
              const SizedBox(width: 6),
              Text(
                'FOLLOW UP (${members.length})',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.error,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              Text(
                'Absent 2+ Sundays',
                style: TextStyle(fontSize: 11, color: isDark ? AppTheme.darkOnSurfaceVariant : AppTheme.slate500),
              ),
            ],
          ),
        ),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: members.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (ctx, i) {
            final m = members[i];
            return Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.errorBg.withValues(alpha: 0.25) : AppTheme.errorBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppTheme.error.withValues(alpha: isDark ? 0.2 : 0.3)),
              ),
              child: Row(
                children: [
                  MemberAvatar(fullName: m.fullName, radius: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(m.fullName,
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: isDark ? AppTheme.darkOnSurface : Colors.black)),
                        const SizedBox(height: 2),
                        TeamBadge(team: m.team),
                      ],
                    ),
                  ),
                  if (m.phone.isNotEmpty)
                    GestureDetector(
                      onTap: () async {
                        final uri = Uri.parse('tel:${m.phone}');
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.error,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Call',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

// ── _TopMembersSection ───────────────────────────────────────────────────────

class _TopMembersSection extends StatelessWidget {
  const _TopMembersSection({required this.leaders});
  final List<_LeaderEntry> leaders;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Top Members This Month',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: isDark ? AppTheme.darkOnSurface : const Color(0xFF0F172A),
                ),
              ),
              TextButton(
                onPressed: () => context.go('/reports'),
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                ),
                child: const Text('See All'),
              ),
            ],
          ),
        ),
        if (leaders.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkSurfaceContainer : AppTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? AppTheme.darkOutlineVariant : AppTheme.slate200,
                ),
              ),
              child: const Center(
                child: Text(
                  'No check-ins recorded this month yet.',
                  style: TextStyle(color: AppTheme.slate500, fontSize: 13),
                ),
              ),
            ),
          )
        else
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: leaders.asMap().entries.map((entry) {
              final rank = entry.key + 1;
              final e = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isDark ? AppTheme.darkSurfaceContainer : AppTheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? AppTheme.darkOutlineVariant : AppTheme.slate200,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: rank == 1
                              ? (isDark
                                  ? const Color(0xFF4A3C2A)
                                  : const Color(0xFFFFF7ED))
                              : (isDark
                                  ? const Color(0xFF0A1128)
                                  : AppTheme.primaryBg),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '#$rank',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: rank == 1
                                  ? (isDark
                                      ? const Color(0xFFD4A574)
                                      : const Color(0xFFEA580C))
                                  : (isDark
                                      ? AppTheme.darkPrimary
                                      : AppTheme.primary),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      MemberAvatar(fullName: e.member.fullName, radius: 16),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          e.member.fullName,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      TeamBadge(team: e.member.team),
                      const SizedBox(width: 8),
                      Text(
                        '${e.pts} pts',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: AppTheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
