// lib/features/members/member_detail_screen.dart
//
// Shows a single member's full profile:
//   Avatar, name, team, phone
//   Attendance code + copy button + QR code
//   Points / present count + recent attendance history
//   Edit button opens _EditMemberSheet

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

import '../../models/member.dart';
import '../../models/clock_in.dart';
import '../../models/enums.dart';
import '../../services/member_service.dart';
import '../../services/attendance_service.dart';
import '../../services/image_storage_service.dart';
import '../../app_theme/app_theme.dart';
import '../../widgets/avatar_widget.dart';
import '../../widgets/team_badge.dart';
import './members_screen.dart'; // For membersListProvider
import '../../core/app_logger.dart';

// ---------------------------------------------------------------------------
// Providers — family, keyed by memberId
// ---------------------------------------------------------------------------

final _memberDetailProvider =
    FutureProvider.family<Member?, String>((ref, id) {
  return ref.read(memberServiceProvider).getMemberById(id);
});

final _memberClockInsProvider =
    FutureProvider.family<List<ClockIn>, String>((ref, id) {
  return ref.read(attendanceServiceProvider).getClockInsByMember(id);
});

// ---------------------------------------------------------------------------
// MemberDetailScreen
// ---------------------------------------------------------------------------

class MemberDetailScreen extends ConsumerWidget {
  const MemberDetailScreen({super.key, required this.memberId});

