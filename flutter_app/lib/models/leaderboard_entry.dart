// lib/models/leaderboard_entry.dart
//
// Read model — maps to the `monthly_leaderboard` Supabase view.
// Used on the Leaderboard and Reports screens.

import 'enums.dart';

class LeaderboardEntry {
  const LeaderboardEntry({
    required this.rank,
    required this.memberId,
    required this.memberName,
    required this.team,
    required this.offlineCode,
    required this.presentCount,
    required this.yearMonth,
  });

  final int rank;
  final String memberId;
  final String memberName;
  final Team team;
  final String offlineCode;
  final int presentCount;

  /// Format: "YYYY-MM"
  final String yearMonth;

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json, {int rank = 0}) {
    return LeaderboardEntry(
      rank: rank,
      memberId: json['member_id'] as String,
      memberName: json['full_name'] as String,
      team: Team.fromValue(json['team'] as String),
      offlineCode: json['offline_code'] as String,
      presentCount: (json['present_count'] as num?)?.toInt() ?? 0,
      yearMonth: json['year_month'] as String,
    );
  }
}
