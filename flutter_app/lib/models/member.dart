// lib/models/member.dart

import 'enums.dart';

// ---------------------------------------------------------------------------
// Member
// ---------------------------------------------------------------------------
// Mirrors the TypeScript Member type and the Supabase `members` table.
//
// birthdayMD / anniversaryMD are stored as "MM-DD" strings — exactly
// as in the original system so celebration logic is portable.
// ---------------------------------------------------------------------------

class Member {
  const Member({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.offlineCode,
    required this.team,
    required this.isMarried,
    required this.birthdayMD,
    this.anniversaryMD,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String fullName;
  final String phone;

  /// 6-digit numeric code used for offline attendance entry.
  final String offlineCode;

  final Team team;
  final bool isMarried;

  /// Format: "MM-DD"
  final String birthdayMD;

  /// Format: "MM-DD" — only set when isMarried == true
  final String? anniversaryMD;

  final DateTime createdAt;
  final DateTime updatedAt;

  // ── JSON ─────────────────────────────────────────────────────────────────

  factory Member.fromJson(Map<String, dynamic> json) {
    return Member(
      id: json['id'] as String,
      fullName: json['full_name'] as String,
      phone: json['phone'] as String? ?? '',
      offlineCode: json['offline_code'] as String,
      team: Team.fromValue(json['team'] as String),
      isMarried: json['is_married'] as bool? ?? false,
      birthdayMD: json['birthday_md'] as String,
      anniversaryMD: json['anniversary_md'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'full_name': fullName,
        'phone': phone,
        'offline_code': offlineCode,
        'team': team.value,
        'is_married': isMarried,
        'birthday_md': birthdayMD,
        'anniversary_md': anniversaryMD,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  /// Returns a map suitable for INSERT (excludes auto-generated fields).
  Map<String, dynamic> toInsertJson() => {
        'full_name': fullName,
        'phone': phone,
        'offline_code': offlineCode,
        'team': team.value,
        'is_married': isMarried,
        'birthday_md': birthdayMD,
        'anniversary_md': anniversaryMD,
      };

  Member copyWith({
    String? fullName,
    String? phone,
    Team? team,
    bool? isMarried,
    String? birthdayMD,
    String? anniversaryMD,
  }) {
    return Member(
      id: id,
      fullName: fullName ?? this.fullName,
      phone: phone ?? this.phone,
      offlineCode: offlineCode,
      team: team ?? this.team,
      isMarried: isMarried ?? this.isMarried,
      birthdayMD: birthdayMD ?? this.birthdayMD,
      anniversaryMD: anniversaryMD ?? this.anniversaryMD,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  @override
  String toString() => 'Member(id: $id, fullName: $fullName, team: $team)';
}
