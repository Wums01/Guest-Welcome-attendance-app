// lib/features/members/register_member_screen.dart

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/enums.dart';
import '../../services/member_service.dart';
import '../../services/image_storage_service.dart';
import '../../app_theme/app_theme.dart';
import '../../core/app_logger.dart';
import 'members_screen.dart';

class RegisterMemberScreen extends ConsumerStatefulWidget {
  const RegisterMemberScreen({super.key});

  @override
  ConsumerState<RegisterMemberScreen> createState() =>
      _RegisterMemberScreenState();
}

class _RegisterMemberScreenState
    extends ConsumerState<RegisterMemberScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl        = TextEditingController();
  final _phoneCtrl       = TextEditingController();
  final _birthdayCtrl    = TextEditingController();
  final _anniversaryCtrl = TextEditingController();

  Team _team = Team.none;
  bool _isMarried  = false;
  bool _loading    = false;
  File? _photoFile;
  Uint8List? _photoBytes;
  String? _generatedCode;
  String? _registeredName;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _birthdayCtrl.dispose();
    _anniversaryCtrl.dispose();
    super.dispose();
  }

  String? _validateMMDD(String? value) {
    if (value == null || value.isEmpty) return null;
    final re = RegExp(r'^\d{2}-\d{2}$');
    if (!re.hasMatch(value)) return 'Format must be MM-DD (e.g. 03-15)';
    final parts = value.split('-');
    final month = int.parse(parts[0]);
    final day   = int.parse(parts[1]);
    if (month < 1 || month > 12) return 'Month must be 01–12';
    if (day   < 1 || day   > 31) return 'Day must be 01–31';
    return null;
  }

  // Calendar picker locked to year 2000 — only month+day matter
  Future<void> _pickMonthDay(TextEditingController ctrl) async {
    final now = DateTime.now();
    DateTime initial = DateTime(2000, now.month, now.day);
    if (ctrl.text.length == 5) {
      try {
        final parts = ctrl.text.split('-');
        initial = DateTime(2000, int.parse(parts[0]), int.parse(parts[1]));
      } catch (_) {}
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2000, 12, 31),
      helpText: 'Pick month & day',
    );
    if (picked != null && mounted) {
      ctrl.text = '${picked.month.toString().padLeft(2, '0')}-'
          '${picked.day.toString().padLeft(2, '0')}';
    }
  }

  /// Pick a photo from camera or gallery
  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    try {
      final source = await showDialog<ImageSource>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Select Photo Source'),
          content: const Text('Choose camera or gallery'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, ImageSource.camera),
              child: const Text('Camera'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, ImageSource.gallery),
              child: const Text('Gallery'),
            ),
          ],
        ),
      );

      if (source == null) return;

      final pickedFile = await picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1024,
        maxHeight: 1024,
      );

      if (pickedFile != null && mounted) {
        final bytes = await pickedFile.readAsBytes();
        setState(() {
          _photoFile = File(pickedFile.path);
          _photoBytes = bytes;
        });
        AppLogger.debug(
          'Photo selected: ${pickedFile.path}',
          tag: 'RegisterMemberScreen',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking photo: $e')),
        );
      }
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _loading = true);
    try {
      final member = await ref.read(memberServiceProvider).createMember(
            fullName:     _nameCtrl.text.trim(),
            phone:        _phoneCtrl.text.trim(),
            team:         _team,
            isMarried:    _isMarried,
            birthdayMD:   _birthdayCtrl.text.trim(),
            anniversaryMD: _isMarried && _anniversaryCtrl.text.isNotEmpty
                ? _anniversaryCtrl.text.trim()
                : null,
          );

      // Upload photo if selected
      if (_photoFile != null) {
        try {
          final photoUrl = await ref
              .read(imageStorageServiceProvider)
              .uploadMemberPhoto(
                memberId: member.id,
                imageFile: _photoFile!,
              );
          
          // Update member with photo URL
          await ref.read(memberServiceProvider).updateMember(
            member.id,
            photoUrl: photoUrl,
          );
          AppLogger.debug(
            'Photo uploaded for member ${member.id}',
            tag: 'RegisterMemberScreen',
          );
        } catch (e) {
          AppLogger.error(
            'Failed to upload photo: $e',
            tag: 'RegisterMemberScreen',
          );
          // Continue — photo upload failure shouldn't block member creation
        }
      }

      ref.invalidate(membersListProvider);
      setState(() {
        _generatedCode  = member.offlineCode;
        _registeredName = member.fullName;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.error),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_generatedCode != null) {
      return _SuccessView(
        code: _generatedCode!,
        name: _registeredName!,
        onRegisterAnother: () => setState(() {
          _generatedCode  = null;
          _registeredName = null;
          _photoFile = null;
          _nameCtrl.clear();
          _phoneCtrl.clear();
          _birthdayCtrl.clear();
          _anniversaryCtrl.clear();
          _team      = Team.none;
          _isMarried = false;
        }),
        onDone: () => context.go('/members'),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.dark ? AppTheme.darkSurface : AppTheme.background,
      appBar: AppBar(
        backgroundColor: Theme.of(context).brightness == Brightness.dark ? AppTheme.darkSurfaceContainer : AppTheme.surface,
        title: const Text('Register Member'),
        leading: BackButton(onPressed: () => context.pop()),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Center(
                        child: Column(
                          children: [
                            Container(
                              width: 64, height: 64,
                              decoration: BoxDecoration(
                                color: AppTheme.primary,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(Icons.person_add, color: Colors.white, size: 28),
                            ),
                            const SizedBox(height: 12),
                            Text('New Member Details',
                                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Theme.of(context).brightness == Brightness.dark ? AppTheme.darkOnSurface : const Color(0xFF0F172A))),
                            const SizedBox(height: 6),
                            Text(
                              'Join our ministry family. Please enter the\ninformation below to add a new member.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 13, color: Theme.of(context).brightness == Brightness.dark ? AppTheme.darkOnSurfaceVariant : AppTheme.slate500),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Card 1: Personal details
                      _FormCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _FieldLabel(label: 'Full Name', required: true),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _nameCtrl,
                              textCapitalization: TextCapitalization.words,
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'Full name is required' : null,
                              decoration: const InputDecoration(hintText: 'e.g. Ada Obi'),
                            ),
                            const SizedBox(height: 14),

                            const _FieldLabel(label: 'Phone Number'),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _phoneCtrl,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(hintText: 'e.g. 08012345678'),
                            ),
                            const SizedBox(height: 14),

                            // Birthday — calendar picker (year locked to 2000)
                            const _FieldLabel(label: 'Birthday', required: true),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _birthdayCtrl,
                              readOnly: true,
                              onTap: () => _pickMonthDay(_birthdayCtrl),
                              validator: (v) {
                                if (v == null || v.isEmpty) return 'Birthday is required';
                                return _validateMMDD(v);
                              },
                              decoration: const InputDecoration(
                                hintText: 'Tap to select birthday',
                                suffixIcon: Icon(Icons.calendar_today, size: 18),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Card 1.5: Photo
                      _FormCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.photo_camera_outlined, size: 18, color: AppTheme.primary),
                                SizedBox(width: 8),
                                Text('Member Photo (Optional)',
                                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                              ],
                            ),
                            const SizedBox(height: 14),
                            if (_photoFile == null)
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: _pickPhoto,
                                  icon: const Icon(Icons.add_a_photo_outlined),
                                  label: const Text('Add Photo'),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(double.infinity, 44),
                                  ),
                                ),
                              )
                            else
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: _photoBytes != null
                                        ? Image.memory(
                                            _photoBytes!,
                                            height: 140,
                                            width: double.infinity,
                                            fit: BoxFit.cover,
                                          )
                                        : const SizedBox(
                                            height: 140,
                                            width: double.infinity,
                                            child: Center(
                                              child: CircularProgressIndicator(),
                                            ),
                                          ),
                                  ),
                                  const SizedBox(height: 12),
                                  OutlinedButton.icon(
                                    onPressed: () => setState(() {
                                      _photoFile = null;
                                      _photoBytes = null;
                                    }),
                                    icon: const Icon(Icons.delete_outline),
                                    label: const Text('Remove Photo'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppTheme.error,
                                      side: BorderSide(
                                          color: AppTheme.error.withValues(alpha: 0.4)),
                                      minimumSize: const Size(double.infinity, 42),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Card 2: Team
                      _FormCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.people_outlined, size: 18, color: AppTheme.primary),
                                SizedBox(width: 8),
                                Text('Team Selection',
                                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(child: _TeamButton(label: 'None',   team: Team.none,  selected: _team == Team.none,  onTap: () => setState(() => _team = Team.none))),
                                    const SizedBox(width: 8),
                                    Expanded(child: _TeamButton(label: 'Team A', team: Team.teamA, selected: _team == Team.teamA, onTap: () => setState(() => _team = Team.teamA))),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(child: _TeamButton(label: 'Team B', team: Team.teamB, selected: _team == Team.teamB, onTap: () => setState(() => _team = Team.teamB))),
                                    const SizedBox(width: 8),
                                    Expanded(child: _TeamButton(label: 'Team C', team: Team.teamC, selected: _team == Team.teamC, onTap: () => setState(() => _team = Team.teamC))),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Card 3: Married + Anniversary
                      _FormCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.favorite_outline, size: 18, color: AppTheme.error),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text('Married',
                                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                ),
                                Switch(
                                  value: _isMarried,
                                  onChanged: (v) => setState(() => _isMarried = v),
                                  activeThumbColor: AppTheme.primary,
                                ),
                              ],
                            ),
                            if (_isMarried) ...[
                              const SizedBox(height: 14),
                              const _FieldLabel(label: 'Anniversary'),
                              const SizedBox(height: 6),
                              // Anniversary — calendar picker (year locked to 2000)
                              TextFormField(
                                controller: _anniversaryCtrl,
                                readOnly: true,
                                onTap: () => _pickMonthDay(_anniversaryCtrl),
                                validator: (v) => _isMarried ? _validateMMDD(v) : null,
                                decoration: const InputDecoration(
                                  hintText: 'Tap to select anniversary',
                                  helperText: 'Optional, used for celebrating with you!',
                                  suffixIcon: Icon(Icons.calendar_today, size: 18),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),

              // Sticky bottom bar
              Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                decoration: const BoxDecoration(
                  color: AppTheme.surface,
                  border: Border(top: BorderSide(color: AppTheme.slate200)),
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: _loading
                        ? const SizedBox(height: 18, width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.how_to_reg, size: 18),
                    label: const Text('Register Member'),
                    onPressed: _loading ? null : _submit,
                  ),
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
// _FormCard
// ---------------------------------------------------------------------------

class _FormCard extends StatelessWidget {
  const _FormCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurfaceContainer : AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppTheme.darkOutlineVariant : AppTheme.slate200),
      ),
      child: child,
    );
  }
}

