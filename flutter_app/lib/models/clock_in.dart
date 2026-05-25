// lib/models/clock_in.dart

import 'enums.dart';

// ---------------------------------------------------------------------------
// ClockIn  (Attendance Record)
// ---------------------------------------------------------------------------
// Mirrors the TypeScript ClockIn type and the Supabase `clock_ins` table.
//
// Status lifecycle (enforced by DB trigger AND service layer):
//   absent  ──upgrade──▶  present  (terminal)
//   absent  ──upgrade──▶  excused  (terminal)
//   present ──────────▶  LOCKED — cannot change
//   excused ──────────▶  LOCKED — cannot change
//
// 'absent' is never set by the UI — only by finalizeSessionAbsences().
// ---------------------------------------------------------------------------

class ClockIn {
  const ClockIn({
    required this.id,
    required this.sessionId,
    required this.memberId,
    required this.status,
    required this.method,
    required this.clockedAt,
    this.positionLabel,
  });

  final String id;
  final String sessionId;
  final String memberId;
  final AttendanceStatus status;
  final ClockInMethod method;
  final String? positionLabel;

  /// The canonical timestamp for this attendance record.
  /// For an absent→present upgrade this is updated to the time of upgrade.
  final DateTime clockedAt;

  // ── JSON ─────────────────────────────────────────────────────────────────

  factory ClockIn.fromJson(Map<String, dynamic> json) {
    return ClockIn(
      id: json['id'] as String,
      sessionId: json['session_id'] as String,
      memberId: json['member_id'] as String,
      status: AttendanceStatus.fromValue(json['status'] as String),
      method: ClockInMethod.fromValue(json['method'] as String),
      clockedAt: DateTime.parse(json['clocked_at'] as String),
      positionLabel: json['position_label'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'session_id': sessionId,
        'member_id': memberId,
        'status': status.value,
        'method': method.value,
        'clocked_at': clockedAt.toIso8601String(),
        'position_label': positionLabel,
      };

  Map<String, dynamic> toInsertJson() => {
        'session_id': sessionId,
        'member_id': memberId,
        'status': status.value,
        'method': method.value,
        'clocked_at': clockedAt.toIso8601String(),
        if (positionLabel != null) 'position_label': positionLabel,
      };

  ClockIn copyWith({
    AttendanceStatus? status,
    ClockInMethod? method,
    DateTime? clockedAt,
    String? positionLabel,
  }) {
    return ClockIn(
      id: id,
      sessionId: sessionId,
      memberId: memberId,
      status: status ?? this.status,
      method: method ?? this.method,
      clockedAt: clockedAt ?? this.clockedAt,
      positionLabel: positionLabel ?? this.positionLabel,
    );
  }
}
