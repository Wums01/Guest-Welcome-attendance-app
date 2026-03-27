import 'package:flutter/material.dart';
import '../app_theme/app_theme.dart';
import '../models/enums.dart';

/// Coloured pill badge for an attendance status (Present / Absent / Excused).
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status, this.clockedAt});

  final AttendanceStatus status;
  /// Optional time string shown below the status label (e.g. "08:45 AM").
  final String? clockedAt;

  @override
  Widget build(BuildContext context) {
    final (bg, text, label) = switch (status) {
      AttendanceStatus.present =>
        (AppTheme.successBg, AppTheme.success, 'PRESENT'),
      AttendanceStatus.absent =>
        (AppTheme.errorBg, AppTheme.error, 'ABSENT'),
      AttendanceStatus.excused =>
        (AppTheme.amberBg, AppTheme.amber, 'EXCUSED'),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: text,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ),
        if (clockedAt != null) ...[
          const SizedBox(height: 2),
          Text(
            clockedAt!,
            style: const TextStyle(color: AppTheme.slate500, fontSize: 11),
          ),
        ],
      ],
    );
  }
}
