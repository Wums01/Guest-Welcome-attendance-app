// lib/features/programs/programs_screen.dart
//
// Stitch UI redesign — Mirrors app/(dashboard)/programs/page.tsx
//
// AppBar: calendar icon tile left, "Programs" title centered, 3-dot menu right.
// Search bar, type filter chips (All / Weekly / Monthly), program cards with
// typed icon tile, type badge pill, session count, pencil icon.
// FAB opens _CreateProgramForm in a bottom sheet.

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
// Providers
// ---------------------------------------------------------------------------

final programsProvider = FutureProvider<List<Program>>((ref) {
  return ref.read(programServiceProvider).getPrograms();
});

final _sessionsByProgramProvider =
    FutureProvider.family<List<Session>, String>((ref, programId) {
  return ref.read(sessionServiceProvider).getSessionsByProgram(programId);
});

// ---------------------------------------------------------------------------
// Helpers — icon / colour per ProgramType
// ---------------------------------------------------------------------------

IconData _typeIcon(ProgramType t) {
  switch (t) {
    case ProgramType.sunday:
      return Icons.wb_sunny_outlined;
    case ProgramType.wednesday:
      return Icons.book_outlined;
    case ProgramType.program:
      return Icons.people_outlined;
    case ProgramType.meeting:
      return Icons.celebration_outlined;
    case ProgramType.training:
      return Icons.nightlight_outlined;
  }
}

Color _typeIconBg(ProgramType t, bool isDark) {
  if (isDark) {
    switch (t) {
      case ProgramType.sunday:
        return const Color(0xFF4A3C2A); // dark orange
      case ProgramType.wednesday:
        return const Color(0xFF0A1128); // dark blue
      case ProgramType.program:
        return const Color(0xFF0F3D1A); // dark green
      case ProgramType.meeting:
        return const Color(0xFF3D0D1F); // dark pink
      case ProgramType.training:
        return const Color(0xFF2D1B4A); // dark purple
    }
  }
  switch (t) {
    case ProgramType.sunday:
      return const Color(0xFFFFF7ED);
    case ProgramType.wednesday:
      return const Color(0xFFEFF6FF);
    case ProgramType.program:
      return const Color(0xFFF0FDF4);
    case ProgramType.meeting:
      return const Color(0xFFFFF1F2);
    case ProgramType.training:
      return const Color(0xFFF5F3FF);
  }
}

Color _typeIconColor(ProgramType t, bool isDark) {
  if (isDark) {
    switch (t) {
      case ProgramType.sunday:
        return const Color(0xFFD4A574); // light orange
      case ProgramType.wednesday:
        return AppTheme.darkPrimary;
      case ProgramType.program:
        return const Color(0xFF4ADE80); // light green
      case ProgramType.meeting:
        return const Color(0xFFFF6B9D); // light pink
      case ProgramType.training:
        return const Color(0xFFC084FC); // light purple
    }
  }
  switch (t) {
    case ProgramType.sunday:
      return const Color(0xFFEA580C);
    case ProgramType.wednesday:
      return AppTheme.primary;
    case ProgramType.program:
      return const Color(0xFF16A34A);
    case ProgramType.meeting:
      return const Color(0xFFE11D48);
    case ProgramType.training:
      return const Color(0xFF7C3AED);
  }
}

/// Chip label for a program type — maps types into two buckets.
String _typeChipLabel(ProgramType t) {
  switch (t) {
    case ProgramType.sunday:
    case ProgramType.wednesday:
      return 'Weekly';
    default:
      return 'Monthly';
  }
}

// ---------------------------------------------------------------------------
// ProgramsScreen
// ---------------------------------------------------------------------------

class ProgramsScreen extends ConsumerStatefulWidget {
  const ProgramsScreen({super.key});

  @override
  ConsumerState<ProgramsScreen> createState() => _ProgramsScreenState();
}

class _ProgramsScreenState extends ConsumerState<ProgramsScreen> {
  String _search = '';
  // 'all' | 'weekly' | 'monthly'
  String _filterTab = 'all';
  // Sort mode: 'latest' | 'oldest' | 'name'
  String _sortMode = 'latest';

