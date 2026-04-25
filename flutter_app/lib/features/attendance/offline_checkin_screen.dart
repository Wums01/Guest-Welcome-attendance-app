// lib/features/attendance/offline_checkin_screen.dart
//
// Stitch UI redesign — Mirrors app/(dashboard)/sessions/[id]/code/page.tsx
//
// Background: AppTheme.background.
// AppBar: "Check-in" centered title, × close icon right.
// Church icon circle → "Welcome!" h1 → subtitle.
// 6 OTP boxes (masked as dots, blue border if filled, slate200 if empty).
// "Scan QR Code instead" full-width outlined button.
// Custom numpad 3×3 + bottom row [empty / 0 / backspace].
// "Confirm Check-in →" full-width blue ElevatedButton.
// Footer: "ATTENDANCE MINISTRY" small uppercase.
// All existing service logic, feedback states, and session loading preserved.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import '../../models/enums.dart';
import '../../models/session.dart';
import '../../services/attendance_service.dart';
import '../../services/member_service.dart';
import '../../services/session_service.dart';
import '../../app_theme/app_theme.dart';
import '../../core/utils/date_utils.dart';

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final _testModeProvider = FutureProvider<bool>((ref) async {
  final data = await Supabase.instance.client
      .from('settings')
      .select('value')
      .eq('key', 'test_mode_enabled')
      .maybeSingle();
  return data?['value'] == 'true';
});

final _codeSessionProvider =
    FutureProvider.family<Session?, String>((ref, id) {
  return ref.read(sessionServiceProvider).getSessionById(id);
});

// ---------------------------------------------------------------------------
// OfflineCheckinScreen
// ---------------------------------------------------------------------------

class OfflineCheckinScreen extends ConsumerStatefulWidget {
  const OfflineCheckinScreen({super.key, required this.sessionId});
  final String sessionId;

  @override
  ConsumerState<OfflineCheckinScreen> createState() =>
      _OfflineCheckinScreenState();
}

