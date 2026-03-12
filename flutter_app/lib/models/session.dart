// lib/models/session.dart

// ---------------------------------------------------------------------------
// Session
// ---------------------------------------------------------------------------
// Mirrors the TypeScript Session type and the Supabase `sessions` table.
//
// Sunday programs produce 3 sessions per date:
//   "Service 1" → Team A  (clock-in opens 06:30 Lagos)
//   "Service 2" → Team B  (clock-in opens 08:30 Lagos)
//   "Service 3" → Team C  (clock-in opens 11:00 Lagos)
// Wednesday programs produce 1 session: "Switch Service"
// ---------------------------------------------------------------------------

class Session {
  const Session({
    required this.id,
    required this.programId,
    required this.name,
    required this.date,
    this.startTime,
    this.endTime,
    required this.clockInRequired,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String programId;
  final String name;

  /// Format: "YYYY-MM-DD"
  final String date;

  /// Format: "HH:mm" — null if not set
  final String? startTime;
  final String? endTime;

  final bool clockInRequired;
  final DateTime createdAt;
  final DateTime updatedAt;

  // ── JSON ─────────────────────────────────────────────────────────────────

  factory Session.fromJson(Map<String, dynamic> json) {
    return Session(
      id: json['id'] as String,
      programId: json['program_id'] as String,
      name: json['name'] as String,
      date: json['date'] as String,
      startTime: json['start_time'] as String?,
      endTime: json['end_time'] as String?,
      clockInRequired: json['clock_in_required'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'program_id': programId,
        'name': name,
        'date': date,
        'start_time': startTime,
        'end_time': endTime,
        'clock_in_required': clockInRequired,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  Map<String, dynamic> toInsertJson() => {
        'program_id': programId,
        'name': name,
        'date': date,
        'start_time': startTime,
        'end_time': endTime,
        'clock_in_required': clockInRequired,
      };
}
