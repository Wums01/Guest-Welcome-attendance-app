class FollowUpAction {
  const FollowUpAction({
    required this.id,
    required this.memberId,
    required this.action,
    required this.createdByStaffId,
    required this.createdAt,
    this.note,
  });

  final String id;
  final String memberId;
  final String action;
  final String createdByStaffId;
  final DateTime createdAt;
  final String? note;

  factory FollowUpAction.fromJson(Map<String, dynamic> json) {
    return FollowUpAction(
      id: json['id'] as String,
      memberId: json['member_id'] as String,
      action: json['action'] as String,
      createdByStaffId: json['created_by_staff_id'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      note: json['note'] as String?,
    );
  }
}
