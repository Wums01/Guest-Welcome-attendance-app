// lib/features/auth/staff_profile_screen.dart
//
// Profile management screen for the currently logged-in staff member.
// Allows: avatar upload, name edit, password change.
// Team and role are read-only.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app_theme/app_theme.dart';
import '../../models/staff_user.dart';
import '../../providers/auth_provider.dart';
import '../../services/auth_service.dart';

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class StaffProfileScreen extends ConsumerWidget {
  const StaffProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staffAsync = ref.watch(currentStaffProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0D1020),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1020),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'My Profile',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: staffAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text('Error: $e', style: const TextStyle(color: Colors.red)),
        ),
        data: (staff) {
          if (staff == null) {
            return const Center(
              child: Text('Not logged in.', style: TextStyle(color: Colors.white70)),
            );
          }
          return _ProfileBody(staff: staff);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Profile body
// ---------------------------------------------------------------------------

class _ProfileBody extends ConsumerStatefulWidget {
  const _ProfileBody({required this.staff});
  final StaffUser staff;

  @override
  ConsumerState<_ProfileBody> createState() => _ProfileBodyState();
}

class _ProfileBodyState extends ConsumerState<_ProfileBody> {
  final _nameKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  bool _editingName = false;
  bool _savingName = false;

  // Password fields
  final _pwKey = GlobalKey<FormState>();
  final _currentPwCtrl = TextEditingController();
  final _newPwCtrl = TextEditingController();
  final _confirmPwCtrl = TextEditingController();
  bool _savingPw = false;
  bool _showCurrentPw = false;
  bool _showNewPw = false;
  bool _showConfirmPw = false;

  bool _uploadingAvatar = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.staff.fullName);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _currentPwCtrl.dispose();
    _newPwCtrl.dispose();
    _confirmPwCtrl.dispose();
    super.dispose();
  }

  // ── Avatar ─────────────────────────────────────────────────────────────────

  Future<void> _pickAndUploadAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 600,
      maxHeight: 600,
      imageQuality: 85,
    );
    if (picked == null) return;

    setState(() => _uploadingAvatar = true);
    try {
      final bytes = await picked.readAsBytes();
      final staffId = widget.staff.id;
      final path = '$staffId.jpg';
      final client = Supabase.instance.client;

      await client.storage.from('staff-avatars').uploadBinary(
        path,
        bytes,
        fileOptions: const FileOptions(
          contentType: 'image/jpeg',
          upsert: true,
        ),
      );

      final url = client.storage.from('staff-avatars').getPublicUrl(path);
      // Bust cache by appending a timestamp query param
      final bustedUrl = '$url?t=${DateTime.now().millisecondsSinceEpoch}';

      await ref
          .read(authServiceProvider)
          .updateStaffUser(staffId, avatarUrl: bustedUrl);

      await ref.read(currentStaffProvider.notifier).refreshCurrentUser();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile photo updated')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  // ── Name ───────────────────────────────────────────────────────────────────

  Future<void> _saveName() async {
    if (!(_nameKey.currentState?.validate() ?? false)) return;
    setState(() => _savingName = true);
    try {
      await ref
          .read(authServiceProvider)
          .updateStaffUser(widget.staff.id, fullName: _nameCtrl.text.trim());
      await ref.read(currentStaffProvider.notifier).refreshCurrentUser();
      if (mounted) {
        setState(() => _editingName = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Name updated')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update name: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
  }

  // ── Password ───────────────────────────────────────────────────────────────

  Future<void> _savePassword() async {
    if (!(_pwKey.currentState?.validate() ?? false)) return;

    final service = ref.read(authServiceProvider);
    final staffId = widget.staff.id;

    setState(() => _savingPw = true);
    try {
      // Verify current password (skip if first login — no hash set yet)
      if (!widget.staff.isFirstLogin) {
        final ok = await service.checkPassword(staffId, _currentPwCtrl.text);
        if (!ok) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Current password is incorrect')),
            );
          }
          return;
        }
      }

      await service.setPassword(staffId, _newPwCtrl.text);
      if (mounted) {
        _currentPwCtrl.clear();
        _newPwCtrl.clear();
        _confirmPwCtrl.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password updated successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update password: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingPw = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // React to live staff state changes (avatar/name update)
    final staff = ref.watch(currentStaffProvider).valueOrNull ?? widget.staff;
    final initials = staff.fullName
        .trim()
        .split(' ')
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Avatar ─────────────────────────────────────────────────────────
          Center(
            child: Stack(
              children: [
                GestureDetector(
                  onTap: _pickAndUploadAvatar,
                  child: ClipOval(
                    child: SizedBox(
                      width: 108,
                      height: 108,
                      child: staff.avatarUrl != null
                          ? CachedNetworkImage(
                              imageUrl: staff.avatarUrl!,
                              fit: BoxFit.cover,
                              width: 108,
                              height: 108,
                              placeholder: (_, __) => ColoredBox(
                                color: HSLColor.fromAHSL(
                                  1,
                                  (initials.codeUnits.fold(0, (a, b) => a + b) % 360)
                                      .toDouble(),
                                  0.45,
                                  0.28,
                                ).toColor(),
                                child: Center(
                                  child: Text(
                                    initials,
                                    style: const TextStyle(
                                      fontSize: 32,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                              errorWidget: (_, __, ___) => ColoredBox(
                                color: AppTheme.primaryBg,
                                child: Center(
                                  child: Text(
                                    initials,
                                    style: const TextStyle(
                                      fontSize: 32,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.primary,
                                    ),
                                  ),
                                ),
                              ),
                            )
                          : ColoredBox(
                              color: AppTheme.primaryBg,
                              child: Center(
                                child: Text(
                                  initials,
                                  style: const TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.primary,
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: _uploadingAvatar
                      ? const SizedBox(
                          width: 32,
                          height: 32,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : GestureDetector(
                          onTap: _pickAndUploadAvatar,
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: const BoxDecoration(
                              color: AppTheme.primary,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.camera_alt,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              staff.fullName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Chip(staff.team.value, AppTheme.primary),
                const SizedBox(width: 8),
                _Chip(staff.role.displayName, Colors.blueGrey),
              ],
            ),
          ),

          const SizedBox(height: 28),
          const _SectionLabel('Display Name'),

          // ── Name edit ─────────────────────────────────────────────────────
          Card(
            color: const Color(0xFF1A2035),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: _editingName
                  ? Form(
                      key: _nameKey,
                      child: Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _nameCtrl,
                              autofocus: true,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                hintText: 'Full name',
                                hintStyle: TextStyle(color: Colors.white38),
                                border: InputBorder.none,
                              ),
                              validator: (v) =>
                                  v == null || v.trim().isEmpty ? 'Name required' : null,
                            ),
                          ),
                          if (_savingName)
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else ...[
                            IconButton(
                              icon: const Icon(Icons.check, color: Colors.greenAccent),
                              onPressed: _saveName,
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.white54),
                              onPressed: () => setState(() {
                                _editingName = false;
                                _nameCtrl.text = staff.fullName;
                              }),
                            ),
                          ],
                        ],
                      ),
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: Text(
                            staff.fullName,
                            style: const TextStyle(color: Colors.white, fontSize: 15),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.white54, size: 20),
                          onPressed: () => setState(() => _editingName = true),
                        ),
                      ],
                    ),
            ),
          ),

          const SizedBox(height: 20),
          const _SectionLabel('Change Password'),

          // ── Password change ────────────────────────────────────────────────
          Card(
            color: const Color(0xFF1A2035),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                title: const Text(
                  'Update Password',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                iconColor: Colors.white54,
                collapsedIconColor: Colors.white38,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Form(
                      key: _pwKey,
                      child: Column(
                        children: [
                          if (!widget.staff.isFirstLogin)
                            _PwField(
                              controller: _currentPwCtrl,
                              label: 'Current Password',
                              show: _showCurrentPw,
                              onToggle: () =>
                                  setState(() => _showCurrentPw = !_showCurrentPw),
                              validator: (v) =>
                                  v == null || v.isEmpty ? 'Required' : null,
                            ),
                          const SizedBox(height: 12),
                          _PwField(
                            controller: _newPwCtrl,
                            label: 'New Password',
                            show: _showNewPw,
                            onToggle: () => setState(() => _showNewPw = !_showNewPw),
                            validator: (v) {
                              if (v == null || v.isEmpty) return 'Required';
                              if (v.length < 6) return 'Min 6 characters';
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          _PwField(
                            controller: _confirmPwCtrl,
                            label: 'Confirm New Password',
                            show: _showConfirmPw,
                            onToggle: () =>
                                setState(() => _showConfirmPw = !_showConfirmPw),
                            validator: (v) => v != _newPwCtrl.text
                                ? 'Passwords do not match'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _savingPw ? null : _savePassword,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: _savingPw
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Text('Save Password'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 32),

          // ── Log out ───────────────────────────────────────────────────────
          OutlinedButton.icon(
            onPressed: () async {
              await ref.read(currentStaffProvider.notifier).logout();
              if (context.mounted) context.go('/');
            },
            icon: const Icon(Icons.logout, size: 18),
            label: const Text('Sign Out'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.redAccent,
              side: const BorderSide(color: Colors.redAccent),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 11,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(
          label,
          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      );
}

class _PwField extends StatelessWidget {
  const _PwField({
    required this.controller,
    required this.label,
    required this.show,
    required this.onToggle,
    required this.validator,
  });

  final TextEditingController controller;
  final String label;
  final bool show;
  final VoidCallback onToggle;
  final FormFieldValidator<String> validator;

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        obscureText: !show,
        style: const TextStyle(color: Colors.white),
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white54),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.06),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          suffixIcon: IconButton(
            icon: Icon(
              show ? Icons.visibility_off : Icons.visibility,
              color: Colors.white38,
              size: 20,
            ),
            onPressed: onToggle,
          ),
        ),
      );
}
