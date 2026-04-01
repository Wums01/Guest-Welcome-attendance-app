import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../models/program.dart';
import '../../models/session.dart';
import '../../services/program_service.dart';
import '../../services/session_service.dart';
import '../../services/attendance_service.dart';
import '../../core/utils/date_utils.dart';
import '../../app_theme/app_theme.dart';
import '../../widgets/session_recovery_edge_button.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

final _selectedDateProvider =
    StateProvider<String>((_) => formatDateISO(nowInLagos()));

final _sessionsByDateProvider =
    FutureProvider.family<List<Session>, String>((ref, date) {
  return ref.read(sessionServiceProvider).getSessionsByDate(date);
});

final _allProgramsProvider = FutureProvider<List<Program>>((ref) {
  return ref.read(programServiceProvider).getPrograms();
});

final _sessionsByProgramProvider =
    FutureProvider.family<List<Session>, String>((ref, programId) {
  return ref.read(sessionServiceProvider).getSessionsByProgram(programId);
});

// ── SessionsScreen ────────────────────────────────────────────────────────────

class SessionsScreen extends ConsumerStatefulWidget {
  const SessionsScreen({super.key});

  @override
  ConsumerState<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends ConsumerState<SessionsScreen>
    with SingleTickerProviderStateMixin {
  final _search = TextEditingController();
  String _query = '';
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _search.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _showMenuSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.list_alt_outlined),
              title: const Text('Programs'),
              onTap: () {
                Navigator.of(context).pop();
                context.push('/programs');
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Settings'),
              onTap: () {
                Navigator.of(context).pop();
                context.push('/settings');
              },
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Cancel'),
              onTap: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu, size: 22),
          onPressed: _showMenuSheet,
        ),
        title: const Text('Sessions'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'By Date'),
            Tab(text: 'By Program'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_circle_outlined, size: 26),
            onPressed: () => context.push('/profile'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.go('/programs'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
      body: Stack(
        children: [
          TabBarView(
            controller: _tabController,
            children: [
              _ByDateTab(search: _search, query: _query,
                  onQueryChanged: (v) => setState(() => _query = v)),
              const _ByProgramTab(),
            ],
          ),
          const SessionRecoveryEdgeButton(),
        ],
      ),
    );
  }
}

// ── By Date Tab ───────────────────────────────────────────────────────────────

class _ByDateTab extends ConsumerWidget {
  const _ByDateTab({
    required this.search,
    required this.query,
    required this.onQueryChanged,
  });

  final TextEditingController search;
  final String query;
  final ValueChanged<String> onQueryChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedDate = ref.watch(_selectedDateProvider);
    final sessionsAsync = ref.watch(_sessionsByDateProvider(selectedDate));
    final lagosNow = nowInLagos();
    final todayISO = formatDateISO(lagosNow);

    String sectionLabel(String dateISO) {
      if (dateISO == todayISO) return 'TODAY';
      final d = parseDateISO(dateISO);
      final diff = lagosNow.difference(d).inDays;
      if (diff == 1) return 'YESTERDAY';
      return DateFormat('EEEE, MMM d').format(d).toUpperCase();
    }

    return SafeArea(
      child: Column(
        children: [
          // ── Search + date picker ───────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: search,
                    onChanged: onQueryChanged,
                    decoration: const InputDecoration(
                      hintText: 'Search sessions or dates...',
                      prefixIcon: Icon(Icons.search,
                          size: 20, color: AppTheme.slate500),
                      contentPadding: EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: parseDateISO(selectedDate),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) {
                      ref.read(_selectedDateProvider.notifier).state =
                          formatDateISO(picked);
                    }
                  },
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      border: Border.all(color: AppTheme.slate200),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.calendar_today,
                        size: 18, color: AppTheme.slate500),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // ── Section label ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Builder(builder: (ctx) {
                final isDark = Theme.of(ctx).brightness == Brightness.dark;
                return Text(
                  sectionLabel(selectedDate),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isDark ? AppTheme.darkOnSurface : AppTheme.slate500,
                    letterSpacing: 0.8,
                  ),
                );
              }),
            ),
          ),

          // ── Session list ──────────────────────────────────────────────
          Expanded(
            child: sessionsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => const Center(child: Text('Unable to load sessions. Please try again.')),
              data: (sessions) {
                final filtered = query.isEmpty
                    ? sessions
                    : sessions
                        .where((s) => s.name
                            .toLowerCase()
                            .contains(query.toLowerCase()))
                        .toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('No sessions on this date.',
                            style: TextStyle(color: AppTheme.slate500)),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: 200,
                          child: OutlinedButton(
                            onPressed: () => context.go('/programs'),
                            child: const Text('Create a program'),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  color: AppTheme.primary,
                  onRefresh: () async => ref
                      .invalidate(_sessionsByDateProvider(selectedDate)),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (ctx, i) =>
                        _SessionCard(session: filtered[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── By Program Tab ────────────────────────────────────────────────────────────

class _ByProgramTab extends ConsumerWidget {
  const _ByProgramTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final programsAsync = ref.watch(_allProgramsProvider);

    return programsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (programs) {
        if (programs.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No programs yet.\nCreate a program first.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.slate500),
              ),
            ),
          );
        }
        return RefreshIndicator(
          color: AppTheme.primary,
          onRefresh: () async => ref.invalidate(_allProgramsProvider),
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            itemCount: programs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _ProgramAccordion(program: programs[i]),
          ),
        );
      },
    );
  }
}

