// lib/features/auth/profile_picker_screen.dart
//
// Netflix-style profile picker.
// Grid: individual Team Lead tiles + one "Assistant" group tile + one "+" Add tile.
// Background: video loop → image slideshow → gradient fallback.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../app_theme/app_theme.dart';
import '../../models/enums.dart';
import '../../models/staff_user.dart';
import '../../providers/auth_provider.dart';
import '../../services/auth_service.dart';

// ---------------------------------------------------------------------------
// Staff list provider — autoDispose so it always re-fetches on screen entry.
// This fixes the isFirstLogin caching bug after a password is set the first time.
// ---------------------------------------------------------------------------

final _staffListProvider = FutureProvider.autoDispose<List<StaffUser>>((ref) {
  return ref.read(authServiceProvider).getStaffUsers();
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class ProfilePickerScreen extends ConsumerWidget {
  const ProfilePickerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staffAsync = ref.watch(_staffListProvider);
    final loggedInUser = ref.watch(currentStaffProvider).valueOrNull;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1020),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Full-screen background ─────────────────────────────────────
          const _Background(),

          // ── Netflix scrim: transparent top → opaque dark bottom ────────
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.0, 0.28, 0.52, 1.0],
                colors: [
                  Colors.transparent,
                  Colors.transparent,
                  Color(0xD0070D1A),
                  Color(0xFF070D1A),
                ],
              ),
            ),
          ),

          // ── UI ──────────────────────────────────────────────────────────
          SafeArea(
            child: Column(
              children: [
                const Spacer(),

                // Heading
                const Text(
                  'Choose Your Profile',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 20),

                // Grid
                staffAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: CircularProgressIndicator(color: Colors.white54),
                  ),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 32, horizontal: 32),
                    child: Text(
                      'Could not load team leads.\n$e',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 13),
                    ),
                  ),
                  data: (staff) =>
                      _buildGrid(context, ref, staff, loggedInUser),
                ),

                // Sign out — only when someone is active
                if (loggedInUser != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: TextButton(
                      onPressed: () =>
                          _confirmSignOut(context, ref, loggedInUser),
                      child: Text(
                        'Sign out ${loggedInUser.fullName.split(' ').first}',
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 13),
                      ),
                    ),
                  ),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Grid builder ──────────────────────────────────────────────────────────

  Widget _buildGrid(BuildContext context, WidgetRef ref,
      List<StaffUser> staff, StaffUser? loggedInUser) {
    final leads =
        staff.where((s) => s.role == StaffRole.teamLead).toList();
    final assistants =
        staff.where((s) => s.role == StaffRole.assistant).toList();
    final hasAssistants = assistants.isNotEmpty;
    final itemCount =
        leads.length + (hasAssistants ? 1 : 0) + 1; // +1 for add tile

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 16,
          crossAxisSpacing: 12,
          childAspectRatio: 0.70,
        ),
        itemCount: itemCount,
        itemBuilder: (ctx, i) {
          // Team lead tiles
          if (i < leads.length) {
            final user = leads[i];
            return _ProfileTile(
              user: user,
              isActive: loggedInUser?.id == user.id,
              onTap: () => _handleTap(context, ref, user),
            );
          }
          // Assistant group tile
          if (hasAssistants && i == leads.length) {
            return _AssistantGroupTile(
              assistants: assistants,
              loggedInUserId: loggedInUser?.id,
              onSelect: (u) => _handleTap(context, ref, u),
              onLogout: loggedInUser != null &&
                      assistants.any((a) => a.id == loggedInUser.id)
                  ? () => ref
                      .read(currentStaffProvider.notifier)
                      .logout()
                  : null,
            );
          }
          // "+" Add team lead tile
          return _AddTile(
            canAdd: loggedInUser?.role == StaffRole.teamLead || leads.isEmpty,
            onTap: () => _showAddSheet(context, ref),
          );
        },
      ),
    );
  }

  // ── Tap handlers ─────────────────────────────────────────────────────────

  void _handleTap(BuildContext context, WidgetRef ref, StaffUser user) async {
    // Already active — just enter the app
    if (ref.read(currentStaffProvider).valueOrNull?.id == user.id) {
      context.go('/home');
      return;
    }
    final isRecent =
        await ref.read(authServiceProvider).isLoginRecent(user.id);
    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      builder: (_) => _LoginDialog(
        user: user,
        ref: ref,
        isRecentLogin: isRecent,
      ),
    );
  }

  void _showAddSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddStaffSheet(
        onAdded: () => ref.invalidate(_staffListProvider),
      ),
    );
  }

  void _confirmSignOut(
      BuildContext context, WidgetRef ref, StaffUser user) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Sign out?'),
        content: Text(
            'Sign out ${user.fullName}? Another team member can then sign in.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(currentStaffProvider.notifier).logout();
            },
            child: const Text('Sign Out',
                style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Individual team-lead profile tile (square, rounded corners)
// ---------------------------------------------------------------------------

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.user,
    required this.isActive,
    required this.onTap,
  });

  final StaffUser user;
  final bool isActive;
  final VoidCallback onTap;

  String get _initials {
    final parts = user.fullName.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return user.fullName.isEmpty ? '?' : user.fullName[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: isActive
                    ? Border.all(color: AppTheme.primary, width: 3)
                    : Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                        width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(isActive ? 9 : 11),
                child: user.avatarUrl != null &&
                        user.avatarUrl!.isNotEmpty
                    ? Image.network(
                        user.avatarUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _initialsBox(),
                      )
                    : _initialsBox(),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            user.fullName,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isActive ? Colors.white : Colors.white70,
              fontSize: 12,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          if (isActive)
            Container(
              margin: const EdgeInsets.only(top: 3),
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Active',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }

  Widget _initialsBox() {
    final hue =
        (user.fullName.codeUnits.fold(0, (a, b) => a + b) % 360).toDouble();
    return ColoredBox(
      color: HSLColor.fromAHSL(1, hue, 0.45, 0.28).toColor(),
      child: Center(
        child: Text(
          _initials,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Assistant group tile — like Netflix "Kids", reveals a wheel picker on tap
// ---------------------------------------------------------------------------

class _AssistantGroupTile extends StatelessWidget {
  const _AssistantGroupTile({
    required this.assistants,
    required this.loggedInUserId,
    required this.onSelect,
    this.onLogout,
  });

  final List<StaffUser> assistants;
  final String? loggedInUserId;
  final void Function(StaffUser) onSelect;
  final VoidCallback? onLogout;

  bool get _hasActive =>
      assistants.any((a) => a.id == loggedInUserId);

  StaffUser? get _activeAssistant =>
      assistants.where((a) => a.id == loggedInUserId).firstOrNull;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showPicker(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF7C3AED), Color(0xFF1D4ED8)],
                ),
                border: _hasActive
                    ? Border.all(color: AppTheme.primary, width: 3)
                    : Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                        width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(_hasActive ? 9 : 11),
                child: _hasActive &&
                        _activeAssistant?.avatarUrl != null &&
                        _activeAssistant!.avatarUrl!.isNotEmpty
                    ? Image.network(
                        _activeAssistant!.avatarUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _icon(),
                      )
                    : _icon(),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _hasActive
                ? _activeAssistant!.fullName.split(' ').first
                : 'Assistant',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _hasActive ? Colors.white : Colors.white70,
              fontSize: 12,
              fontWeight: _hasActive ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          if (_hasActive)
            Container(
              margin: const EdgeInsets.only(top: 3),
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Active',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }

  Widget _icon() => const Center(
        child: Icon(Icons.people_alt_rounded,
            color: Colors.white70, size: 36),
      );

  void _showPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _AssistantPickerSheet(
        assistants: assistants,
        activeId: loggedInUserId,
        onLogout: onLogout,
        onSelect: (selected) {
          Navigator.pop(context);
          onSelect(selected);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Wheel/drum-roll picker for selecting an assistant
// ---------------------------------------------------------------------------

class _AssistantPickerSheet extends StatefulWidget {
  const _AssistantPickerSheet({
    required this.assistants,
    required this.activeId,
    required this.onSelect,
    this.onLogout,
  });

  final List<StaffUser> assistants;
  final String? activeId;
  final void Function(StaffUser) onSelect;
  final VoidCallback? onLogout;

  @override
  State<_AssistantPickerSheet> createState() =>
      _AssistantPickerSheetState();
}

class _AssistantPickerSheetState
    extends State<_AssistantPickerSheet> {
  late int _selectedIndex;
  late final FixedExtentScrollController _ctrl;

  @override
  void initState() {
    super.initState();
    final idx =
        widget.assistants.indexWhere((a) => a.id == widget.activeId);
    _selectedIndex = idx >= 0 ? idx : 0;
    _ctrl = FixedExtentScrollController(initialItem: _selectedIndex);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
      decoration: const BoxDecoration(
        color: Color(0xFF1A2940),
        borderRadius: BorderRadius.all(Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Select Assistant',
            style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 20),

          // Wheel picker
          SizedBox(
            height: 220,
            child: Stack(
              children: [
                // Centre-highlight band
                Center(
                  child: Container(
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                ListWheelScrollView.useDelegate(
                  controller: _ctrl,
                  onSelectedItemChanged: (i) =>
                      setState(() => _selectedIndex = i),
                  itemExtent: 56,
                  perspective: 0.003,
                  diameterRatio: 1.6,
                  physics: const FixedExtentScrollPhysics(),
                  childDelegate: ListWheelChildListDelegate(
                    children: List.generate(
                      widget.assistants.length,
                      (i) => _PickerRow(
                        user: widget.assistants[i],
                        isSelected: i == _selectedIndex,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () =>
                  widget.onSelect(widget.assistants[_selectedIndex]),
              child: const Text('Select'),
            ),
          ),
          if (widget.onLogout != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  widget.onLogout!();
                },
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white38,
                ),
                child: const Text('Sign Out'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({required this.user, required this.isSelected});

  final StaffUser user;
  final bool isSelected;

  String get _initials {
    final parts = user.fullName.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return user.fullName.isEmpty ? '?' : user.fullName[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final hue =
        (user.fullName.codeUnits.fold(0, (a, b) => a + b) % 360).toDouble();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          // Mini square avatar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 36,
              height: 36,
              child: user.avatarUrl != null &&
                      user.avatarUrl!.isNotEmpty
                  ? Image.network(user.avatarUrl!, fit: BoxFit.cover)
                  : ColoredBox(
                      color: HSLColor.fromAHSL(1, hue, 0.45, 0.28)
                          .toColor(),
                      child: Center(
                        child: Text(
                          _initials,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              user.fullName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white54,
                fontSize: 15,
                fontWeight:
                    isSelected ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
          if (isSelected)
            const Icon(Icons.check_circle_rounded,
                color: AppTheme.primary, size: 18),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// "+" Add staff tile — dimmed unless a team lead is logged in
// ---------------------------------------------------------------------------

class _AddTile extends StatelessWidget {
  const _AddTile({required this.canAdd, required this.onTap});

  final bool canAdd;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: canAdd
          ? onTap
          : () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content:
                      Text('Sign in as Team Lead to add a team lead.'),
                  duration: Duration(seconds: 2),
                ),
              ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.white
                    .withValues(alpha: canAdd ? 0.10 : 0.04),
                border: Border.all(
                  color: Colors.white
                      .withValues(alpha: canAdd ? 0.22 : 0.08),
                  width: 1,
                ),
              ),
              child: Icon(
                Icons.person_add_alt_1_rounded,
                color: Colors.white
                    .withValues(alpha: canAdd ? 0.60 : 0.22),
                size: 30,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add Team Lead',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white
                  .withValues(alpha: canAdd ? 0.54 : 0.22),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Login dialog — first login (set password), returning login, 2-week notice
// ---------------------------------------------------------------------------

class _LoginDialog extends StatefulWidget {
  const _LoginDialog({
    required this.user,
    required this.ref,
    required this.isRecentLogin,
  });

  final StaffUser user;
  final WidgetRef ref;

  /// True when the last login was within the past 14 days.
  final bool isRecentLogin;

  @override
  State<_LoginDialog> createState() => _LoginDialogState();
}

class _LoginDialogState extends State<_LoginDialog> {
  final _pwCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _obscurePw = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _pwCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final password = _pwCtrl.text.trim();
    if (password.length < 4) {
      setState(() => _error = 'Password must be at least 4 characters.');
      return;
    }
    if (widget.user.isFirstLogin &&
        password != _confirmCtrl.text.trim()) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final service = widget.ref.read(authServiceProvider);
    try {
      if (widget.user.isFirstLogin) {
        await service.setPassword(widget.user.id, password);
      } else {
        final ok =
            await service.checkPassword(widget.user.id, password);
        if (!ok) {
          setState(() {
            _error = 'Incorrect password. Please try again.';
            _loading = false;
          });
          return;
        }
      }
      await widget.ref
          .read(currentStaffProvider.notifier)
          .login(widget.user.id);
      if (mounted) {
        Navigator.of(context).pop();
        context.go('/home');
      }
    } catch (_) {
      setState(() {
        _error = 'Something went wrong. Please try again.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isFirst = widget.user.isFirstLogin;
    final showWelcomeBack = !isFirst && !widget.isRecentLogin;

    return Dialog(
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: const Color(0xFF1A2940),
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Square avatar
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 72,
                    height: 72,
                    child: widget.user.avatarUrl != null &&
                            widget.user.avatarUrl!.isNotEmpty
                        ? Image.network(widget.user.avatarUrl!,
                            fit: BoxFit.cover)
                        : _initialsBox(),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  widget.user.fullName,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700),
                ),

                // Context message
                if (isFirst)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'Create a password to activate your account.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Colors.white54, fontSize: 12),
                    ),
                  )
                else if (showWelcomeBack)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color:
                          AppTheme.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      "It's been a while! Please re-enter your password.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: AppTheme.amber, fontSize: 11),
                    ),
                  ),

                const SizedBox(height: 20),

                // Password field
                _pwField(
                  controller: _pwCtrl,
                  hint: isFirst ? 'New password' : 'Password',
                  obscure: _obscurePw,
                  onToggle: () =>
                      setState(() => _obscurePw = !_obscurePw),
                  onSubmit: isFirst ? null : (_) => _submit(),
                ),

                // Confirm (first login only)
                if (isFirst) ...[
                  const SizedBox(height: 12),
                  _pwField(
                    controller: _confirmCtrl,
                    hint: 'Confirm password',
                    obscure: _obscureConfirm,
                    onToggle: () => setState(
                        () => _obscureConfirm = !_obscureConfirm),
                    onSubmit: (_) => _submit(),
                  ),
                ],

                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Color(0xFFFF6B6B), fontSize: 12),
                  ),
                ],
                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : Text(
                            isFirst
                                ? 'Set Password & Log In'
                                : 'Log In',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 15),
                          ),
                  ),
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel',
                      style: TextStyle(
                          color: Colors.white38, fontSize: 13)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _initialsBox() {
    final parts =
        widget.user.fullName.trim().split(RegExp(r'\s+'));
    final initials = parts.length >= 2
        ? '${parts.first[0]}${parts.last[0]}'.toUpperCase()
        : widget.user.fullName.isEmpty
            ? '?'
            : widget.user.fullName[0].toUpperCase();
    final hue =
        (widget.user.fullName.codeUnits.fold(0, (a, b) => a + b) % 360)
            .toDouble();
    return ColoredBox(
      color: HSLColor.fromAHSL(1, hue, 0.45, 0.28).toColor(),
      child: Center(
        child: Text(initials,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _pwField({
    required TextEditingController controller,
    required String hint,
    required bool obscure,
    required VoidCallback onToggle,
    ValueChanged<String>? onSubmit,
  }) =>
      TextField(
        controller: controller,
        obscureText: obscure,
        style: const TextStyle(color: Colors.white),
        onSubmitted: onSubmit,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white38),
          filled: true,
          fillColor: const Color(0xFF243450),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          suffixIcon: IconButton(
            icon: Icon(
              obscure ? Icons.visibility_off : Icons.visibility,
              color: Colors.white38,
              size: 20,
            ),
            onPressed: onToggle,
          ),
        ),
      );
}

// ---------------------------------------------------------------------------
// Add Staff sheet — accessible from picker, no auth required for initial setup
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
              style: TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 18)),
          const SizedBox(height: 20),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Full name',
              hintText: 'e.g. John Doe',
            ),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 20),
          const Text('Team',
              style: TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [Team.teamA, Team.teamB, Team.teamC]
                .map((t) => ChoiceChip(
                      label: Text(t.value),
                      selected: _team == t,
                      onSelected: (_) => setState(() => _team = t),
                    ))
                .toList(),
          ),
          const SizedBox(height: 20),
          const Text('Role',
              style: TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: StaffRole.values
                .map((r) => ChoiceChip(
                      label: Text(r.displayName),
                      selected: _role == r,
                      onSelected: (_) => setState(() => _role = r),
                    ))
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
                          color: Colors.white, strokeWidth: 2))
                  : const Text('Add Team Lead'),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Background: video loop → image slideshow → gradient fallback
// ---------------------------------------------------------------------------

class _Background extends StatefulWidget {
  const _Background();

  @override
  State<_Background> createState() => _BackgroundState();
}

class _BackgroundState extends State<_Background> {
  static const _videoPath = 'assets/videos/bg.mp4';
  static const _images = <String>[
    'assets/images/bg1.jpg',
    'assets/images/bg2.jpg',
    'assets/images/bg3.jpg',
  ];

  VideoPlayerController? _videoController;
  bool _videoReady = false;
  int _current = 0;
  Timer? _timer;
  bool _hasImages = false;

  @override
  void initState() {
    super.initState();
    _initBackground();
  }

  Future<void> _initBackground() async {
    try {
      await rootBundle.load(_videoPath);
      final controller = VideoPlayerController.asset(_videoPath);
      await controller.initialize();
      controller.setLooping(true);
      controller.setVolume(0);
      controller.play();
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() {
        _videoController = controller;
        _videoReady = true;
      });
      return;
    } catch (_) {
      // No video — fall through
    }
    try {
      await rootBundle.load(_images[0]);
    } catch (_) {
      return; // gradient fallback
    }
    if (!mounted) return;
    setState(() => _hasImages = true);
    _timer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (mounted) {
        setState(() => _current = (_current + 1) % _images.length);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_videoReady && _videoController != null) {
      return SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: _videoController!.value.size.width,
            height: _videoController!.value.size.height,
            child: VideoPlayer(_videoController!),
          ),
        ),
      );
    }
    if (_hasImages) {
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 1200),
        child: Image.asset(
          _images[_current],
          key: ValueKey(_current),
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        ),
      );
    }
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF1A1060),
            Color(0xFF0D1B2A),
            Color(0xFF050D17),
          ],
          stops: [0.0, 0.5, 1.0],
        ),
      ),
    );
  }
}
