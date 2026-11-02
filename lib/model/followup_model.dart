class FollowupModel {
  final String id;
  final int? leadId;
  final String customerName;
  final String phoneNumber;
  final String? company;
  final DateTime scheduledTime;
  final DateTime createdAt;
  final String notes;
  final String status; // 'pending', 'snoozed', 'completed', 'cancelled'
  final DateTime? completedAt;
  final String? source;

  FollowupModel({
    required this.id,
    this.leadId,
    required this.customerName,
    required this.phoneNumber,
    this.company,
    required this.scheduledTime,
    required this.createdAt,
    this.notes = '',
    this.status = 'pending',
    this.completedAt,
    this.source,
  });

  bool get isOverdue =>
      status == 'pending' && DateTime.now().isAfter(scheduledTime);

  bool get isDueNow {
    if (status != 'pending' && status != 'snoozed') return false;
    final diffMinutes = DateTime.now().difference(scheduledTime).inMinutes;
    return diffMinutes >= -2 && diffMinutes <= 15;
  }

  bool get isToday {
    final now = DateTime.now();
    return scheduledTime.year == now.year &&
        scheduledTime.month == now.month &&
        scheduledTime.day == now.day;
  }

  String get timeRemainingText {
    final now = DateTime.now();
    final difference = scheduledTime.difference(now);

    if (difference.isNegative) {
      final passedMinutes = difference.inMinutes.abs();
      if (passedMinutes < 60) {
        return '$passedMinutes mins overdue';
      } else {
        final hours = passedMinutes ~/ 60;
        return '$hours hrs overdue';
      }
    } else {
      final inMinutes = difference.inMinutes;
      if (inMinutes < 60) {
        return 'in $inMinutes mins';
      } else if (inMinutes < 1440) {
        final hours = inMinutes ~/ 60;
        return 'in $hours hrs';
      } else {
        final days = inMinutes ~/ 1440;
        return 'in $days days';
      }
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'lead_id': leadId,
      'customer_name': customerName,
      'phone_number': phoneNumber,
      'company': company,
      'scheduled_time': scheduledTime.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'notes': notes,
      'status': status,
      'completed_at': completedAt?.toIso8601String(),
      'source': source,
    };
  }

  factory FollowupModel.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic val) {
      if (val == null) return null;
      return DateTime.tryParse(val.toString());
    }

    return FollowupModel(
      id: (json['id'] ?? 'f_${DateTime.now().millisecondsSinceEpoch}').toString(),
      leadId: json['lead_id'] is int
          ? json['lead_id'] as int
          : int.tryParse(json['lead_id']?.toString() ?? ''),
      customerName: json['customer_name']?.toString() ?? 'Unknown Customer',
      phoneNumber: json['phone_number']?.toString() ?? '',
      company: json['company']?.toString(),
      scheduledTime: parseDate(json['scheduled_time']) ?? DateTime.now(),
      createdAt: parseDate(json['created_at']) ?? DateTime.now(),
      notes: json['notes']?.toString() ?? '',
      status: json['status']?.toString() ?? 'pending',
      completedAt: parseDate(json['completed_at']),
      source: json['source']?.toString(),
    );
  }

  FollowupModel copyWith({
    String? id,
    int? leadId,
    String? customerName,
    String? phoneNumber,
    String? company,
    DateTime? scheduledTime,
    DateTime? createdAt,
    String? notes,
    String? status,
    DateTime? completedAt,
    String? source,
  }) {
    return FollowupModel(
      id: id ?? this.id,
      leadId: leadId ?? this.leadId,
      customerName: customerName ?? this.customerName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      company: company ?? this.company,
      scheduledTime: scheduledTime ?? this.scheduledTime,
      createdAt: createdAt ?? this.createdAt,
      notes: notes ?? this.notes,
      status: status ?? this.status,
      completedAt: completedAt ?? this.completedAt,
      source: source ?? this.source,
    );
  }
}

