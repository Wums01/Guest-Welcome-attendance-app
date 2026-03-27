// lib/features/programs/program_detail_screen.dart
//
// Shows a single program's info + its sessions list.
// Sunday programs get a "Create Sunday Sessions" quick-create button.
// Wednesday programs get a "Create Wednesday Session" button.
// AppBar "+" opens a manual session creation sheet.
// Tapping a session row navigates to /sessions/:id.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/program.dart';
import '../../models/session.dart';
import '../../models/enums.dart';
import '../../services/program_service.dart';
import '../../services/session_service.dart';
import '../../app_theme/app_theme.dart';

// ---------------------------------------------------------------------------
// Providers — family, keyed by programId
// ---------------------------------------------------------------------------

final _programDetailProvider =
    FutureProvider.family<Program?, String>((ref, id) {
  return ref.read(programServiceProvider).getProgramById(id);
});

final _programSessionsProvider =
    FutureProvider.family<List<Session>, String>((ref, id) {
  return ref.read(sessionServiceProvider).getSessionsByProgram(id);
});

// ---------------------------------------------------------------------------
// ProgramDetailScreen
// ---------------------------------------------------------------------------

class ProgramDetailScreen extends ConsumerWidget {
  const ProgramDetailScreen({super.key, required this.programId});

  final String programId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final programAsync = ref.watch(_programDetailProvider(programId));
    final sessionsAsync = ref.watch(_programSessionsProvider(programId));

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Theme.of(context).brightness == Brightness.dark 
          ? AppTheme.darkSurface 
          : AppTheme.surface,
        leading: BackButton(onPressed: () => context.pop()),
        title: programAsync.when(
          data: (p) => Text(p?.title ?? 'Program'),
          loading: () => const Text('Loading…'),
          error: (_, __) => const Text('Program'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add session',
            onPressed: () => _openAddSessionSheet(context, ref),
          ),
        ],
      ),
      body: programAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (program) {
          if (program == null) {
            return const Center(child: Text('Program not found.'));
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(_programDetailProvider(programId));
              ref.invalidate(_programSessionsProvider(programId));
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
              children: [
                // ── Program info card ─────────────────────────────────────
                _ProgramInfoCard(program: program),
                const SizedBox(height: 16),

                // ── Quick-create buttons ──────────────────────────────────
                if (program.programType == ProgramType.sunday) ...[
                  _QuickCreateButton(
                    label: 'Create Sunday Sessions',
                    icon: Icons.wb_sunny_outlined,
                    onTap: () =>
                        _createSundaySessions(context, ref, program.id),
                  ),
                  const SizedBox(height: 12),
                ],
                if (program.programType == ProgramType.wednesday) ...[
                  _QuickCreateButton(
                    label: 'Create Wednesday Session',
                    icon: Icons.book_outlined,
                    onTap: () =>
                        _createWednesdaySessions(context, ref, program.id),
                  ),
                  const SizedBox(height: 12),
                ],

                // ── Sessions header ───────────────────────────────────────
                Builder(builder: (ctx) {
                  final isDark = Theme.of(ctx).brightness == Brightness.dark;
                  return Row(
                    children: [
                      const Text(
                        'Sessions',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      sessionsAsync.maybeWhen(
                        data: (s) => Text(
                          '${s.length} total',
                          style: TextStyle(
                              fontSize: 12, 
                              color: isDark 
                                ? AppTheme.darkOnSurfaceVariant 
                                : AppTheme.slate500),
                        ),
                        orElse: () => const SizedBox.shrink(),
                      ),
                    ],
                  );
                }),
                const SizedBox(height: 10),

                // ── Sessions list ─────────────────────────────────────────
                sessionsAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) =>
                      Center(child: Text('Error loading sessions: $e')),
                  data: (sessions) {
                    if (sessions.isEmpty) {
                      return Builder(builder: (ctx) {
                        final isDark = Theme.of(ctx).brightness == Brightness.dark;
                        return Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: isDark 
                              ? AppTheme.darkSurfaceContainer 
                              : AppTheme.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isDark 
                                ? AppTheme.darkOutlineVariant 
                                : AppTheme.slate200,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              'No sessions yet. Tap + to add one.',
                              style: TextStyle(
                                color: isDark 
                                  ? AppTheme.darkOnSurfaceVariant 
                                  : AppTheme.slate500,
                              ),
                            ),
                          ),
                        );
                      });
                    }
                    return Column(
                      children: sessions
                          .map((s) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _SessionRow(
                                  session: s,
                                  onTap: () =>
                                      context.push('/sessions/${s.id}'),
                                  onDeleted: () => ref.invalidate(
                                      _programSessionsProvider(programId)),
                                ),
                              ))
                          .toList(),
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _openAddSessionSheet(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: _SessionSheet(
          programId: programId,
          onCreated: () =>
              ref.invalidate(_programSessionsProvider(programId)),
        ),
      ),
    );
  }

  Future<void> _createSundaySessions(
      BuildContext context, WidgetRef ref, String progId) async {
    final date = await _pickDate(context);
    if (date == null) return;
    try {
      await ref
          .read(sessionServiceProvider)
          .createSundaySessions(programId: progId, date: date);
      ref.invalidate(_programSessionsProvider(programId));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('3 Sunday sessions created'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'),
              backgroundColor: AppTheme.error),
        );
      }
    }
  }

  Future<void> _createWednesdaySessions(
      BuildContext context, WidgetRef ref, String progId) async {
    final date = await _pickDate(context);
    if (date == null) return;
    try {
      await ref
          .read(sessionServiceProvider)
          .createWednesdaySessions(programId: progId, date: date);
      ref.invalidate(_programSessionsProvider(programId));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Wednesday session created'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'),
              backgroundColor: AppTheme.error),
        );
      }
    }
  }

  Future<String?> _pickDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked == null) return null;
    return '${picked.year}-'
        '${picked.month.toString().padLeft(2, '0')}-'
        '${picked.day.toString().padLeft(2, '0')}';
  }
}

