// lib/features/settings/settings_screen.dart
//
// Mirrors app/(dashboard)/settings/page.tsx
//
// Allows toggling test mode (bypasses the Lagos-time gate on check-in).
// In Flutter the setting is stored in Supabase settings table.
//
// When test mode is ON an extra "Debug — Sunday Flow" card is shown
// so you can quickly open any of the 3 service check-in gates for today.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import '../../app_theme/app_theme.dart';
import '../../core/utils/date_utils.dart';
import '../../models/enums.dart';
import '../../models/session.dart';
import '../../models/staff_user.dart';
import '../../providers/auth_provider.dart';
import '../../services/auth_service.dart';
import '../../services/program_service.dart';
import '../../services/session_service.dart';
import '../../widgets/avatar_widget.dart';

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final _testModeProvider = FutureProvider<bool>((ref) async {
  final data = await Supabase.instance.client
      .from('settings')
      .select('value')
      .eq('key', 'test_mode_enabled')
      .maybeSingle();
  return data?['value'] == 'true';
});

final _todaySessionsProvider = FutureProvider<List<Session>>((ref) {
  final today = formatDateISO(nowInLagos());
  return ref.read(sessionServiceProvider).getSessionsByDate(today);
});

final _staffProvider = FutureProvider<List<StaffUser>>((ref) {
  return ref.read(authServiceProvider).getStaffUsers();
});

// ---------------------------------------------------------------------------
// SettingsScreen
// ---------------------------------------------------------------------------

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final testModeAsync = ref.watch(_testModeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: testModeAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Error: $e'),
            data: (testMode) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Test mode toggle ────────────────────────────────────────
                _card(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Test mode',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15)),
                          const SizedBox(height: 4),
                          Text(
                            testMode
                                ? 'ON — timing gate bypassed'
                                : 'OFF',
                            style: TextStyle(
                              fontSize: 12,
                              color: testMode
                                  ? AppTheme.success
                                  : const Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ),
                      Switch(
                        value: testMode,
                        activeThumbColor: AppTheme.primary,
                        onChanged: (v) async {
                          await Supabase.instance.client
                              .from('settings')
                              .upsert({
                                'key': 'test_mode_enabled',
                                'value': v ? 'true' : 'false',
                              });
                          ref.invalidate(_testModeProvider);
                          ref.invalidate(_todaySessionsProvider);
                        },
                      ),
                    ],
                  ),
                ),

                // ── Debug launcher (only when test mode is ON) ─────────────
                if (testMode) ...[
                  const SizedBox(height: 16),
                  const _DebugSundayCard(),
                ],

                // ── Staff Management ────────────────────────────────────────
                const SizedBox(height: 16),
                const _StaffManagementCard(),

                // ── Sign out ────────────────────────────────────────────────
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: () async {
                    await ref
                        .read(currentStaffProvider.notifier)
                        .logout();
                    if (context.mounted) context.go('/');
                  },
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  label: const Text('Sign Out'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.error,
                    side: BorderSide(
                        color: AppTheme.error.withValues(alpha: 0.4)),
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8)
          ],
        ),
        child: child,
      );
}

// ---------------------------------------------------------------------------
// _StaffManagementCard
// ---------------------------------------------------------------------------

class _StaffManagementCard extends ConsumerWidget {
  const _StaffManagementCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staffAsync = ref.watch(_staffProvider);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.manage_accounts_outlined,
                  size: 18, color: AppTheme.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Team Lead Management',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline,
                    color: AppTheme.primary, size: 22),
                tooltip: 'Add team lead',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => _showAddSheet(context, ref),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Staff list
          staffAsync.when(
            loading: () => const Center(
              child: SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            error: (e, _) => Text('Error: $e',
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.error)),
            data: (staff) {
              if (staff.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'No team leads registered. Tap + to add the first one.',
                    style: TextStyle(
                        fontSize: 12, color: AppTheme.slate500),
                  ),
                );
              }
              return Column(
                children: staff
                    .map((u) => _StaffTile(
                          user: u,
                          onDelete: () async {
                            await ref
                                .read(authServiceProvider)
                                .deleteStaffUser(u.id);
                            ref.invalidate(_staffProvider);
                          },
                        ))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showAddSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddStaffSheet(
        onAdded: () => ref.invalidate(_staffProvider),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _StaffTile
// ---------------------------------------------------------------------------

class _StaffTile extends StatelessWidget {
  const _StaffTile({required this.user, required this.onDelete});

  final StaffUser user;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final roleColor = user.role == StaffRole.teamLead
        ? AppTheme.primary
        : AppTheme.slate500;
    final roleBg = user.role == StaffRole.teamLead
        ? AppTheme.primaryBg
        : const Color(0xFFF1F5F9);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          MemberAvatar(
              fullName: user.fullName,
              imageUrl: user.avatarUrl,
              radius: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.fullName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    _chip(user.team.value, AppTheme.primary,
                        AppTheme.primaryBg),
                    const SizedBox(width: 6),
                    _chip(user.role.displayName, roleColor, roleBg),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded,
                size: 18, color: Color(0xFFCBD5E1)),
            onPressed: () => _confirmDelete(context),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, Color fg, Color bg) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 10, color: fg, fontWeight: FontWeight.w600)),
      );

  void _confirmDelete(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove team lead?'),
        content: Text(
            'Remove ${user.fullName} from the app? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onDelete();
            },
            child: const Text('Remove',
                style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _AddStaffSheet — bottom sheet to register a new staff member
// ---------------------------------------------------------------------------

class _AddStaffSheet extends StatefulWidget {
  const _AddStaffSheet({required this.onAdded});

  final VoidCallback onAdded;

  @override
  State<_AddStaffSheet> createState() => _AddStaffSheetState();
}

class _AddStaffSheetState extends State<_AddStaffSheet> {
  final _nameCtrl = TextEditingController();
  Team _team = Team.teamA;
  StaffRole _role = StaffRole.assistant;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Please enter a full name.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.from('staff_users').insert({
        'full_name': name,
        'team': _team.value,
        'role': _role.value,
      });
      widget.onAdded();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        _error = 'Failed to save. Please try again.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      margin: const EdgeInsets.all(12),
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottom),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Add Team Lead',
              style:
                  TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          const SizedBox(height: 20),

          // Full name field
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Full name',
              hintText: 'e.g. John Doe',
            ),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 20),

          // Team selector
          const Text('Team',
              style: TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [Team.teamA, Team.teamB, Team.teamC]
                .map(
                  (t) => ChoiceChip(
                    label: Text(t.value),
                    selected: _team == t,
                    onSelected: (_) => setState(() => _team = t),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 20),

          // Role selector
          const Text('Role',
              style: TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: StaffRole.values
                .map(
                  (r) => ChoiceChip(
                    label: Text(r.displayName),
                    selected: _role == r,
                    onSelected: (_) => setState(() => _role = r),
                  ),
                )
                .toList(),
          ),

          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
                style: const TextStyle(
                    color: AppTheme.error, fontSize: 12)),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _loading ? null : _save,
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const Text('Add Team Lead'),
            ),
          ),
        ],
      ),
    );
  }
}

