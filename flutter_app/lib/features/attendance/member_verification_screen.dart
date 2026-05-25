// lib/features/attendance/member_verification_screen.dart
//
// Member Verification/Check-in Success Screen
// ─────────────────────────────────────────────────────────────────────────
// Displays a beautiful success state after a member checks in.
// Features:
//   • Profile photo with warm gold circular border & checkmark badge
//   • "Check-in Successful!" headline in warm gold
//   • "VERIFICATION CONFIRMED" subheading
//   • Member details card (name, team, status, entry time)
//   • Supports both light and dark modes
//   • Custom app bar with back navigation
//
// Design System: The Welcoming Hearth (dark mode) + light mode fallback
// ─────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/member.dart';
import '../../models/enums.dart';
import '../../app_theme/app_theme.dart';

// ───────────────────────────────────────────────────────────────────────────
// MemberVerificationScreen
// ───────────────────────────────────────────────────────────────────────────

class MemberVerificationScreen extends StatefulWidget {
  const MemberVerificationScreen({
    super.key,
    required this.member,
    required this.entryTime,
    this.status = AttendanceStatus.present,
    this.positionLabel,
  });

  final Member member;
  final DateTime entryTime;
  final AttendanceStatus status;
  final String? positionLabel;

  @override
  State<MemberVerificationScreen> createState() =>
      _MemberVerificationScreenState();
}