class _ProgramAccordion extends ConsumerWidget {
  const _ProgramAccordion({required this.program});
  final Program program;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(_sessionsByProgramProvider(program.id));

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppTheme.slate200),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          title: Text(
            program.title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          subtitle: Row(
            children: [
              _TypeBadge(program.programType.displayName),
              const SizedBox(width: 6),
              sessionsAsync.maybeWhen(
                data: (s) => Text(
                  '${s.length} session${s.length == 1 ? '' : 's'}',
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.slate500),
                ),
                orElse: () => const SizedBox.shrink(),
              ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.open_in_new,
                    size: 18, color: AppTheme.primary),
                onPressed: () =>
                    context.push('/programs/${program.id}'),
                tooltip: 'Open program',
              ),
            ],
          ),
          children: [
            sessionsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Unable to delete session. Please try again.'),
              ),
              data: (sessions) {
                if (sessions.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: Text(
                      'No sessions in this program yet.',
                      style: TextStyle(
                          color: AppTheme.slate500, fontSize: 13),
                    ),
                  );
                }
                return Column(
                  children: sessions
                      .map((s) => _SessionRow(session: s))
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session});
  final Session session;

  bool get _isLive {
    final now = nowInLagos();
    final todayISO = formatDateISO(now);
    if (session.date != todayISO) return false;
    final state = sessionGateState(session.startTime, session.endTime, now);
    return state == SessionGateState.open || state == SessionGateState.noGate;
  }

  @override
  Widget build(BuildContext context) {
    final live = _isLive;
    return InkWell(
      onTap: () => context.push('/sessions/${session.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (live)
                    const Text(
                      'LIVE NOW',
                      style: TextStyle(
                        color: AppTheme.primary,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                  Text(
                    session.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  if (session.date.isNotEmpty)
                    Text(
                      '${DateFormat('MMM d, y').format(parseDateISO(session.date))}'
                      '${session.startTime != null ? '  •  ${session.startTime}' : ''}',
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.slate500),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                size: 18, color: AppTheme.slate500),
          ],
        ),
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppTheme.primaryBg,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: const TextStyle(
              color: AppTheme.primary,
              fontSize: 10,
              fontWeight: FontWeight.w600),
        ),
      );
}

// ── _SessionCard ──────────────────────────────────────────────────────────────

class _SessionCard extends ConsumerWidget {
  const _SessionCard({required this.session});
  final Session session;

  bool get _isLive {
    final now = nowInLagos();
    final todayISO = formatDateISO(now);
    if (session.date != todayISO) return false;
    final state = sessionGateState(session.startTime, session.endTime, now);
    return state == SessionGateState.open || state == SessionGateState.noGate;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<int>(
      future: ref
          .read(attendanceServiceProvider)
          .getClockInCountBySession(session.id),
      builder: (ctx, snap) {
        final count = snap.data ?? 0;
        final live = _isLive;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.slate200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (live)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 4),
                            child: Text(
                              'LIVE NOW',
                              style: TextStyle(
                                color: AppTheme.primary,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
                        Text(
                          session.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        if (session.startTime != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              '${session.startTime}'
                              '${session.endTime != null ? ' – ${session.endTime}' : ''}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.slate500,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryBg,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$count Present',
                      style: const TextStyle(
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: () => context.push('/sessions/${session.id}'),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Details',
                        style: TextStyle(
                          color: AppTheme.primary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      Icon(Icons.chevron_right,
                          size: 18, color: AppTheme.primary),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
