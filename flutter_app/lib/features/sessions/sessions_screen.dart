import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../models/session.dart';
import '../../services/session_service.dart';
import '../../services/attendance_service.dart';
import '../../core/utils/date_utils.dart';
import '../../app_theme/app_theme.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

final _selectedDateProvider =
    StateProvider<String>((_) => formatDateISO(nowInLagos()));

final _sessionsByDateProvider =
    FutureProvider.family<List<Session>, String>((ref, date) {
  return ref.read(sessionServiceProvider).getSessionsByDate(date);
});

// ── SessionsScreen ────────────────────────────────────────────────────────────

class SessionsScreen extends ConsumerStatefulWidget {
  const SessionsScreen({super.key});

  @override
  ConsumerState<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends ConsumerState<SessionsScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu, size: 22),
          onPressed: () => context.push('/settings'),
        ),
        title: const Text('Sessions'),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_circle_outlined, size: 26),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.go('/programs'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ── Search + date picker ─────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _search,
                      onChanged: (v) => setState(() => _query = v),
                      decoration: const InputDecoration(
                        hintText: 'Search sessions or dates...',
                        prefixIcon: Icon(Icons.search,
                            size: 20, color: AppTheme.slate500),
                        contentPadding:
                            EdgeInsets.symmetric(vertical: 12),
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
                        ref
                            .read(_selectedDateProvider.notifier)
                            .state = formatDateISO(picked);
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
                child: Text(
                  sectionLabel(selectedDate),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.slate500,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ),

            // ── Session list ──────────────────────────────────────────────
            Expanded(
              child: sessionsAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (sessions) {
                  final filtered = _query.isEmpty
                      ? sessions
                      : sessions
                          .where((s) => s.name
                              .toLowerCase()
                              .contains(_query.toLowerCase()))
                          .toList();

                  if (filtered.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('No sessions on this date.',
                              style: TextStyle(
                                  color: AppTheme.slate500)),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: 200,
                            child: OutlinedButton(
                              onPressed: () =>
                                  context.go('/programs'),
                              child: const Text(
                                  'Create a program'),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return RefreshIndicator(
                    color: AppTheme.primary,
                    onRefresh: () async => ref.invalidate(
                        _sessionsByDateProvider(selectedDate)),
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(
                          16, 4, 16, 100),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 10),
                      itemBuilder: (ctx, i) =>
                          _SessionCard(session: filtered[i]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
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
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
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
                  onTap: () =>
                      context.push('/sessions/${session.id}'),
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
