// lib/models/follow_up_action.dart

class FollowUpAction {
  const FollowUpAction({
    required this.id,
    required this.memberId,
    required this.actionType,
    required this.createdByStaffId,
    required this.createdAt,
    this.note,
    this.scheduledFollowUpAt,
    this.outcomeNote,
  });

  final String id;
  final String memberId;
  final String actionType;
  final String createdByStaffId;
  final DateTime createdAt;
  final String? note;
  final DateTime? scheduledFollowUpAt;
  final String? outcomeNote;

  factory FollowUpAction.fromJson(Map<String, dynamic> json) {
    return FollowUpAction(
      id: json['id'] as String,
      memberId: json['member_id'] as String,
      actionType: json['action_type'] as String,
      createdByStaffId: json['created_by_staff_id'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      note: json['note'] as String?,
      scheduledFollowUpAt: json['scheduled_follow_up_at'] == null
          ? null
          : DateTime.parse(json['scheduled_follow_up_at'] as String),
      outcomeNote: json['outcome_note'] as String?,
    );
  }
}