class _OfflineCheckinScreenState
    extends ConsumerState<OfflineCheckinScreen> {
  String _code = '';
  _FeedbackState _feedback = _FeedbackState.idle;
  String _message = '';
  bool _loading = false;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    // Refresh countdown display every 30 seconds for the tooEarly gate state
    _countdownTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  // ── Input ──────────────────────────────────────────────────────────────────

  void _onKeyTap(String digit) {
    if (_code.length >= 6 || _loading) return;
    setState(() {
      _code += digit;
      _feedback = _FeedbackState.idle;
      _message = '';
    });
  }

  void _onDelete() {
    if (_code.isEmpty || _loading) return;
    setState(() {
      _code = _code.substring(0, _code.length - 1);
      _feedback = _FeedbackState.idle;
      _message = '';
    });
  }

  // ── Submit ─────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (_code.length != 6 || _loading) return;

    // Re-check gate state right now — the UI may not have refreshed yet
    // even if the session closed a few seconds ago.
    final session = ref
        .read(_codeSessionProvider(widget.sessionId))
        .valueOrNull;
    final testMode =
        ref.read(_testModeProvider).valueOrNull ?? false;
    if (session != null && session.startTime != null && !testMode) {
      final gate = sessionGateState(
          session.startTime, session.endTime, nowInLagos());
      if (gate == SessionGateState.closed) {
        setState(() {
          _feedback = _FeedbackState.error;
          _message =
              'Session is closed. Check-in is no longer available.';
        });
        return;
      }
    }

    setState(() => _loading = true);

    try {
      final submittedCode = _code;
      final clockIn =
          await ref.read(attendanceServiceProvider).clockInByOfflineCode(
            sessionId: widget.sessionId,
            code: submittedCode,
            status: AttendanceStatus.present,
          );
      final member = await ref
          .read(memberServiceProvider)
          .getMemberByOfflineCode(submittedCode);
      if (member == null) {
        throw Exception('Member not found');
      }

      if (!mounted) return;
      await context.push(
        '/verification',
        extra: {
          'member': member,
          'entryTime': clockIn.clockedAt,
          'status': clockIn.status,
        },
      );

      if (!mounted) return;
      setState(() {
        _code = '';
        _feedback = _FeedbackState.idle;
        _message = '';
      });
    } on Exception catch (e) {
      final msg = e.toString();
      if (msg.contains('Already marked')) {
        setState(() {
          _feedback = _FeedbackState.warning;
          _message = 'Already marked for this session.';
          _code = '';
        });
      } else if (msg.contains('Member not found')) {
        setState(() {
          _feedback = _FeedbackState.error;
          _message = 'Code not found. Check the number and try again.';
          _code = '';
        });
      } else {
        setState(() {
          _feedback = _FeedbackState.error;
          _message = 'Something went wrong.';
          _code = '';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final sessionAsync =
        ref.watch(_codeSessionProvider(widget.sessionId));
    final testModeAsync = ref.watch(_testModeProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
        title: const Text(
          'Check-in',
          style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F172A)),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.close, color: Color(0xFF0F172A)),
            onPressed: () => context.pop(),
          ),
        ],
      ),
      body: SafeArea(
        child: sessionAsync.when(
          loading: () =>
              const Center(child: CircularProgressIndicator()),
          error: (e, _) => const Center(child: Text('Unable to load. Please try again.')),
          data: (session) {
            if (session == null) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Session not found.'),
                    TextButton(
                        onPressed: () => context.go('/sessions'),
                        child: const Text('Go back')),
                  ],
                ),
              );
            }

            return testModeAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              // On error, fail open — show OTP keypad
              error: (_, __) => _buildOtpBody(),
              data: (testMode) {
                // Test mode or no start time → bypass gate
                if (testMode || session.startTime == null) {
                  return _buildOtpBody();
                }
                final gate = sessionGateState(
                  session.startTime,
                  session.endTime,
                  nowInLagos(),
                );
                switch (gate) {
                  case SessionGateState.noGate:
                  case SessionGateState.open:
                    return _buildOtpBody();
                  case SessionGateState.tooEarly:
                    final ms = msUntilTime(
                        session.startTime!, nowInLagos());
                    return _buildTooEarlyBody(
                        session.startTime!, msToCountdown(ms));
                  case SessionGateState.closed:
                    return _buildClosedBody();
                }
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildOtpBody() {
    return _Body(
      sessionId: widget.sessionId,
      code: _code,
      feedback: _feedback,
      message: _message,
      loading: _loading,
      onKeyTap: _onKeyTap,
      onDelete: _onDelete,
      onSubmit: _submit,
    );
  }

  Widget _buildTooEarlyBody(String startTime, String countdown) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.access_time,
              size: 64,
              color: AppTheme.primary,
            ),
            const SizedBox(height: 20),
            Text(
              countdown,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Service opens at $startTime',
              style: const TextStyle(
                  fontSize: 14, color: AppTheme.slate500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClosedBody() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.lock_clock,
              size: 64,
              color: AppTheme.slate500,
            ),
            const SizedBox(height: 20),
            const Text(
              'Session Closed',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Check-in for this service has ended.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14, color: AppTheme.slate500),
            ),
            const SizedBox(height: 32),
            OutlinedButton(
              onPressed: () => context.go('/sessions'),
              child: const Text('Go Back'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _Body
// ---------------------------------------------------------------------------

class _Body extends StatelessWidget {
  const _Body({
    required this.sessionId,
    required this.code,
    required this.feedback,
    required this.message,
    required this.loading,
    required this.onKeyTap,
    required this.onDelete,
    required this.onSubmit,
  });

  final String sessionId;
  final String code;
  final _FeedbackState feedback;
  final String message;
  final bool loading;
  final ValueChanged<String> onKeyTap;
  final VoidCallback onDelete;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const SizedBox(height: 8),

          // ── Church icon circle ──────────────────────────────────────
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: Color(0xFFF1F5F9),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.church,
                color: AppTheme.primary, size: 28),
          ),
          const SizedBox(height: 14),

          // ── "Welcome!" heading ─────────────────────────────────────
          const Text(
            'Welcome!',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Enter your 6-digit attendance code below',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppTheme.slate500),
          ),
          const SizedBox(height: 20),

          // ── 6 OTP boxes ────────────────────────────────────────────
          _CodeDisplay(code: code, feedback: feedback),
          const SizedBox(height: 8),

          // ── Feedback banner ─────────────────────────────────────────
          if (feedback != _FeedbackState.idle) ...[
            _FeedbackBanner(feedback: feedback, message: message),
            const SizedBox(height: 8),
          ],

          const SizedBox(height: 12),

          // ── "Scan QR Code instead" button ──────────────────────────
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.qr_code_scanner, size: 18),
              label: const Text('Scan QR Code instead'),
              onPressed: () =>
                  context.push('/sessions/$sessionId/checkin'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primary,
                side: const BorderSide(color: AppTheme.primary),
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ── Custom numpad ───────────────────────────────────────────
          _NumericKeypad(
            onKeyTap: onKeyTap,
            onDelete: onDelete,
            enabled: !loading,
          ),
          const SizedBox(height: 16),

          // ── Confirm button ──────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (code.length == 6 && !loading) ? onSubmit : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                minimumSize: const Size(double.infinity, 52),
              ),
              child: loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text(
                      'Confirm Check-in  →',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700),
                    ),
            ),
          ),
          const SizedBox(height: 20),

          // ── Footer ─────────────────────────────────────────────────
          const Text(
            'ATTENDANCE MINISTRY',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppTheme.slate500,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _CodeDisplay — 6 OTP-style boxes, digits shown as dots
// ---------------------------------------------------------------------------

class _CodeDisplay extends StatelessWidget {
  const _CodeDisplay({required this.code, required this.feedback});
  final String code;
  final _FeedbackState feedback;

  Color get _borderColor {
    switch (feedback) {
      case _FeedbackState.success:
        return AppTheme.success;
      case _FeedbackState.error:
        return AppTheme.error;
      case _FeedbackState.warning:
        return AppTheme.amber;
      case _FeedbackState.idle:
        return AppTheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(6, (i) {
        final filled = i < code.length;
        final isCurrent = i == code.length && i < 6;

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: 48,
          height: 56,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: filled || isCurrent
                  ? _borderColor
                  : AppTheme.slate200,
              width: filled || isCurrent ? 2 : 1,
            ),
          ),
          child: Center(
            child: filled
                ? Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _borderColor,
                      shape: BoxShape.circle,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        );
      }),
    );
  }
}