class _MemberVerificationScreenState extends State<MemberVerificationScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _checkmarkController;

  @override
  void initState() {
    super.initState();
    // Animate checkmark on load
    _checkmarkController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _checkmarkController.forward();
    });
  }

  @override
  void dispose() {
    _checkmarkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      backgroundColor: isDarkMode ? AppTheme.darkSurface : AppTheme.background,
      appBar: AppBar(
        backgroundColor:
            isDarkMode ? AppTheme.darkSurface : AppTheme.background,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color:
                isDarkMode ? AppTheme.darkOnSurface : const Color(0xFF0F172A),
          ),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Member Check-in',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: Color(0xFF0F172A),
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(
              Icons.more_vert,
              color:
                  isDarkMode ? AppTheme.darkOnSurface : const Color(0xFF0F172A),
            ),
            onPressed: () {
              // Menu options for settings, etc.
            },
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Center(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 16 : 32,
                vertical: 24,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 20),

                  // ── Profile Photo with Gold Border & Checkmark ────────────
                  _buildProfilePhotoSection(isDarkMode),

                  const SizedBox(height: 40),

                  // ── Success Headline ────────────────────────────────────
                  Text(
                    'Check-in Successful!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: isMobile ? 32 : 40,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.darkTertiary, // Warm gold
                      letterSpacing: -0.02,
                    ),
                  ),

                  const SizedBox(height: 12),

                  // ── Verification Confirmed Badge ────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.verified_outlined,
                        size: 18,
                        color: isDarkMode
                            ? AppTheme.darkOnSurfaceVariant
                            : AppTheme.slate500,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'VERIFICATION CONFIRMED',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDarkMode
                              ? AppTheme.darkOnSurfaceVariant
                              : AppTheme.slate500,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),

                  // ── Member Details Card ─────────────────────────────────
                  _buildMemberDetailsCard(isDarkMode, context),

                  const SizedBox(height: 40),

                  // ── Action Buttons ──────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => context.pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Complete Check-in',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () {
                        context.go('/home');
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primary,
                        side: const BorderSide(
                          color: AppTheme.slate200,
                        ),
                        minimumSize: const Size(double.infinity, 52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Go to Home',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Profile Photo Section with Gold Border & Checkmark Badge
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildProfilePhotoSection(bool isDarkMode) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Large gold circle border
        Container(
          width: 240,
          height: 240,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            border: Border(
              top: BorderSide(color: AppTheme.darkTertiary, width: 8),
              bottom: BorderSide(color: AppTheme.darkTertiary, width: 8),
              left: BorderSide(color: AppTheme.darkTertiary, width: 8),
              right: BorderSide(color: AppTheme.darkTertiary, width: 8),
            ),
          ),
        ),

        // Profile photo
        Container(
          width: 220,
          height: 220,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color:
                isDarkMode ? AppTheme.darkSurfaceContainer : AppTheme.primaryBg,
            border: Border.all(
              color: isDarkMode
                  ? AppTheme.darkSurfaceContainerHigh
                  : AppTheme.slate200,
              width: 2,
            ),
          ),
          child: widget.member.photoUrl != null
              ? SizedBox.expand(
                  child: Image.network(
                    widget.member.photoUrl!,
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (context, error, stackTrace) =>
                        _buildPlaceholderAvatar(isDarkMode),
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Center(
                        child: CircularProgressIndicator(
                          color: isDarkMode
                              ? AppTheme.darkTertiary
                              : AppTheme.primary,
                        ),
                      );
                    },
                  ),
                )
              : _buildPlaceholderAvatar(isDarkMode),
        ),

        // Checkmark badge
        Positioned(
          bottom: 0,
          right: 0,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0, end: 1).animate(
              CurvedAnimation(
                parent: _checkmarkController,
                curve: Curves.elasticOut,
              ),
            ),
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.darkTertiary, // Warm gold
                border: Border.all(
                  color: isDarkMode
                      ? AppTheme.darkSurfaceContainerHigh
                      : AppTheme.background,
                  width: 3,
                ),
              ),
              child: const Center(
                child: Icon(
                  Icons.check,
                  size: 32,
                  color: Color(0xFF0A1128),
                  weight: 700,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Placeholder Avatar
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildPlaceholderAvatar(bool isDarkMode) {
    final initials = widget.member.fullName
        .split(' ')
        .map((word) => word.isNotEmpty ? word[0].toUpperCase() : '')
        .take(2)
        .join();

    return Container(
      color: AppTheme.primary,
      child: Center(
        child: Text(
          initials,
          style: const TextStyle(
            fontSize: 48,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Member Details Card
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildMemberDetailsCard(bool isDarkMode, BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final teamColor = _getTeamColor(widget.member.team);
    final entryTimeFormatted = _formatEntryTime(widget.entryTime);
    final statusLabel = _getStatusLabel(widget.status);

    return Container(
      decoration: BoxDecoration(
        color: isDarkMode ? AppTheme.darkSurfaceContainer : AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDarkMode ? AppTheme.darkOutlineVariant : AppTheme.slate200,
        ),
      ),
      padding: EdgeInsets.all(isMobile ? 20 : 28),
      child: Column(
        children: [
          // ── Member Name ──────────────────────────────────────────────────
          Text(
            widget.member.fullName,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: isMobile ? 24 : 28,
              fontWeight: FontWeight.w800,
              color:
                  isDarkMode ? AppTheme.darkOnSurface : const Color(0xFF0F172A),
              letterSpacing: -0.01,
            ),
          ),

          const SizedBox(height: 16),

          // ── Team Badge ───────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: teamColor['bg'] as Color,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: (teamColor['bg'] as Color).withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              'TEAM ${_getTeamDisplayLetter(widget.member.team)}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: teamColor['text'] as Color,
                letterSpacing: 0.5,
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ── Status and Entry Time (2-column layout) ──────────────────────
          Row(
            children: [
              // Status
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'STATUS',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDarkMode
                            ? AppTheme.darkOnSurfaceVariant
                            : AppTheme.slate500,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const SizedBox(
                          width: 8,
                          height: 8,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppTheme.success,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          statusLabel,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: isDarkMode
                                ? AppTheme.darkOnSurface
                                : const Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Entry Time
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ENTRY TIME',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDarkMode
                            ? AppTheme.darkOnSurfaceVariant
                            : AppTheme.slate500,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      entryTimeFormatted,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: isDarkMode
                            ? AppTheme.darkOnSurface
                            : const Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          if (widget.positionLabel != null &&
              widget.positionLabel!.trim().isNotEmpty) ...[
            const SizedBox(height: 24),
            _DetailValue(
              label: 'POSITION',
              value: widget.positionLabel!,
              icon: Icons.place_outlined,
              isDarkMode: isDarkMode,
            ),
          ],
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  Map<String, dynamic> _getTeamColor(Team team) {
    switch (team) {
      case Team.teamA:
        return {
          'bg': AppTheme.teamABg,
          'text': AppTheme.teamAText,
        };
      case Team.teamB:
        return {
          'bg': AppTheme.teamBBg,
          'text': AppTheme.teamBText,
        };
      case Team.teamC:
        return {
          'bg': AppTheme.teamCBg,
          'text': AppTheme.teamCText,
        };
      case Team.none:
        return {
          'bg': AppTheme.teamNoneBg,
          'text': AppTheme.teamNoneText,
        };
    }
  }

  String _getTeamDisplayLetter(Team team) {
    switch (team) {
      case Team.teamA:
        return 'A';
      case Team.teamB:
        return 'B';
      case Team.teamC:
        return 'C';
      case Team.none:
        return 'NONE';
    }
  }

  String _formatEntryTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')} ${dateTime.hour >= 12 ? "PM" : "AM"}';
  }

  String _getStatusLabel(AttendanceStatus status) {
    switch (status) {
      case AttendanceStatus.present:
        return 'Present';
      case AttendanceStatus.absent:
        return 'Absent';
      case AttendanceStatus.excused:
        return 'Excused';
    }
  }
}

class _DetailValue extends StatelessWidget {
  const _DetailValue({
    required this.label,
    required this.value,
    required this.icon,
    required this.isDarkMode,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool isDarkMode;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          size: 18,
          color: isDarkMode ? AppTheme.darkOnSurfaceVariant : AppTheme.slate500,
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color:
                isDarkMode ? AppTheme.darkOnSurfaceVariant : AppTheme.slate500,
            letterSpacing: 0.5,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color:
                isDarkMode ? AppTheme.darkOnSurface : const Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }
}