// ---------------------------------------------------------------------------
// _TeamButton
// ---------------------------------------------------------------------------

class _TeamButton extends StatelessWidget {
  const _TeamButton({
    required this.label, required this.team,
    required this.selected, required this.onTap,
  });
  final String       label;
  final Team         team;
  final bool         selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (selected) {
      return ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primary, foregroundColor: Colors.white,
          minimumSize: const Size(0, 48), elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      );
    }
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.slate500,
        side: const BorderSide(color: AppTheme.slate200),
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
    );
  }
}

// ---------------------------------------------------------------------------
// _FieldLabel
// ---------------------------------------------------------------------------

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label, this.required = false});
  final String label;
  final bool   required;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
        if (required)
          const Text(' *', style: TextStyle(color: AppTheme.error, fontSize: 13)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _SuccessView — QR code + copy + WhatsApp share
// ---------------------------------------------------------------------------

class _SuccessView extends StatelessWidget {
  const _SuccessView({
    required this.code,
    required this.name,
    required this.onRegisterAnother,
    required this.onDone,
  });
  final String       code;
  final String       name;
  final VoidCallback onRegisterAnother;
  final VoidCallback onDone;

  String get _firstName => name.split(' ').first;

  Future<void> _shareOnWhatsApp(BuildContext context) async {
    final msg =
        'Hi $_firstName!\n\n'
        "You've been registered as a member of the Guest Welcome Ministry!\n\n"
        'Your personal attendance code is:\n\n'
        '*$code*\n\n'
        'How to check in at service:\n'
        '📱 Scan your personal QR code (see image), OR\n'
        '🔢 Enter your 6-digit code: $code\n\n'
        "We're so blessed to have you with us! "
        'The Lord bless you and keep you!\n\n'
        'Guest Welcome Unit';

    try {
      // Generate QR as PNG with white background
      const size = 300.0;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      // White background
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, size, size),
        Paint()..color = const Color(0xFFFFFFFF),
      );
      final painter = QrPainter(
        data: code,
        version: QrVersions.auto,
        errorCorrectionLevel: QrErrorCorrectLevel.M,
      );
      painter.paint(canvas, const Size(size, size));
      final picture = recorder.endRecording();
      final img = await picture.toImage(size.toInt(), size.toInt());
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('QR render failed');
      final bytes = byteData.buffer.asUint8List();

      // Write to a temp file for sharing
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/qr_$code.png');
      await file.writeAsBytes(bytes);

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png', name: 'qr_$code.png')],
        text: msg,
      );
    } catch (_) {
      // Fallback: open WhatsApp with text only
      final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(msg)}');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await Clipboard.setData(ClipboardData(text: msg));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content:
                  Text('WhatsApp not found — message copied to clipboard!'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkSurface : AppTheme.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Icon(Icons.check_circle_outline, size: 64, color: AppTheme.success),
              const SizedBox(height: 16),
              Text('Member registered!',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700,
                      color: isDark ? AppTheme.darkOnSurface : Colors.black)),
              const SizedBox(height: 6),
              Text(
                'Welcome to the family, $_firstName! 🙏',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: isDark ? AppTheme.darkOnSurfaceVariant : AppTheme.slate500),
              ),
              const SizedBox(height: 28),

              // QR code card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkSurfaceContainer : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: isDark ? AppTheme.darkOutlineVariant : AppTheme.slate200),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
                      blurRadius: 12, offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    QrImageView(
                      data: code,
                      version: QrVersions.auto,
                      size: 200,
                      backgroundColor: Colors.white,
                    ),
                    const SizedBox(height: 8),
                    Text('Scan to check in',
                        style: TextStyle(fontSize: 11, color: isDark ? AppTheme.darkOnSurfaceVariant : Colors.grey[500])),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Code display with inline copy button
              Container(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      code,
                      style: const TextStyle(
                        fontSize: 34, fontWeight: FontWeight.w800,
                        color: Colors.white, letterSpacing: 8,
                      ),
                    ),
                    const SizedBox(width: 14),
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: code));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Code copied!'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.copy, color: Colors.white, size: 18),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text('6-digit offline code',
                  style: TextStyle(fontSize: 12, color: isDark ? AppTheme.darkOnSurfaceVariant : AppTheme.slate500)),
              const SizedBox(height: 28),

              // WhatsApp share button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.send, size: 18),
                  label: const Text('Share on WhatsApp'),
                  onPressed: () => _shareOnWhatsApp(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onRegisterAnother,
                  child: const Text('Register another'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: onDone,
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
