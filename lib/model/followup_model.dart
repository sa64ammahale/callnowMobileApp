class FollowupModel {
  final String id;
  final int? serverId;
  final int? leadId;
  final int? clientContactId;
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
    this.serverId,
    this.leadId,
    this.clientContactId,
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
      'server_id': serverId,
      'lead_id': leadId,
      'client_contact_id': clientContactId,
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

    final rawServerId = json['server_id'] ?? (json['id'] is int ? json['id'] : int.tryParse(json['id']?.toString() ?? ''));
    final int? sId = rawServerId is int ? rawServerId : null;

    final rawStatus = (json['status']?.toString() ?? 'pending').toUpperCase();
    String normalizedStatus;
    if (rawStatus == 'OPEN' || rawStatus == 'PENDING') {
      normalizedStatus = 'pending';
    } else if (rawStatus == 'DONE' || rawStatus == 'COMPLETED') {
      normalizedStatus = 'completed';
    } else if (rawStatus == 'SNOOZED') {
      normalizedStatus = 'snoozed';
    } else if (rawStatus == 'CANCELLED') {
      normalizedStatus = 'cancelled';
    } else {
      normalizedStatus = json['status']?.toString().toLowerCase() ?? 'pending';
    }

    final rawId = json['id']?.toString() ?? '';
    final String localId = rawId.isNotEmpty && !rawId.contains(RegExp(r'^\d+$'))
        ? rawId
        : (sId != null ? 'srv_$sId' : 'f_${DateTime.now().millisecondsSinceEpoch}');

    return FollowupModel(
      id: localId,
      serverId: sId,
      leadId: json['lead_id'] is int
          ? json['lead_id'] as int
          : int.tryParse(json['lead_id']?.toString() ?? ''),
      clientContactId: json['client_contact_id'] is int
          ? json['client_contact_id'] as int
          : int.tryParse(json['client_contact_id']?.toString() ?? ''),
      customerName: json['customer_name']?.toString() ?? json['name']?.toString() ?? 'Unknown Customer',
      phoneNumber: json['phone_number']?.toString() ?? json['customer_mobile']?.toString() ?? json['mobile']?.toString() ?? '',
      company: json['company']?.toString() ?? json['company_name']?.toString(),
      scheduledTime: parseDate(json['scheduled_time']) ?? parseDate(json['followup_at']) ?? DateTime.now(),
      createdAt: parseDate(json['created_at']) ?? DateTime.now(),
      notes: json['notes']?.toString() ?? json['note']?.toString() ?? '',
      status: normalizedStatus,
      completedAt: parseDate(json['completed_at']),
      source: json['source']?.toString() ?? json['contact_source']?.toString(),
    );
  }

  FollowupModel copyWith({
    String? id,
    int? serverId,
    int? leadId,
    int? clientContactId,
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
      serverId: serverId ?? this.serverId,
      leadId: leadId ?? this.leadId,
      clientContactId: clientContactId ?? this.clientContactId,
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