  List<Program> _applyFilters(List<Program> programs) {
    var list = programs;
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list.where((p) => p.title.toLowerCase().contains(q)).toList();
    }
    if (_filterTab == 'weekly') {
      list = list
          .where((p) =>
              p.programType == ProgramType.sunday ||
              p.programType == ProgramType.wednesday)
          .toList();
    } else if (_filterTab == 'monthly') {
      list = list
          .where((p) =>
              p.programType == ProgramType.program ||
              p.programType == ProgramType.meeting ||
              p.programType == ProgramType.training)
          .toList();
    }
    // Apply sort
    switch (_sortMode) {
      case 'oldest':
        list = [...list]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      case 'name':
        list = [...list]..sort((a, b) => a.title.compareTo(b.title));
      default: // 'latest' — already ordered by createdAt desc from DB
        break;
    }
    return list;
  }

  void _showSortSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        return SafeArea(
          child: StatefulBuilder(builder: (ctx, setLocal) {
            Widget option(String mode, String label, IconData icon) {
              final selected = _sortMode == mode;
              final selectedColor =
                  isDark ? AppTheme.darkPrimary : AppTheme.primary;
              return ListTile(
                leading: Icon(icon, color: selected ? selectedColor : null),
                title: Text(label,
                    style: TextStyle(
                        color: selected ? selectedColor : null,
                        fontWeight: selected
                            ? FontWeight.bold
                            : FontWeight.normal)),
                trailing: selected
                    ? Icon(Icons.check, color: selectedColor)
                    : null,
                onTap: () {
                  setState(() => _sortMode = mode);
                  Navigator.of(context).pop();
                },
              );
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                const ListTile(
                  title: Text('Sort Programs',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                const Divider(height: 1),
                option('latest', 'Latest first', Icons.arrow_downward),
                option('oldest', 'Oldest first', Icons.arrow_upward),
                option('name', 'Name A–Z', Icons.sort_by_alpha),
                const SizedBox(height: 8),
              ],
            );
          }),
        );
      },
    );
  }

  void _openCreateSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppTheme.darkSurfaceContainer : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: _CreateProgramForm(
              onCreated: () {
                Navigator.pop(ctx);
                ref.invalidate(programsProvider);
              },
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final programsAsync = ref.watch(programsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkSurface : AppTheme.background,
      appBar: AppBar(
        backgroundColor: isDark ? AppTheme.darkSurfaceContainer : AppTheme.surface,
        centerTitle: true,
        leading: GestureDetector(
          onTap: () => context.push('/sessions'),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppTheme.primaryBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.calendar_month_outlined,
                  color: AppTheme.primary, size: 20),
            ),
          ),
        ),
        title: const Text('Programs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: _showSortSheet,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: isDark ? AppTheme.darkPrimary : AppTheme.primary,
        onPressed: _openCreateSheet,
        child: Icon(Icons.add,
            color: isDark ? AppTheme.darkPrimaryContainer : Colors.white),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(programsProvider),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Search bar ────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: TextField(
                  onChanged: (v) => setState(() => _search = v),
                  decoration: const InputDecoration(
                    hintText: 'Search programs by name...',
                    prefixIcon: Icon(Icons.search,
                        color: AppTheme.slate500, size: 20),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // ── Filter chips ──────────────────────────────────────────
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _FilterChip(
                      label: 'All Programs',
                      selected: _filterTab == 'all',
                      onTap: () => setState(() => _filterTab = 'all'),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: 'Weekly',
                      selected: _filterTab == 'weekly',
                      onTap: () => setState(() => _filterTab = 'weekly'),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: 'Monthly',
                      selected: _filterTab == 'monthly',
                      onTap: () => setState(() => _filterTab = 'monthly'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // ── Programs list ─────────────────────────────────────────
              Expanded(
                child: programsAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
            error: (e, _) => const Center(child: Text('Unable to load programs. Please try again.')),
                  data: (programs) {
                    final filtered = _applyFilters(programs);
                    if (filtered.isEmpty) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Text(
                            'No programs found.',
                            style: TextStyle(color: AppTheme.slate500),
                          ),
                        ),
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 10),
                      itemBuilder: (ctx, i) => _ProgramCard(
                        program: filtered[i],
                        onDeleted: () => ref.invalidate(programsProvider),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _FilterChip
// ---------------------------------------------------------------------------

class _FilterChip extends StatelessWidget {
  const _FilterChip({
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
            color:
                selected ? AppTheme.primary : AppTheme.slate200,
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

// ---------------------------------------------------------------------------
// _ProgramCard
// ---------------------------------------------------------------------------

class _ProgramCard extends ConsumerWidget {
  const _ProgramCard({required this.program, required this.onDeleted});
  final Program program;
  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sessionsAsync =
        ref.watch(_sessionsByProgramProvider(program.id));
    final sessionCount = sessionsAsync.maybeWhen(
      data: (s) => s.length,
      orElse: () => 0,
    );

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => context.push('/programs/${program.id}'),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkSurfaceContainer : AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? AppTheme.darkOutlineVariant : AppTheme.slate200,
          ),
        ),
        child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _typeIconBg(program.programType, isDark),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            _typeIcon(program.programType),
            color: _typeIconColor(program.programType, isDark),
            size: 20,
          ),
        ),
        title: Text(
          program.title,
          style: const TextStyle(
              fontWeight: FontWeight.w700, fontSize: 14),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              _TypeBadge(label: _typeChipLabel(program.programType)),
              if (program.isVirtual) ...[
                const SizedBox(width: 6),
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
              const SizedBox(width: 6),
              Text(
                '• $sessionCount session${sessionCount == 1 ? '' : 's'}',
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.slate500),
              ),
            ],
          ),
        ),
        trailing: IconButton(
          icon: Icon(Icons.edit_outlined,
              size: 18,
              color: isDark
                  ? AppTheme.darkOnSurfaceVariant
                  : AppTheme.slate500),
          onPressed: () => _showOptionsSheet(context, ref),
        ),
      ),     // close ListTile
      ),     // close Container
    );       // close InkWell
  }

  void _showOptionsSheet(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor:
          isDark ? AppTheme.darkSurfaceContainer : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark
                    ? AppTheme.darkOutlineVariant
                    : AppTheme.slate200,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: const Text('Add Session'),
              onTap: () {
                Navigator.pop(ctx);
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  shape: const RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  builder: (_) => _AddSessionSheet(programId: program.id),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline,
                  color: AppTheme.error),
              title: const Text('Delete program',
                  style: TextStyle(color: AppTheme.error)),
              onTap: () {
                Navigator.pop(ctx);
                _delete(context, ref);
              },
            ),
            ListTile(
              leading: const Icon(Icons.close, color: AppTheme.slate500),
              title: const Text('Cancel'),
              onTap: () => Navigator.pop(ctx),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete program?'),
        content: const Text(
            'This will also delete all sessions and attendance records for this program.'),
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
      await ref.read(programServiceProvider).deleteProgram(program.id);
      onDeleted();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to delete program. Please try again.')),
        );
      }
    }
  }
}