  final String memberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memberAsync = ref.watch(_memberDetailProvider(memberId));
    final clockInsAsync = ref.watch(_memberClockInsProvider(memberId));

    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.dark ? AppTheme.darkSurface : AppTheme.background,
      appBar: AppBar(
        backgroundColor: Theme.of(context).brightness == Brightness.dark ? AppTheme.darkSurfaceContainer : AppTheme.surface,
        leading: BackButton(onPressed: () => context.pop()),
        title: memberAsync.when(
          data: (m) => Text(m?.fullName ?? 'Member'),
          loading: () => const Text('Loading…'),
          error: (_, __) => const Text('Member'),
        ),
        actions: [
          memberAsync.when(
            data: (m) => m == null
                ? const SizedBox.shrink()
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.send_outlined),
                        tooltip: 'Share on WhatsApp',
                        onPressed: () => _shareMemberOnWhatsApp(context, m),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: 'Edit member',
                        onPressed: () => _openEditSheet(context, ref, m),
                      ),
                    ],
                  ),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
      body: memberAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (member) {
          if (member == null) {
            return const Center(child: Text('Member not found.'));
          }
          final presentCount = clockInsAsync.maybeWhen(
            data: (list) =>
                list.where((c) => c.status == AttendanceStatus.present).length,
            orElse: () => 0,
          );
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(_memberDetailProvider(memberId));
              ref.invalidate(_memberClockInsProvider(memberId));
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
              children: [
                // ── Profile card ───────────────────────────────────────────
                _ProfileCard(member: member, presentCount: presentCount),
                const SizedBox(height: 16),

                // ── Code + QR card ─────────────────────────────────────────
                _CodeQrCard(member: member),
                const SizedBox(height: 16),

                // ── Attendance History ─────────────────────────────────────
                const Text(
                  'Attendance History',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                clockInsAsync.when(
                  loading: () => const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ),
                  ),
                  error: (e, _) =>
                      Center(child: Text('Error loading history: $e')),
                  data: (clockIns) {
                    if (clockIns.isEmpty) {
                      return Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.slate200),
                        ),
                        child: const Center(
                          child: Text(
                            'No attendance records yet.',
                            style: TextStyle(color: AppTheme.slate500),
                          ),
                        ),
                      );
                    }
                    return Column(
                      children: clockIns
                          .map((c) => Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: _ClockInRow(clockIn: c),
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

  Future<void> _shareMemberOnWhatsApp(BuildContext context, Member member) async {
    final firstName = member.fullName.split(' ').first;
    final code = member.offlineCode;
    final msg =
        'Hi $firstName!\n\n'
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
      // Render QR with white background
      const size = 300.0;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
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

      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/qr_$code.png');
      await file.writeAsBytes(bytes);

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png', name: 'qr_$code.png')],
        text: msg,
      );
    } catch (_) {
      // Fallback: WhatsApp text only
      final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(msg)}');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await Clipboard.setData(ClipboardData(text: msg));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Message copied to clipboard'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    }
  }

  void _openEditSheet(BuildContext context, WidgetRef ref, Member member) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: _EditMemberSheet(
          member: member,
          onSaved: () {
            ref.invalidate(_memberDetailProvider(memberId));
            // Also refresh the members list so photos show up immediately
            ref.invalidate(membersListProvider);
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _ProfileCard
// ---------------------------------------------------------------------------

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.member, required this.presentCount});
  final Member member;
  final int presentCount;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurfaceContainer : AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppTheme.darkOutlineVariant : AppTheme.slate200),
      ),
      child: Column(
        children: [
          MemberAvatar(
            fullName: member.fullName,
            imageUrl: member.photoUrl,
            radius: 36,
          ),
          const SizedBox(height: 12),
          Text(
            member.fullName,
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w800,
                color: isDark ? AppTheme.darkOnSurface : Colors.black),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TeamBadge(team: member.team),
              if (member.isMarried) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF3D0D1F) : const Color(0xFFFFF1F2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Married',
                    style: TextStyle(
                        fontSize: 11,
                        color: isDark ? const Color(0xFFFF69B4) : const Color(0xFFE11D48),
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          if (member.phone.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.phone_outlined,
                    size: 14, color: AppTheme.slate500),
                const SizedBox(width: 6),
                Text(
                  member.phone,
                  style: const TextStyle(
                      fontSize: 13, color: AppTheme.slate500),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () async {
                    final uri = Uri.parse('tel:${member.phone}');
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Call',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          // Stats row
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _StatPill(label: 'Present', value: '$presentCount'),
              const SizedBox(width: 12),
              _StatPill(label: 'Points', value: '$presentCount pts'),
            ],
          ),
          // Birthday / anniversary
          if (member.birthdayMD.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.cake_outlined,
                    size: 14, color: AppTheme.slate500),
                const SizedBox(width: 6),
                Text(
                  'Birthday: ${member.birthdayMD}',
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.slate500),
                ),
                if (member.anniversaryMD != null) ...[
                  const SizedBox(width: 16),
                  const Icon(Icons.favorite_outline,
                      size: 14, color: AppTheme.amber),
                  const SizedBox(width: 6),
                  Text(
                    'Anniversary: ${member.anniversaryMD}',
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.slate500),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.primaryBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontFamily: 'Poppins'),
          children: [
            TextSpan(
              text: '$value ',
              style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: AppTheme.primary),
            ),
            TextSpan(
              text: label,
              style: const TextStyle(
                  fontSize: 11, color: AppTheme.slate500),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _CodeQrCard
// ---------------------------------------------------------------------------

class _CodeQrCard extends StatelessWidget {
  const _CodeQrCard({required this.member});
  final Member member;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurfaceContainer : AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppTheme.darkOutlineVariant : AppTheme.slate200),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                'Attendance Code',
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700,
                    color: isDark ? AppTheme.darkOnSurface : Colors.black),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(
                      ClipboardData(text: member.offlineCode));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Code copied to clipboard!'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.copy, size: 14, color: AppTheme.primary),
                      SizedBox(width: 4),
                      Text(
                        'Copy',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primary),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkSurfaceContainerHigh : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: isDark ? AppTheme.darkOutlineVariant : AppTheme.slate200),
            ),
            child: Center(
              child: Text(
                member.offlineCode,
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 6,
                  color: isDark ? AppTheme.darkOnSurface : const Color(0xFF0F172A),
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          QrImageView(
            data: member.offlineCode,
            version: QrVersions.auto,
            size: 180,
            backgroundColor: Colors.white,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _ClockInRow — one row in the attendance history list
// ---------------------------------------------------------------------------

class _ClockInRow extends StatelessWidget {
  const _ClockInRow({required this.clockIn});
  final ClockIn clockIn;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = switch (clockIn.status) {
      AttendanceStatus.present => AppTheme.success,
      AttendanceStatus.excused => AppTheme.primary,
      AttendanceStatus.absent  => AppTheme.error,
    };

    final label = switch (clockIn.status) {
      AttendanceStatus.present => 'Present',
      AttendanceStatus.excused => 'Excused',
      AttendanceStatus.absent  => 'Absent',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurfaceContainer : AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? AppTheme.darkOutlineVariant : AppTheme.slate200),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _formatDate(clockIn.clockedAt),
              style: TextStyle(
                  fontSize: 13,
                  color: isDark ? AppTheme.darkOnSurface : Colors.black),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isDark ? color.withValues(alpha: 0.15) : color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[dt.month]} ${dt.day}, ${dt.year}';
  }
}

// ---------------------------------------------------------------------------
// _EditMemberSheet
// ---------------------------------------------------------------------------

class _EditMemberSheet extends ConsumerStatefulWidget {
  const _EditMemberSheet(
      {required this.member, required this.onSaved});
  final Member member;
  final VoidCallback onSaved;

  @override
  ConsumerState<_EditMemberSheet> createState() =>
      _EditMemberSheetState();
}

class _EditMemberSheetState
    extends ConsumerState<_EditMemberSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _bdCtrl;
  late final TextEditingController _annCtrl;
  late Team _team;
  late bool _isMarried;
  bool _saving = false;
  File? _photoFile;
  Uint8List? _photoBytes;
  bool _uploadingPhoto = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.member.fullName);
    _phoneCtrl = TextEditingController(text: widget.member.phone);
    _bdCtrl = TextEditingController(text: widget.member.birthdayMD);
    _annCtrl = TextEditingController(
        text: widget.member.anniversaryMD ?? '');
    _team = widget.member.team;
    _isMarried = widget.member.isMarried;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _bdCtrl.dispose();
    _annCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Select Photo Source',
                style: TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take Photo'),
              onTap: () async {
                Navigator.pop(ctx);
                await _pickPhotoFrom(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () async {
                Navigator.pop(ctx);
                await _pickPhotoFrom(ImageSource.gallery);
              },
            ),
            if (_photoFile != null)
              ListTile(
                leading: const Icon(Icons.delete, color: AppTheme.error),
                title: const Text('Remove Photo',
                    style: TextStyle(color: AppTheme.error)),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _photoFile = null;
                    _photoBytes = null;
                  });
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickPhotoFrom(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      maxWidth: 600,
      maxHeight: 600,
      imageQuality: 85,
    );
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    setState(() {
      _photoFile = File(picked.path);
      _photoBytes = bytes;
    });
  }

  Future<void> _pickMonthDay(TextEditingController ctrl) async {
    final parts = ctrl.text.split('-');
    DateTime initial = DateTime(2000);
    if (parts.length == 2) {
      try {
        initial = DateTime(
            2000, int.parse(parts[0]), int.parse(parts[1]));
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
      ctrl.text =
          '${picked.month.toString().padLeft(2, '0')}-'
          '${picked.day.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      AppLogger.info(
        '💾 SAVING MEMBER: ${widget.member.id}',
        tag: 'EditMemberSheet',
      );

      // Upload photo if selected
      String? photoUrl;
      if (_photoFile != null) {
        setState(() => _uploadingPhoto = true);
        AppLogger.info(
          '📸 Photo selected, uploading...',
          tag: 'EditMemberSheet',
        );
        try {
          photoUrl = await ref
              .read(imageStorageServiceProvider)
              .uploadMemberPhoto(
                memberId: widget.member.id,
                imageFile: _photoFile!,
              );
          AppLogger.info(
            '✓ Photo uploaded, URL: $photoUrl',
            tag: 'EditMemberSheet',
          );
        } catch (e) {
          AppLogger.error(
            '❌ Photo upload failed: $e',
            tag: 'EditMemberSheet',
            error: e,
          );
          // Continue — photo upload failure shouldn't block member update
        } finally {
          setState(() => _uploadingPhoto = false);
        }
      }

      // Update member info
      AppLogger.info(
        '📝 Updating member fields: name, phone, team, birthday, photoUrl=$photoUrl',
        tag: 'EditMemberSheet',
      );

      await ref.read(memberServiceProvider).updateMember(
            widget.member.id,
            fullName: _nameCtrl.text.trim(),
            phone: _phoneCtrl.text.trim(),
            team: _team,
            isMarried: _isMarried,
            birthdayMD: _bdCtrl.text.trim(),
            anniversaryMD: _isMarried && _annCtrl.text.trim().isNotEmpty
                ? _annCtrl.text.trim()
                : null,
            photoUrl: photoUrl,
          );

      AppLogger.info(
        '✓ Member updated successfully!',
        tag: 'EditMemberSheet',
      );

      if (mounted) {
        Navigator.pop(context);
        widget.onSaved();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Member updated'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      AppLogger.error(
        '❌ Save failed: $e',
        tag: 'EditMemberSheet',
        error: e,
      );
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
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Edit Member',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            // ── Photo section ──────────────────────────────────────────────
            Center(
              child: Stack(
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.slate200),
                    ),
                    child: _uploadingPhoto
                        ? const Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : GestureDetector(
                            onTap: _pickPhoto,
                            child: _photoBytes != null
                                ? ClipRRect(
                                    borderRadius:
                                        BorderRadius.circular(12),
                                    child: Image.memory(
                                      _photoBytes!,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                : (widget.member.photoUrl != null &&
                                        widget
                                            .member.photoUrl!.isNotEmpty)
                                    ? Image.network(
                                        widget.member.photoUrl!,
                                        fit: BoxFit.cover,
                                      )
                                    : const Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.add_a_photo_outlined,
                                            size: 32,
                                            color: AppTheme.slate500,
                                          ),
                                          SizedBox(height: 4),
                                          Text(
                                            'Add Photo',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: AppTheme.slate500,
                                            ),
                                          ),
                                        ],
                                      ),
                          ),
                  ),
                  if (_photoFile != null && !_uploadingPhoto)
                    Positioned(
                      right: -8,
                      bottom: -8,
                      child: GestureDetector(
                        onTap: () => setState(() {
                          _photoFile = null;
                          _photoBytes = null;
                        }),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: const BoxDecoration(
                            color: AppTheme.error,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameCtrl,
              decoration:
                  const InputDecoration(labelText: 'Full name*'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration:
                  const InputDecoration(labelText: 'Phone'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _bdCtrl,
              readOnly: true,
              onTap: () => _pickMonthDay(_bdCtrl),
              decoration: const InputDecoration(
                labelText: 'Birthday (MM-DD)*',
                suffixIcon: Icon(Icons.calendar_today, size: 18),
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            const Text('Team',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.slate500)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: Team.values
                  .where((t) => t != Team.none)
                  .map((t) => GestureDetector(
                        onTap: () => setState(() => _team = t),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: _team == t
                                ? AppTheme.primary
                                : AppTheme.surface,
                            borderRadius:
                                BorderRadius.circular(20),
                            border: Border.all(
                                color: _team == t
                                    ? AppTheme.primary
                                    : AppTheme.slate200),
                          ),
                          child: Text(
                            t.value,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _team == t
                                  ? Colors.white
                                  : AppTheme.slate500,
                            ),
                          ),
                        ),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Switch(
                  value: _isMarried,
                  onChanged: (v) =>
                      setState(() => _isMarried = v),
                  activeThumbColor: AppTheme.primary,
                ),
                const SizedBox(width: 8),
                const Text('Married',
                    style: TextStyle(fontWeight: FontWeight.w500)),
              ],
            ),
            if (_isMarried) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _annCtrl,
                readOnly: true,
                onTap: () => _pickMonthDay(_annCtrl),
                decoration: const InputDecoration(
                  labelText: 'Anniversary (MM-DD)',
                  suffixIcon: Icon(Icons.calendar_today, size: 18),
                ),
              ),
            ],
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
                    : const Text('Save Changes',
                        style: TextStyle(
                            fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
