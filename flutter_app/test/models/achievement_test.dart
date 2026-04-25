import 'package:attendance_app/models/achievement.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Achievement.fromJson', () {
    test('parses all required fields', () {
      final json = {
        'id': 'ach-001',
        'member_id': 'mem-001',
        'achievement_type': 'tier_bronze',
        'achieved_at': '2026-04-01T00:00:00.000Z',
        'metadata': null,
      };
      final a = Achievement.fromJson(json);
      expect(a.id, 'ach-001');
      expect(a.memberId, 'mem-001');
      expect(a.achievementType, AchievementType.tierBronze);
      expect(a.achievedAt, DateTime.parse('2026-04-01T00:00:00.000Z'));
      expect(a.metadata, isNull);
    });

    test('parses metadata when present', () {
      final json = {
        'id': 'ach-002',
        'member_id': 'mem-001',
        'achievement_type': 'perfect_month',
        'achieved_at': '2026-04-01T00:00:00.000Z',
        'metadata': {'year_month': '2026-03'},
      };
      final a = Achievement.fromJson(json);
      expect(a.achievementType, AchievementType.perfectMonth);
      expect(a.metadata?['year_month'], '2026-03');
    });

    test('label returns human-readable string', () {
      final json = {
        'id': 'x',
        'member_id': 'x',
        'achievement_type': 'streak_4',
        'achieved_at': '2026-01-01T00:00:00Z',
        'metadata': null,
      };
      expect(Achievement.fromJson(json).label, '4-Week Streak');
    });
  });
}
