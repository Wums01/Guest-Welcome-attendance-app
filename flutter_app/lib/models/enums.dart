// lib/models/enums.dart
//
// Dart equivalents of the TypeScript union types in lib/types.ts
// All enums provide:
//   - .value  → the Supabase DB string
//   - fromValue() factory → parse from DB string

// ---------------------------------------------------------------------------
// Team
// ---------------------------------------------------------------------------
enum Team {
  teamA('Team A'),
  teamB('Team B'),
  teamC('Team C'),
  none('None');

  const Team(this.value);
  final String value;

  static Team fromValue(String v) =>
      Team.values.firstWhere((e) => e.value == v,
          orElse: () => throw ArgumentError('Unknown team: $v'));

  @override
  String toString() => value;
}

// ---------------------------------------------------------------------------
// ProgramType
// ---------------------------------------------------------------------------
enum ProgramType {
  sunday('sunday'),
  wednesday('wednesday'),
  program('program'),
  meeting('meeting'),
  training('training');

  const ProgramType(this.value);
  final String value;

  static ProgramType fromValue(String v) =>
      ProgramType.values.firstWhere((e) => e.value == v,
          orElse: () => throw ArgumentError('Unknown program type: $v'));

  String get displayName {
    switch (this) {
      case ProgramType.sunday:
        return 'Sunday Service';
      case ProgramType.wednesday:
        return 'Wednesday Service';
      case ProgramType.program:
        return 'Program';
      case ProgramType.meeting:
        return 'Meeting';
      case ProgramType.training:
        return 'Training';
    }
  }
}

// ---------------------------------------------------------------------------
// AttendanceStatus
// ---------------------------------------------------------------------------
enum AttendanceStatus {
  present('present'),
  absent('absent'),
  excused('excused');

  const AttendanceStatus(this.value);
  final String value;

  static AttendanceStatus fromValue(String v) =>
      AttendanceStatus.values.firstWhere((e) => e.value == v,
          orElse: () => throw ArgumentError('Unknown status: $v'));

  /// Returns true if this status is terminal (cannot be changed).
  /// Mirrors the DB trigger: present/excused are immutable.
  bool get isTerminal =>
      this == AttendanceStatus.present || this == AttendanceStatus.excused;
}

// ---------------------------------------------------------------------------
// StaffRole
// ---------------------------------------------------------------------------
enum StaffRole {
  teamLead('team_lead'),
  assistant('assistant');

  const StaffRole(this.value);
  final String value;

  static StaffRole fromValue(String v) =>
      StaffRole.values.firstWhere((e) => e.value == v,
          orElse: () => throw ArgumentError('Unknown staff role: $v'));

  String get displayName {
    switch (this) {
      case StaffRole.teamLead:
        return 'Team Lead';
      case StaffRole.assistant:
        return 'Assistant';
    }
  }
}

// ---------------------------------------------------------------------------
// ClockInMethod
// ---------------------------------------------------------------------------
enum ClockInMethod {
  manual('manual'),
  qr('qr'),
  self('self'),
  offlineCode('offline_code');

  const ClockInMethod(this.value);
  final String value;

  static ClockInMethod fromValue(String v) =>
      ClockInMethod.values.firstWhere((e) => e.value == v,
          orElse: () => throw ArgumentError('Unknown method: $v'));
}
