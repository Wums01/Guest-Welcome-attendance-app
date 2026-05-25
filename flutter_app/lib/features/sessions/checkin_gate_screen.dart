import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import '../../models/enums.dart';
import '../../models/session.dart';
import '../../services/attendance_service.dart';
import '../../services/member_service.dart';
import '../../services/session_service.dart';
import '../../app_theme/app_theme.dart';
import '../../core/utils/date_utils.dart';
import '../attendance/position_assignment_dialog.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

final _testModeProvider = FutureProvider<bool>((ref) async {
  final data = await Supabase.instance.client
      .from('settings')
      .select('value')
      .eq('key', 'test_mode_enabled')
      .maybeSingle();
  return data?['value'] == 'true';
});

final _sessionDetailProvider =
    FutureProvider.family<Session?, String>((ref, id) {
  return ref.read(sessionServiceProvider).getSessionById(id);
});

// ── CheckinGateScreen ─────────────────────────────────────────────────────────

class CheckinGateScreen extends ConsumerStatefulWidget {
  const CheckinGateScreen({super.key, required this.sessionId});
  final String sessionId;

  @override
  ConsumerState<CheckinGateScreen> createState() => _CheckinGateScreenState();
}

class _CheckinGateScreenState extends ConsumerState<CheckinGateScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _torchOn = false;
  bool _processing = false;
  Timer? _gateRefreshTimer;

  @override
  void initState() {
    super.initState();
    // Re-evaluate gate state every 30 s so TooEarly → Open transition is automatic
    _gateRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      ref.invalidate(_sessionDetailProvider(widget.sessionId));
    });
  }

  @override
  void dispose() {
    _gateRefreshTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_processing) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw.isEmpty) return;

    final code = raw.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) return;

    // Re-check gate state immediately before processing.
    // The visual gate auto-refreshes every 30 s, but the user could scan
    // in the final seconds before close.
    final testMode = ref.read(_testModeProvider).valueOrNull ?? false;
    if (!testMode) {
      final session =
          ref.read(_sessionDetailProvider(widget.sessionId)).valueOrNull;
      if (session != null && session.startTime != null) {
        final gate =
            sessionGateState(session.startTime, session.endTime, nowInLagos());
        if (gate == SessionGateState.closed) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content:
                    Text('Session is closed. Check-in is no longer available.'),
                backgroundColor: AppTheme.error,
              ),
            );
          }
          return;
        }
      }
    }

    setState(() => _processing = true);
    try {
      final member =
          await ref.read(memberServiceProvider).getMemberByOfflineCode(code);
      if (member == null) {
        throw Exception('Member not found');
      }

      final options = await ref
          .read(attendanceServiceProvider)
          .getPositionOptionsForSession(widget.sessionId);
      if (!mounted) return;
      final positionLabel = await showPositionAssignmentDialog(
        context: context,
        memberName: member.fullName,
        options: options,
      );
      if (!mounted) return;

      final clockIn =
          await ref.read(attendanceServiceProvider).clockInByOfflineCode(
                sessionId: widget.sessionId,
                code: code,
                status: AttendanceStatus.present,
                positionLabel: positionLabel,
              );

      if (!mounted) return;
      await context.push(
        '/verification',
        extra: {
          'member': member,
          'entryTime': clockIn.clockedAt,
          'status': clockIn.status,
          'positionLabel': clockIn.positionLabel,
        },
      );

      if (!mounted) return;
      setState(() => _processing = false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: AppTheme.error,
          ),
        );
        setState(() => _processing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Load test mode and session in parallel
    final testModeAsync = ref.watch(_testModeProvider);
    final sessionAsync = ref.watch(_sessionDetailProvider(widget.sessionId));

    return testModeAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      // On error, fail open — show scanner
      error: (_, __) => _buildScannerScaffold(),
      data: (testMode) {
        // Test mode bypasses the gate entirely
        if (testMode) return _buildScannerScaffold();

        return sessionAsync.when(
          loading: () => const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          ),
          // On error, fail open — show scanner
          error: (_, __) => _buildScannerScaffold(),
          data: (session) {
            // No session or no startTime → no gate, show scanner
            if (session == null || session.startTime == null) {
              return _buildScannerScaffold();
            }

            final gate = sessionGateState(
              session.startTime,
              session.endTime,
              nowInLagos(),
            );

            switch (gate) {
              case SessionGateState.noGate:
              case SessionGateState.open:
                return _buildScannerScaffold();
              case SessionGateState.tooEarly:
                return _TooEarlyScreen(
                  session: session,
                  sessionId: widget.sessionId,
                );
              case SessionGateState.closed:
                return _ClosedScreen(session: session);
            }
          },
        );
      },
    );
  }

  Scaffold _buildScannerScaffold() {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => context.go('/sessions'),
        ),
        title: const Text(
          'Guest Check-in',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline, color: Colors.white),
            onPressed: () => showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('QR Check-in'),
                content: const Text(
                    'Ask the member to show their QR code, or tap "Enter Code Manually" to type their 6-digit code.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('OK')),
                ],
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // ── Camera full screen ─────────────────────────────────────────
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),

          // ── Darkened overlay with hole ─────────────────────────────────
          Column(
            children: [
              Expanded(flex: 3, child: Container(color: Colors.black54)),
              Row(
                children: [
                  Expanded(child: Container(color: Colors.black54)),
                  SizedBox(
                    width: 260,
                    height: 260,
                    child: _ScanFrame(),
                  ),
                  Expanded(child: Container(color: Colors.black54)),
                ],
              ),
              Expanded(flex: 4, child: Container(color: Colors.black54)),
            ],
          ),

          // ── Scanning status pill ───────────────────────────────────────
          Positioned(
            bottom: 226,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppTheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _processing ? 'Processing...' : 'Scanning for QR Code...',
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Hint text ──────────────────────────────────────────────────
          Positioned(
            bottom: 188,
            left: 48,
            right: 48,
            child: Text(
              'Align the member\'s check-in code within the frame to automatically scan',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontSize: 12,
              ),
            ),
          ),

          // ── Flashlight toggle ──────────────────────────────────────────
          Positioned(
            bottom: 110,
            left: 0,
            right: 0,
            child: Center(
              child: _CameraIconButton(
                icon: _torchOn ? Icons.flash_on : Icons.flash_off,
                label: 'FLASHLIGHT',
                onTap: () {
                  _controller.toggleTorch();
                  setState(() => _torchOn = !_torchOn);
                },
              ),
            ),
          ),

          // ── Enter Code Manually button ─────────────────────────────────
          Positioned(
            bottom: 36,
            left: 24,
            right: 24,
            child: ElevatedButton.icon(
              onPressed: () =>
                  context.push('/sessions/${widget.sessionId}/code'),
              icon: const Icon(Icons.keyboard, size: 18),
              label: const Text('Enter Code Manually'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── _TooEarlyScreen ───────────────────────────────────────────────────────────

class _TooEarlyScreen extends StatefulWidget {
  const _TooEarlyScreen({
    required this.session,
    required this.sessionId,
  });
  final Session session;
  final String sessionId;

  @override
  State<_TooEarlyScreen> createState() => _TooEarlyScreenState();
}

class _TooEarlyScreenState extends State<_TooEarlyScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Refresh the countdown display every 30 seconds
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ms = msUntilTime(widget.session.startTime!, nowInLagos());
    final countdown = msToCountdown(ms);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => context.go('/sessions'),
        ),
        title: const Text('Guest Check-in'),
      ),
      body: Center(
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
                'Service opens at ${widget.session.startTime}',
                style: const TextStyle(
                  fontSize: 14,
                  color: AppTheme.slate500,
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () =>
                    context.push('/sessions/${widget.sessionId}/code'),
                icon: const Icon(Icons.keyboard, size: 18),
                label: const Text('Enter Code Manually'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── _ClosedScreen ─────────────────────────────────────────────────────────────

class _ClosedScreen extends StatelessWidget {
  const _ClosedScreen({required this.session});
  final Session session;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => context.go('/sessions'),
        ),
        title: const Text('Guest Check-in'),
      ),
      body: Center(
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
                  fontSize: 14,
                  color: AppTheme.slate500,
                ),
              ),
              const SizedBox(height: 32),
              OutlinedButton(
                onPressed: () => context.go('/sessions'),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── _ScanFrame ────────────────────────────────────────────────────────────────

class _ScanFrame extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _FramePainter(),
      child: const SizedBox(width: 260, height: 260),
    );
  }
}

