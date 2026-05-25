import 'enums.dart';

class AttendanceExportEntry {
  const AttendanceExportEntry({
    required this.sessionId,
    required this.sessionName,
    required this.memberName,
    required this.status,
    required this.clockedAt,
    this.positionLabel,
  });

  final String sessionId;
  final String sessionName;
  final String memberName;
  final AttendanceStatus status;
  final DateTime clockedAt;
  final String? positionLabel;

  factory AttendanceExportEntry.fromJson(Map<String, dynamic> json) {
    final member = json['members'] as Map<String, dynamic>?;
    final session = json['sessions'] as Map<String, dynamic>?;

    return AttendanceExportEntry(
      sessionId: json['session_id'] as String,
      sessionName: (session?['name'] as String?) ?? 'Session',
      memberName: (member?['full_name'] as String?) ?? 'Unknown Member',
      status: AttendanceStatus.fromValue(json['status'] as String),
      clockedAt: DateTime.parse(json['clocked_at'] as String),
      positionLabel: json['position_label'] as String?,
    );
  }
}
