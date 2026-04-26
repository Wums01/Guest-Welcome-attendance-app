import 'package:attendance_app/models/leaderboard_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LeaderboardEntry.fromJson', () {
    final json = {
      'year_month': '2026-04',
      'member_id': 'abc-123',
      'full_name': 'Ada Lovelace',
      'team': 'Team A',
      'offline_code': 'OFF1',
      'present_count': 8,
      'total_points': 8,
    };

    test('parses totalPoints from total_points', () {
      final entry = LeaderboardEntry.fromJson(json, rank: 1);
      expect(entry.totalPoints, 8);
    });

    test('rank is assigned from parameter', () {
      final entry = LeaderboardEntry.fromJson(json, rank: 3);
      expect(entry.rank, 3);
    });

    test('falls back to present_count when total_points is null', () {
      final noPoints = Map<String, dynamic>.from(json)
        ..remove('total_points');
      final entry = LeaderboardEntry.fromJson(noPoints, rank: 1);
      expect(entry.totalPoints, 8);
    });
  });
}