// Shown only when test mode is ON.
// Queries today's sessions and offers a button per service.
// If today has no Sunday sessions, offers a "Create & open" shortcut.
// ---------------------------------------------------------------------------

class _DebugSundayCard extends ConsumerStatefulWidget {
  const _DebugSundayCard();

  @override
  ConsumerState<_DebugSundayCard> createState() => _DebugSundayCardState();
}

class _DebugSundayCardState extends ConsumerState<_DebugSundayCard> {
  bool _creating = false;

  static const _serviceNames = ['Service 1', 'Service 2', 'Service 3'];

  /// Creates a throwaway Sunday program + 3 sessions for today, then
  /// returns the list of created sessions.
  Future<List<Session>> _createTodaySessions() async {
    setState(() => _creating = true);
    try {
      final today = formatDateISO(nowInLagos());
      final program = await ref.read(programServiceProvider).createProgram(
            title: 'Sunday Service (Test — $today)',
            programType: ProgramType.sunday,
            teamScope: 'all',
            isTBD: false,
            startDate: today,
            endDate: today,
          );
      final sessions = await ref
          .read(sessionServiceProvider)
          .createSundaySessions(programId: program.id, date: today);
      ref.invalidate(_todaySessionsProvider);
      return sessions;
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  void _openGate(BuildContext ctx, String sessionId) {
    context.push('/sessions/$sessionId/checkin');
  }

  @override
  Widget build(BuildContext context) {
    final sessionsAsync = ref.watch(_todaySessionsProvider);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED), // amber-50
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.amber.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.bug_report_outlined,
                  size: 18, color: AppTheme.amber),
              const SizedBox(width: 8),
              const Text(
                'Debug — Sunday Flow',
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: AppTheme.amber),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => ref.invalidate(_todaySessionsProvider),
                child: const Icon(Icons.refresh,
                    size: 16, color: AppTheme.amber),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            "Opens today's check-in gate for each service (gate timing bypassed).",
            style: TextStyle(fontSize: 11, color: AppTheme.slate500),
          ),
          const SizedBox(height: 14),

          // Session buttons
          sessionsAsync.when(
            loading: () => const Center(
                child: SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(strokeWidth: 2))),
            error: (e, _) => Text('Error loading sessions: $e',
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.error)),
            data: (sessions) {
              // Filter to today's Sunday services
              final sundaySessions = sessions
                  .where((s) => _serviceNames.contains(s.name))
                  .toList();

              if (sundaySessions.isEmpty) {
                // No Sunday sessions today — offer to create them
                return Column(
                  children: [
                    const Text(
                      'No Sunday sessions for today.',
                      style: TextStyle(
                          fontSize: 12, color: AppTheme.slate500),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _creating ? null : () async {
                          final messenger = ScaffoldMessenger.of(context);
                          try {
                            await _createTodaySessions();
                          } catch (e) {
                            if (mounted) {
                              messenger.showSnackBar(
                                SnackBar(
                                    content: Text('Error: $e'),
                                    backgroundColor: AppTheme.error),
                              );
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.amber,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 42),
                        ),
                        icon: _creating
                            ? const SizedBox(
                                height: 14,
                                width: 14,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.add),
                        label: Text(
                            _creating ? 'Creating…' : 'Create & Open Sessions'),
                      ),
                    ),
                  ],
                );
              }

              // Sort by service name so order is always 1, 2, 3
              sundaySessions.sort((a, b) => a.name.compareTo(b.name));

              return Column(
                children: sundaySessions.map((session) {
                  final index =
                      _serviceNames.indexOf(session.name);
                  final teamLabel = ['Team A', 'Team B', 'Team C']
                      .elementAtOrNull(index) ?? '';
                  final timeRange = session.startTime != null
                      ? '${session.startTime} – ${session.endTime ?? '?'}'
                      : 'No time set';

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      onTap: () => _openGate(context, session.id),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: AppTheme.slate200),
                        ),
                        child: Row(
                          children: [
                            // Service icon
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: AppTheme.primaryBg,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: Text(
                                  '${index + 1}',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.primary,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    session.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(
                                    '$teamLabel  ·  $timeRange',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: AppTheme.slate500),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.qr_code_scanner,
                                size: 18, color: AppTheme.primary),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

