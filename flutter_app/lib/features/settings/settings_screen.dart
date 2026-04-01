// lib/features/settings/settings_screen.dart
//
// Mirrors app/(dashboard)/settings/page.tsx

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import '../../app_theme/app_theme.dart';
import '../../models/enums.dart';
import '../../models/staff_user.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/auth_service.dart';
import '../../widgets/avatar_widget.dart';

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

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
    final brightness = ref.watch(brightnessProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Dark mode toggle ────────────────────────────────────────
              _card(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Dark mode',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15)),
                        const SizedBox(height: 4),
                        Text(
                          brightness == Brightness.dark ? 'ON' : 'OFF',
                          style: TextStyle(
                            fontSize: 12,
                            color: brightness == Brightness.dark
                                ? AppTheme.success
                                : const Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                    Switch(
                      value: brightness == Brightness.dark,
                      activeThumbColor: AppTheme.primary,
                      onChanged: (v) {
                        ref
                            .read(brightnessProvider.notifier)
                            .setBrightness(
                                v ? Brightness.dark : Brightness.light);
                      },
                    ),
                  ],
                ),
              ),

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
    );
  }

  static Widget _card(
      {required Widget child, bool isDark = false}) => 
      Builder(builder: (ctx) {
        final dark = isDark || Theme.of(ctx).brightness == Brightness.dark;
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: dark ? AppTheme.darkSurfaceContainer : Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: dark
                      ? Colors.black.withValues(alpha: 0.2)
                      : Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8)
            ],
          ),
          child: child,
        );
      });
}

// ---------------------------------------------------------------------------
// _StaffManagementCard
// ---------------------------------------------------------------------------

class _StaffManagementCard extends ConsumerWidget {
  const _StaffManagementCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staffAsync = ref.watch(_staffProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurfaceContainer : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.2)
                  : Colors.black.withValues(alpha: 0.04),
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
            error: (e, _) => const Text('Unable to load team leads. Please try again.',
                style: TextStyle(
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