// ---------------------------------------------------------------------------
// _TypeBadge — pill label for program type
// ---------------------------------------------------------------------------

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.primaryBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppTheme.primary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _CreateProgramForm  (unchanged business logic, only minor layout tweaks)
// ---------------------------------------------------------------------------

class _CreateProgramForm extends ConsumerStatefulWidget {
  const _CreateProgramForm({required this.onCreated});
  final VoidCallback onCreated;

  @override
  ConsumerState<_CreateProgramForm> createState() =>
      _CreateProgramFormState();
}

class _CreateProgramFormState
    extends ConsumerState<_CreateProgramForm> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _startCtrl = TextEditingController();
  final _endCtrl = TextEditingController();

  ProgramType _type = ProgramType.sunday;
  String _teamScope = 'all';
  bool _isTBD = false;
  bool _isVirtual = false;
  bool _loading = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _startCtrl.dispose();
    _endCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate(TextEditingController ctrl) async {
    DateTime initial = DateTime.now();
    if (ctrl.text.isNotEmpty) {
      try { initial = DateTime.parse(ctrl.text); } catch (_) {}
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null && mounted) {
      ctrl.text = '${picked.year}-'
          '${picked.month.toString().padLeft(2, '0')}-'
          '${picked.day.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _loading = true);
    try {
      await ref.read(programServiceProvider).createProgram(
            title: _titleCtrl.text.trim(),
            programType: _type,
            teamScope: _teamScope,
            isTBD: _isTBD,
            startDate: _isTBD ? null : _startCtrl.text.trim(),
            endDate: _isTBD ? null : _endCtrl.text.trim(),
            isVirtual: _isVirtual,
          );
      widget.onCreated();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Unable to create program. Please try again.'),
              backgroundColor: AppTheme.error),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Create program',
              style:
                  TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 16),
          TextFormField(
            controller: _titleCtrl,
            decoration:
                const InputDecoration(hintText: 'Program title'),
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'Title is required'
                : null,
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<ProgramType>(
            initialValue: _type,
            items: ProgramType.values
                .map((t) => DropdownMenuItem(
                    value: t, child: Text(t.displayName)))
                .toList(),
            onChanged: (v) => setState(() => _type = v!),
            decoration: const InputDecoration(labelText: 'Type'),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _teamScope,
            items: ['all', 'Team A', 'Team B', 'Team C']
                .map((v) =>
                    DropdownMenuItem(value: v, child: Text(v)))
                .toList(),
            onChanged: (v) => setState(() => _teamScope = v!),
            decoration: const InputDecoration(labelText: 'Team scope'),
          ),
          if (_type == ProgramType.meeting ||
              _type == ProgramType.training) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Virtual Meeting',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
                Switch(
                  value: _isVirtual,
                  activeThumbColor: AppTheme.primary,
                  onChanged: (v) => setState(() => _isVirtual = v),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Switch(
                  value: _isTBD,
                  onChanged: (v) => setState(() => _isTBD = v),
                  activeThumbColor: AppTheme.primary),
              const SizedBox(width: 8),
              const Text('Dates TBD',
                  style: TextStyle(fontWeight: FontWeight.w500)),
            ],
          ),
          if (!_isTBD) ...[
            const SizedBox(height: 10),
            TextFormField(
              controller: _startCtrl,
              readOnly: true,
              onTap: () => _pickDate(_startCtrl),
              decoration: const InputDecoration(
                hintText: 'Tap to pick start date',
                suffixIcon: Icon(Icons.calendar_today, size: 18),
              ),
              validator: (v) =>
                  (!_isTBD && (v == null || v.isEmpty)) ? 'Start date required' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _endCtrl,
              readOnly: true,
              onTap: () => _pickDate(_endCtrl),
              decoration: const InputDecoration(
                hintText: 'Tap to pick end date',
                suffixIcon: Icon(Icons.calendar_today, size: 18),
              ),
              validator: (v) =>
                  (!_isTBD && (v == null || v.isEmpty)) ? 'End date required' : null,
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Create program'),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _AddSessionSheet — Create a session for a custom program/meeting
// ---------------------------------------------------------------------------
class _AddSessionSheet extends ConsumerStatefulWidget {
  const _AddSessionSheet({required this.programId});
  final String programId;

  @override
  ConsumerState<_AddSessionSheet> createState() => _AddSessionSheetState();
}

class _AddSessionSheetState extends ConsumerState<_AddSessionSheet> {
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

  Future<void> _pickTime(TextEditingController ctrl) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked != null) {
      ctrl.text =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _pickSessionDate() async {
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
            endTime:
                _endCtrl.text.trim().isEmpty ? null : _endCtrl.text.trim(),
          );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Session created'),
              backgroundColor: AppTheme.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Unable to create session. Please try again.'),
              backgroundColor: AppTheme.error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        left: 16,
        right: 16,
        top: 20,
      ),
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Add Session',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Session Name*'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Name required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _dateCtrl,
              readOnly: true,
              onTap: _pickSessionDate,
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
                    decoration:
                        const InputDecoration(labelText: 'End Time (opt.)'),
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
                        style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
