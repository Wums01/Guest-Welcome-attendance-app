// lib/models/attendance_summary.dart
//
// Read model — maps to the `session_attendance_summary` Supabase view.
// Used on the Reports screen.

class AttendanceSummary {
  const AttendanceSummary({
    required this.sessionId,
    required this.sessionName,
    required this.sessionDate,
    required this.programId,
    required this.programTitle,
    required this.newGuestCount,
    required this.presentCount,
    required this.absentCount,
    required this.excusedCount,
    required this.totalMarked,
  });

  final String sessionId;
  final String sessionName;
  final String sessionDate;
  final String programId;
  final String programTitle;
  final int newGuestCount;
  final int presentCount;
  final int absentCount;
  final int excusedCount;
  final int totalMarked;

  factory AttendanceSummary.fromJson(Map<String, dynamic> json) {
    return AttendanceSummary(
      sessionId: json['session_id'] as String,
      sessionName: json['session_name'] as String,
      sessionDate: json['session_date'] as String,
      programId: json['program_id'] as String,
      programTitle: json['program_title'] as String,      newGuestCount: (json['new_guest_count'] as num?)?.toInt() ?? 0,      presentCount: (json['present_count'] as num?)?.toInt() ?? 0,
      absentCount: (json['absent_count'] as num?)?.toInt() ?? 0,
      excusedCount: (json['excused_count'] as num?)?.toInt() ?? 0,
      totalMarked: (json['total_marked'] as num?)?.toInt() ?? 0,
    );
  }
}
