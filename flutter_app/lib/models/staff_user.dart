// lib/models/staff_user.dart
import 'enums.dart';

class StaffUser {
  final String id;
  final String fullName;
  final Team team;
  final StaffRole role;
  final String? avatarUrl;
  final bool isFirstLogin; // true when password_hash is NULL in DB

  const StaffUser({
    required this.id,
    required this.fullName,
    required this.team,
    required this.role,
    this.avatarUrl,
    required this.isFirstLogin,
  });

  factory StaffUser.fromJson(Map<String, dynamic> json) => StaffUser(
        id: json['id'] as String,
        fullName: json['full_name'] as String,
        team: Team.fromValue(json['team'] as String),
        role: StaffRole.fromValue(json['role'] as String),
        avatarUrl: json['avatar_url'] as String?,
        isFirstLogin: json['password_hash'] == null,
      );

  StaffUser copyWith({
    String? id,
    String? fullName,
    Team? team,
    StaffRole? role,
    String? avatarUrl,
    bool? isFirstLogin,
  }) =>
      StaffUser(
        id: id ?? this.id,
        fullName: fullName ?? this.fullName,
        team: team ?? this.team,
        role: role ?? this.role,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        isFirstLogin: isFirstLogin ?? this.isFirstLogin,
      );
}