// ---------------------------------------------------------------------------
// _FeedbackBanner
// ---------------------------------------------------------------------------

class _FeedbackBanner extends StatelessWidget {
  const _FeedbackBanner(
      {required this.feedback, required this.message});
  final _FeedbackState feedback;
  final String message;

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    IconData icon;

    switch (feedback) {
      case _FeedbackState.success:
        bg = AppTheme.successBg;
        fg = const Color(0xFF065F46);
        icon = Icons.check_circle_outline;
        break;
      case _FeedbackState.warning:
        bg = AppTheme.amberBg;
        fg = const Color(0xFF92400E);
        icon = Icons.warning_amber_rounded;
        break;
      case _FeedbackState.error:
        bg = AppTheme.errorBg;
        fg = AppTheme.error;
        icon = Icons.error_outline;
        break;
      case _FeedbackState.idle:
        return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 8),
          Expanded(
              child: Text(message,
                  style: TextStyle(fontSize: 13, color: fg))),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _NumericKeypad — 3×3 digits + bottom row [spacer / 0 / backspace]
// ---------------------------------------------------------------------------

class _NumericKeypad extends StatelessWidget {
  const _NumericKeypad({
    required this.onKeyTap,
    required this.onDelete,
    required this.enabled,
  });
  final ValueChanged<String> onKeyTap;
  final VoidCallback onDelete;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
    ];

    return Column(
      children: [
        // Digit rows 1–9
        ...rows.map((row) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: row.map((key) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: _KeyButton(
                      label: key,
                      enabled: enabled,
                      onTap: () {
                        if (enabled) onKeyTap(key);
                      },
                    ),
                  ),
                );
              }).toList(),
            ),
          );
        }),

        // Bottom row: spacer / 0 / backspace
        Row(
          children: [
            // Empty spacer
            const Expanded(child: SizedBox()),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: _KeyButton(
                  label: '0',
                  enabled: enabled,
                  onTap: () {
                    if (enabled) onKeyTap('0');
                  },
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: _KeyButton(
                  label: '⌫',
                  isAction: true,
                  enabled: enabled,
                  onTap: () {
                    if (enabled) onDelete();
                  },
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _KeyButton extends StatelessWidget {
  const _KeyButton({
    required this.label,
    required this.onTap,
    required this.enabled,
    this.isAction = false,
  });
  final String label;
  final VoidCallback onTap;
  final bool enabled;
  final bool isAction;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isAction ? AppTheme.slate200 : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.slate200),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: isAction ? 18 : 22,
                fontWeight: FontWeight.w600,
                color: enabled
                    ? AppTheme.primary
                    : const Color(0xFFCBD5E1),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Feedback state enum
// ---------------------------------------------------------------------------

enum _FeedbackState { idle, success, warning, error }