class _FramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.primary
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const c = 36.0; // corner length

    // Top-left
    canvas.drawLine(Offset.zero, const Offset(c, 0), paint);
    canvas.drawLine(Offset.zero, const Offset(0, c), paint);
    // Top-right
    canvas.drawLine(Offset(size.width, 0), Offset(size.width - c, 0), paint);
    canvas.drawLine(Offset(size.width, 0), Offset(size.width, c), paint);
    // Bottom-left
    canvas.drawLine(Offset(0, size.height), Offset(c, size.height), paint);
    canvas.drawLine(Offset(0, size.height), Offset(0, size.height - c), paint);
    // Bottom-right
    canvas.drawLine(Offset(size.width, size.height),
        Offset(size.width - c, size.height), paint);
    canvas.drawLine(Offset(size.width, size.height),
        Offset(size.width, size.height - c), paint);

    // Centre scan line
    final line = Paint()
      ..color = AppTheme.primary.withValues(alpha: 0.5)
      ..strokeWidth = 2;
    canvas.drawLine(Offset(8, size.height / 2),
        Offset(size.width - 8, size.height / 2), line);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ── _CameraIconButton ─────────────────────────────────────────────────────────

class _CameraIconButton extends StatelessWidget {
  const _CameraIconButton(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: Colors.black45,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