// ---------------------------------------------------------------------------
// _ProgramInfoCard
// ---------------------------------------------------------------------------

class _ProgramInfoCard extends StatelessWidget {
  const _ProgramInfoCard({required this.program});
  final Program program;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark 
          ? AppTheme.darkSurfaceContainer 
          : AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark 
            ? AppTheme.darkOutlineVariant 
            : AppTheme.slate200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _TypeBadge(label: program.programType.displayName),
              if (program.isVirtual) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.primary),
                  ),
                  child: const Text(
                    'Virtual',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primary),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          if (program.teamScope != null && program.teamScope != 'all') ...[
            Row(
              children: [
                Icon(Icons.group_outlined,
                    size: 14, 
                    color: isDark 
                      ? AppTheme.darkOnSurfaceVariant 
                      : AppTheme.slate500),
                const SizedBox(width: 6),
                Text(
                  'Scope: ${program.teamScope}',
                  style: TextStyle(
                      fontSize: 13, 
                      color: isDark 
                        ? AppTheme.darkOnSurfaceVariant 
                        : AppTheme.slate500),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          if (!program.isTBD &&
              program.startDate != null &&
              program.endDate != null) ...[
            Row(
              children: [
                Icon(Icons.date_range_outlined,
                    size: 14, 
                    color: isDark 
                      ? AppTheme.darkOnSurfaceVariant 
                      : AppTheme.slate500),
                const SizedBox(width: 6),
                Text(
                  '${program.startDate} → ${program.endDate}',
                  style: TextStyle(
                      fontSize: 13, 
                      color: isDark 
                        ? AppTheme.darkOnSurfaceVariant 
                        : AppTheme.slate500),
                ),
              ],
            ),
          ] else if (program.isTBD) ...[
            Row(
              children: [
                Icon(Icons.hourglass_empty,
                    size: 14, 
                    color: isDark 
                      ? AppTheme.darkOnSurfaceVariant 
                      : AppTheme.slate500),
                const SizedBox(width: 6),
                Text('Dates TBD',
                    style: TextStyle(
                        fontSize: 13, 
                        color: isDark 
                          ? AppTheme.darkOnSurfaceVariant 
                          : AppTheme.slate500)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.primaryBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppTheme.primary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _QuickCreateButton
// ---------------------------------------------------------------------------

class _QuickCreateButton extends StatelessWidget {
  const _QuickCreateButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.primary,
          side: const BorderSide(color: AppTheme.primary),
          padding:
              const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: onTap,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _SessionRow
// ---------------------------------------------------------------------------

class _SessionRow extends ConsumerWidget {
  const _SessionRow({
    required this.session,
    required this.onTap,
    required this.onDeleted,
  });

  final Session session;
  final VoidCallback onTap;
  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final timeRange = (session.startTime != null && session.endTime != null)
        ? '${session.startTime} – ${session.endTime}'
        : session.startTime ?? '';

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isDark 
            ? AppTheme.darkSurfaceContainer 
            : AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark 
              ? AppTheme.darkOutlineVariant 
              : AppTheme.slate200,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.calendar_today,
                          size: 12, 
                          color: isDark 
                            ? AppTheme.darkOnSurfaceVariant 
                            : AppTheme.slate500),
                      const SizedBox(width: 4),
                      Text(
                        session.date,
                        style: TextStyle(
                            fontSize: 12, 
                            color: isDark 
                              ? AppTheme.darkOnSurfaceVariant 
                              : AppTheme.slate500),
                      ),
                      if (timeRange.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Icon(Icons.schedule,
                            size: 12, 
                            color: isDark 
                              ? AppTheme.darkOnSurfaceVariant 
                              : AppTheme.slate500),
                        const SizedBox(width: 4),
                        Text(
                          timeRange,
                          style: TextStyle(
                              fontSize: 12, 
                              color: isDark 
                                ? AppTheme.darkOnSurfaceVariant 
                                : AppTheme.slate500),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  size: 18, color: AppTheme.error),
              onPressed: () => _confirmDelete(context, ref),
            ),
            Icon(Icons.chevron_right,
                size: 18, 
                color: isDark 
                  ? AppTheme.darkOnSurfaceVariant 
                  : AppTheme.slate500),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete session?'),
        content: Text(
            'Remove "${session.name}" on ${session.date}? This will also delete all attendance records.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete',
                style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(sessionServiceProvider).deleteSession(session.id);
      onDeleted();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }
}

// ---------------------------------------------------------------------------
// _SessionSheet — manual session creation
// ---------------------------------------------------------------------------

class _SessionSheet extends ConsumerStatefulWidget {
  const _SessionSheet(
      {required this.programId, required this.onCreated});
  final String programId;
  final VoidCallback onCreated;

  @override
  ConsumerState<_SessionSheet> createState() => _SessionSheetState();
}

class _SessionSheetState extends ConsumerState<_SessionSheet> {
  final _form = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _dateCtrl = TextEditingController();
  final _startCtrl = TextEditingController();
  final _endCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _dateCtrl.dispose();
    _startCtrl.dispose();
    _endCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null && mounted) {
      _dateCtrl.text = '${picked.year}-'
          '${picked.month.toString().padLeft(2, '0')}-'
          '${picked.day.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _pickTime(TextEditingController ctrl) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked != null && mounted) {
      ctrl.text =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(sessionServiceProvider).createSession(
            programId: widget.programId,
            name: _nameCtrl.text.trim(),
            date: _dateCtrl.text.trim(),
            startTime: _startCtrl.text.trim().isEmpty
                ? null
                : _startCtrl.text.trim(),
            endTime: _endCtrl.text.trim().isEmpty
                ? null
                : _endCtrl.text.trim(),
          );
      if (mounted) {
        Navigator.pop(context);
        widget.onCreated();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Session created'),
              backgroundColor: AppTheme.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'),
              backgroundColor: AppTheme.error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add Session',
                style: TextStyle(
                  fontSize: 18, 
                  fontWeight: FontWeight.w800,
                  color: isDark 
                    ? AppTheme.darkOnSurface 
                    : Colors.black,
                )),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameCtrl,
              decoration:
                  const InputDecoration(labelText: 'Session Name*'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Name required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _dateCtrl,
              readOnly: true,
              onTap: _pickDate,
              decoration: const InputDecoration(
                labelText: 'Date*',
                hintText: 'Tap to pick date',
                suffixIcon: Icon(Icons.calendar_today, size: 18),
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Date required' : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _startCtrl,
                    readOnly: true,
                    decoration: const InputDecoration(
                        labelText: 'Start Time (opt.)'),
                    onTap: () => _pickTime(_startCtrl),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _endCtrl,
                    readOnly: true,
                    decoration: const InputDecoration(
                        labelText: 'End Time (opt.)'),
                    onTap: () => _pickTime(_endCtrl),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 48),
                ),
                child: _saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Text('Create Session',
                        style:
                            TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
