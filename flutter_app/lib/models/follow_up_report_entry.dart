class FollowUpReportEntry {
  const FollowUpReportEntry({
    required this.id,
    required this.memberId,
    required this.memberName,
    required this.actionType,
    required this.createdAt,
    required this.createdByName,
    this.scheduledFollowUpAt,
    this.note,
    this.outcomeNote,
  });

  final String id;
  final String memberId;
  final String memberName;
  final String actionType;
  final DateTime createdAt;
  final String createdByName;
  final DateTime? scheduledFollowUpAt;
  final String? note;
  final String? outcomeNote;

  bool get isScheduled => scheduledFollowUpAt != null;

  factory FollowUpReportEntry.fromJson(Map<String, dynamic> json) {
    final member = _map(json['members']);
    final staff = _map(json['staff_users']);
    final createdAt = DateTime.tryParse(_string(json['created_at'])) ??
        DateTime.fromMillisecondsSinceEpoch(0);

    return FollowUpReportEntry(
      id: _string(json['id'], fallback: 'unknown'),
      memberId: _string(json['member_id'], fallback: 'unknown'),
      memberName: _string(member?['full_name'], fallback: 'Unknown Member'),
      actionType: _string(json['action_type'], fallback: 'contacted'),
      createdAt: createdAt,
      createdByName: _string(staff?['full_name'], fallback: 'Unknown Staff'),
      scheduledFollowUpAt: json['scheduled_follow_up_at'] == null
          ? null
          : DateTime.tryParse(_string(json['scheduled_follow_up_at'])),
      note: _nullableString(json['note']),
      outcomeNote: _nullableString(json['outcome_note']),
    );
  }

  static String _string(dynamic value, {String fallback = ''}) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? fallback : text;
  }

  static String? _nullableString(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static Map<String, dynamic>? _map(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is List && value.isNotEmpty) {
      return _map(value.first);
    }
    return null;
  }
}
