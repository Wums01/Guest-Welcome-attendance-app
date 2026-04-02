// lib/models/program.dart

import 'enums.dart';

// ---------------------------------------------------------------------------
// Program
// ---------------------------------------------------------------------------
// Mirrors the TypeScript Program type and the Supabase `programs` table.
//
// Key business rule:
//   - isTBD == true  → startDate / endDate are null
//   - isTBD == false → startDate required, endDate >= startDate
// ---------------------------------------------------------------------------

class Program {
  const Program({
    required this.id,
    required this.title,
    required this.programType,
    required this.isTBD,
    required this.isVirtual,
    this.startDate,
    this.endDate,
    this.teamScope,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final ProgramType programType;
  final bool isTBD;

  /// Meetings and trainings can be physical or virtual.
  final bool isVirtual;

  /// Null when isTBD == true. Format: YYYY-MM-DD (stored as String to stay
  /// consistent with the DB DATE type returned as a plain string by Supabase).
  final String? startDate;
  final String? endDate;

  /// 'all' | Team.value | null
  final String? teamScope;

  final DateTime createdAt;
  final DateTime updatedAt;

  // ── JSON ─────────────────────────────────────────────────────────────────

  factory Program.fromJson(Map<String, dynamic> json) {
    return Program(
      id: json['id'] as String,
      title: json['title'] as String,
      programType: ProgramType.fromValue(json['program_type'] as String),
      isTBD: json['is_tbd'] as bool? ?? false,
      isVirtual: json['is_virtual'] as bool? ?? false,
      startDate: json['start_date'] as String?,
      endDate: json['end_date'] as String?,
      teamScope: json['team_scope'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'program_type': programType.value,
        'is_tbd': isTBD,
        'is_virtual': isVirtual,
        'start_date': startDate,
        'end_date': endDate,
        'team_scope': teamScope,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  Map<String, dynamic> toInsertJson() => {
        'title': title,
        'program_type': programType.value,
        'is_tbd': isTBD,
        'is_virtual': isVirtual,
        'start_date': startDate,
        'end_date': endDate,
        'team_scope': teamScope,
      };

  Program copyWith({
    String? title,
    ProgramType? programType,
    bool? isTBD,
    bool? isVirtual,
    String? startDate,
    String? endDate,
    String? teamScope,
  }) {
    return Program(
      id: id,
      title: title ?? this.title,
      programType: programType ?? this.programType,
      isTBD: isTBD ?? this.isTBD,
      isVirtual: isVirtual ?? this.isVirtual,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      teamScope: teamScope ?? this.teamScope,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
