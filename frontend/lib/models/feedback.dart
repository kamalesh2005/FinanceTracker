class FeedbackItem {
  final int id;
  final int userId;
  final String screenName;
  final String message;
  final String status;
  final String adminResponse;
  final DateTime? respondedAt;
  final int? respondedBy;
  final DateTime createdAt;
  final String? username;

  const FeedbackItem({
    required this.id,
    required this.userId,
    required this.screenName,
    required this.message,
    required this.status,
    required this.adminResponse,
    this.respondedAt,
    this.respondedBy,
    required this.createdAt,
    this.username,
  });

  bool get isOpen => status == 'open';
  bool get hasResponse => adminResponse.trim().isNotEmpty;

  factory FeedbackItem.fromJson(Map<String, dynamic> json) {
    return FeedbackItem(
      id: (json['id'] as num).toInt(),
      userId: (json['user_id'] as num).toInt(),
      screenName: json['screen_name'] as String? ?? '',
      message: json['message'] as String? ?? '',
      status: json['status'] as String? ?? 'open',
      adminResponse: json['admin_response'] as String? ?? '',
      respondedAt: _parseDate(json['responded_at']),
      respondedBy: (json['responded_by'] as num?)?.toInt(),
      createdAt: _parseDate(json['created_at']) ?? DateTime.now(),
      username: json['username'] as String?,
    );
  }

  static DateTime? _parseDate(dynamic raw) {
    if (raw == null) return null;
    if (raw is String && raw.isNotEmpty) {
      return DateTime.tryParse(raw);
    }
    return null;
  }
}

class FeedbackPage {
  final List<FeedbackItem> items;
  final int total;
  final int page;
  final int pageSize;

  const FeedbackPage({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  int get totalPages {
    if (total == 0) return 1;
    return ((total - 1) ~/ pageSize) + 1;
  }
}
