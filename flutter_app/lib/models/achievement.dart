// lib/models/achievement.dart

enum AchievementType {
  streak4,
  streak8,
  streak16,
  tierBronze,
  tierSilver,
  tierGold,
  tierPlatinum,
  perfectMonth,
  anniversary1yr,
  anniversary2yr;

  static AchievementType fromString(String value) {
    return switch (value) {
      'streak_4'        => streak4,
      'streak_8'        => streak8,
      'streak_16'       => streak16,
      'tier_bronze'     => tierBronze,
      'tier_silver'     => tierSilver,
      'tier_gold'       => tierGold,
      'tier_platinum'   => tierPlatinum,
      'perfect_month'   => perfectMonth,
      'anniversary_1yr' => anniversary1yr,
      'anniversary_2yr' => anniversary2yr,
      _                 => throw ArgumentError('Unknown achievement type: $value'),
    };
  }
}

class Achievement {
  const Achievement({
    required this.id,
    required this.memberId,
    required this.achievementType,
    required this.achievedAt,
    this.metadata,
  });

  final String id;
  final String memberId;
  final AchievementType achievementType;
  final DateTime achievedAt;
  final Map<String, dynamic>? metadata;

  factory Achievement.fromJson(Map<String, dynamic> json) {
    return Achievement(
      id: json['id'] as String,
      memberId: json['member_id'] as String,
      achievementType:
          AchievementType.fromString(json['achievement_type'] as String),
      achievedAt: DateTime.parse(json['achieved_at'] as String),
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  String get label => switch (achievementType) {
    AchievementType.streak4        => '4-Week Streak',
    AchievementType.streak8        => '8-Week Streak',
    AchievementType.streak16       => '16-Week Streak',
    AchievementType.tierBronze     => 'Bronze Member',
    AchievementType.tierSilver     => 'Silver Member',
    AchievementType.tierGold       => 'Gold Member',
    AchievementType.tierPlatinum   => 'Platinum Member',
    AchievementType.perfectMonth   => 'Perfect Month',
    AchievementType.anniversary1yr => '1-Year Anniversary',
    AchievementType.anniversary2yr => '2-Year Anniversary',
  };

  String get emoji => switch (achievementType) {
    AchievementType.streak4        => '🔥',
    AchievementType.streak8        => '🔥🔥',
    AchievementType.streak16       => '🔥🔥🔥',
    AchievementType.tierBronze     => '🥉',
    AchievementType.tierSilver     => '🥈',
    AchievementType.tierGold       => '🥇',
    AchievementType.tierPlatinum   => '💎',
    AchievementType.perfectMonth   => '⭐',
    AchievementType.anniversary1yr => '🎖️',
    AchievementType.anniversary2yr => '🏆',
  };
}
