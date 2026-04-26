import 'package:attendance_app/models/follow_up_action.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FollowUpAction.fromJson', () {
    test('parses action_type and new optional fields', () {
      final json = {
        'id': 'fa-001',
        'member_id': 'mem-001',
        'action_type': 'not_reachable',
        'created_by_staff_id': 'staff-001',
        'created_at': '2026-04-10T10:00:00.000Z',
        'note': 'Called twice',
        'scheduled_follow_up_at': '2026-04-17T10:00:00.000Z',
        'outcome_note': 'Will try again next week',
      };
      final fa = FollowUpAction.fromJson(json);
      expect(fa.actionType, 'not_reachable');
      expect(fa.scheduledFollowUpAt,
          DateTime.parse('2026-04-17T10:00:00.000Z'));
      expect(fa.outcomeNote, 'Will try again next week');
    });

    test('nullable fields default to null', () {
      final json = {
        'id': 'fa-002',
        'member_id': 'mem-001',
        'action_type': 'contacted',
        'created_by_staff_id': 'staff-001',
        'created_at': '2026-04-10T10:00:00.000Z',
        'note': null,
        'scheduled_follow_up_at': null,
        'outcome_note': null,
      };
      final fa = FollowUpAction.fromJson(json);
      expect(fa.scheduledFollowUpAt, isNull);
      expect(fa.outcomeNote, isNull);
    });
  });
}
