// lib/features/reports/reports_screen.dart
//
// Stitch UI redesign — Mirrors app/(dashboard)/reports/page.tsx
//
// AppBar: "Reports" left-aligned, filter icon right.
// Team filter chips: Overall / Team A / Team B / Team C.
// Stats row: AVG ATTENDANCE + TOTAL MEMBERS.
// "Attendance Trends" section with placeholder chart.
// "Monthly Leaderboard" section with MemberAvatar, TeamBadge, attendance %, session count.
// First card gets "TOP ATTENDER" gold badge.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/enums.dart';
import '../../models/leaderboard_entry.dart';
import '../../services/report_service.dart';
import '../../core/utils/date_utils.dart';
import '../../app_theme/app_theme.dart';
import '../../widgets/team_badge.dart';
import '../../widgets/avatar_widget.dart';

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final _monthlyLeaderboardProvider =
    FutureProvider.family<List<LeaderboardEntry>, String>(
        (ref, yearMonth) {
  return ref
      .read(reportServiceProvider)
      .getMonthlyLeaderboard(yearMonth);
});

// ---------------------------------------------------------------------------
// ReportsScreen
// ---------------------------------------------------------------------------

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  // 'all' | 'Team A' | 'Team B' | 'Team C'
  String _teamFilter = 'all';

  late final String _currentYearMonth;

  @override
  void initState() {
    super.initState();
    final now = nowInLagos();
    _currentYearMonth =
        '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  List<LeaderboardEntry> _filterByTeam(List<LeaderboardEntry> entries) {
    if (_teamFilter == 'all') return entries;
    final team = Team.values.firstWhere(
      (t) => t.value == _teamFilter,
      orElse: () => Team.none,
    );
    return entries.where((e) => e.team == team).toList();
  }

  @override
  Widget build(BuildContext context) {
    final leaderboardAsync =
        ref.watch(_monthlyLeaderboardProvider(_currentYearMonth));

    final bestScore = leaderboardAsync.maybeWhen(
      data: (all) {
        final entries = _filterByTeam(all);
        return entries.isNotEmpty ? entries.first.presentCount : 0;
      },
      orElse: () => 0,
    );

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        centerTitle: false,
        title: const Text('Reports'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list_outlined),
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Date range filter coming soon'),
                duration: Duration(seconds: 2),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async =>
              ref.invalidate(_monthlyLeaderboardProvider(_currentYearMonth)),
          child: CustomScrollView(
            slivers: [
              // ── Team filter chips ────────────────────────────────────
              SliverToBoxAdapter(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Row(
                    children: [
                      _TeamChip(
                        label: 'Overall',
                        selected: _teamFilter == 'all',
                        onTap: () =>
                            setState(() => _teamFilter = 'all'),
                      ),
                      const SizedBox(width: 8),
                      _TeamChip(
                        label: 'Team A',
                        selected: _teamFilter == 'Team A',
                        onTap: () =>
                            setState(() => _teamFilter = 'Team A'),
                      ),
                      const SizedBox(width: 8),
                      _TeamChip(
                        label: 'Team B',
                        selected: _teamFilter == 'Team B',
                        onTap: () =>
                            setState(() => _teamFilter = 'Team B'),
                      ),
                      const SizedBox(width: 8),
                      _TeamChip(
                        label: 'Team C',
                        selected: _teamFilter == 'Team C',
                        onTap: () =>
                            setState(() => _teamFilter = 'Team C'),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Stats row ────────────────────────────────────────────
              SliverToBoxAdapter(
                child: leaderboardAsync.when(
                  loading: () => const SizedBox(height: 80),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (all) {
                    final entries = _filterByTeam(all);
                    final totalMembers = entries.length;
                    final avgAttendance = totalMembers == 0
                        ? 0.0
                        : entries
                                .map((e) => e.presentCount)
                                .reduce((a, b) => a + b) /
                            totalMembers;

                    return Padding(
                      padding:
                          const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: _SummaryCard(
                              label: 'AVG POINTS',
                              value: avgAttendance
                                  .toStringAsFixed(1),
                              unit: 'pts',
                              color: AppTheme.primary,
                              bg: AppTheme.primaryBg,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _SummaryCard(
                              label: 'TOTAL MEMBERS',
                              value: '$totalMembers',
                              unit: 'members',
                              color: AppTheme.success,
                              bg: AppTheme.successBg,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

              // ── Attendance Trends section ────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SectionHeader(title: 'Attendance Trends'),
                      const SizedBox(height: 12),
                      Container(
                        height: 120,
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.slate200),
                        ),
                        child: Column(
                          children: [
                            Expanded(
                              child: Center(
                                child: Text(
                                  'Chart coming soon',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.slate500
                                        .withValues(alpha: 0.6),
                                  ),
                                ),
                              ),
                            ),
                            // Date axis labels
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                  12, 0, 12, 8),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: _buildDateLabels(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                              child: _SectionHeader(
                                  title: 'Monthly Leaderboard')),
                          TextButton(
                            onPressed: () =>
                                ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content:
                                    Text('Full leaderboard coming soon'),
                                duration: Duration(seconds: 2),
                              ),
                            ),
                            child: const Text(
                              'SEE ALL',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '1 service = 1 point  ·  Best score: $bestScore pts',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.slate500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Leaderboard list ─────────────────────────────────────
              leaderboardAsync.when(
                loading: () => const SliverToBoxAdapter(
                  child:
                      Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => SliverToBoxAdapter(
                  child: Center(child: Text('Error: $e')),
                ),
                data: (all) {
                  final entries = _filterByTeam(all);
                  if (entries.isEmpty) {
                    return const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(
                          child: Text(
                            'No leaderboard data yet.',
                            style:
                                TextStyle(color: AppTheme.slate500),
                          ),
                        ),
                      ),
                    );
                  }
                  final maxPresent = entries
                      .map((e) => e.presentCount)
                      .reduce((a, b) => a > b ? a : b);

                  return SliverPadding(
                    padding:
                        const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (ctx, i) {
                          final entry = entries[i];
                          final isTop = i == 0;
                          final pct = maxPresent == 0
                              ? 0
                              : (entry.presentCount /
                                          maxPresent *
                                          100)
                                      .round();
                          return Padding(
                            padding:
                                const EdgeInsets.only(bottom: 10),
                            child: _LeaderboardCard(
                              entry: entry,
                              isTop: isTop,
                              attendancePct: pct,
                            ),
                          );
                        },
                        childCount: entries.length,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildDateLabels() {
    final now = nowInLagos();
    return List.generate(5, (i) {
      final d = now.subtract(Duration(days: (4 - i) * 7));
      return Text(
        '${d.month}/${d.day}',
        style: const TextStyle(
            fontSize: 10, color: AppTheme.slate500),
      );
    });
  }
}

// ---------------------------------------------------------------------------
// _TeamChip
// ---------------------------------------------------------------------------

class _TeamChip extends StatelessWidget {
  const _TeamChip({
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
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? AppTheme.primary : AppTheme.slate200),
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

// ---------------------------------------------------------------------------
// _SectionHeader — title with blue left border accent
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: AppTheme.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _SummaryCard
// ---------------------------------------------------------------------------

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
    required this.bg,
  });
  final String label;
  final String value;
  final String unit;
  final Color color;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: color.withValues(alpha: 0.2)),
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
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          Text(
            unit,
            style: const TextStyle(
                fontSize: 11, color: AppTheme.slate500),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _LeaderboardCard
// ---------------------------------------------------------------------------

class _LeaderboardCard extends StatelessWidget {
  const _LeaderboardCard({
    required this.entry,
    required this.isTop,
    required this.attendancePct,
  });
  final LeaderboardEntry entry;
  final bool isTop;
  final int attendancePct;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Row(
        children: [
          // Avatar with optional TOP ATTENDER badge
          Stack(
            clipBehavior: Clip.none,
            children: [
              MemberAvatar(
                  fullName: entry.memberName, radius: 22),
              if (isTop)
                Positioned(
                  top: -6,
                  right: -6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.amber,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'TOP',
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),

          // Name + team
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.memberName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                TeamBadge(team: entry.team),
              ],
            ),
          ),

          // Attendance stat
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$attendancePct%',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: AppTheme.primary,
                ),
              ),
              Text(
                '${entry.presentCount} pts',
                style: const TextStyle(
                    fontSize: 11, color: AppTheme.slate500),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
