import 'package:callnow_new/constants/lead_stages.dart';

class CrmLead {
  final int id;
  final int? custId;
  final String name;
  final String mobile;
  final String company;
  final String package;
  final String loanType;
  final String status; // 'LEAD', 'FOLLOWUP', 'INTERNAL_UNDERWRITING', 'LOGIN', etc.
  final String stage; // 'Hot', 'Warm', 'Cold'
  final String priority; // 'High', 'Medium', 'Low'
  final String? loginBank;
  final String? nextFollowup;
  final String otherInfo;
  final String assignedUser;
  final String? source;
  final String? uploadTime;
  final int callCount;

  CrmLead({
    required this.id,
    this.custId,
    required this.name,
    required this.mobile,
    required this.company,
    required this.package,
    this.loanType = 'Personal Loan',
    required this.status,
    this.stage = 'Warm',
    this.priority = 'Medium',
    this.loginBank,
    this.nextFollowup,
    required this.otherInfo,
    required this.assignedUser,
    this.source,
    this.uploadTime,
    this.callCount = 0,
  });

  String get cleanMobile => mobile.replaceAll(RegExp(r'\D'), '');

  int get stepNumber => LeadStageHelper.getStep(status);

  bool get isRejected => status.toUpperCase() == 'REJECT';

  String get formattedPackage {
    if (package.isEmpty) return 'Loan Amount Unspecified';
    final cleaned = package.replaceAll(RegExp(r'[^\d.]'), '');
    final numVal = double.tryParse(cleaned);
    if (numVal != null && numVal > 0) {
      if (numVal >= 10000000) {
        return '₹${(numVal / 10000000).toStringAsFixed(2)} Cr';
      } else if (numVal >= 100000) {
        return '₹${(numVal / 100000).toStringAsFixed(2)} Lakh';
      }
      return '₹${numVal.toInt()}';
    }
    return package.startsWith('₹') ? package : '₹$package';
  }

  factory CrmLead.fromJson(Map<String, dynamic> json) {
    String rawStatus = (json['status'] ?? json['lead_status_new'] ?? json['last_status'] ?? 'LEAD')
        .toString()
        .trim();
    // Normalize status strings like 'Not Called' to 'LEAD'
    if (rawStatus.toLowerCase() == 'not called' || rawStatus.isEmpty) {
      rawStatus = 'LEAD';
    } else if (rawStatus.toLowerCase() == 'called' || rawStatus.toLowerCase() == 'follow-up') {
      rawStatus = 'FOLLOWUP';
    }

    return CrmLead(
      id: int.tryParse(json['lead_id']?.toString() ?? json['id']?.toString() ?? json['record_id']?.toString() ?? '0') ?? 0,
      custId: int.tryParse(json['cust_id']?.toString() ?? '0'),
      name: (json['name'] ?? json['customer_name'] ?? 'Unnamed Lead').toString().trim(),
      mobile: (json['mobile'] ?? json['customer_mobile'] ?? '').toString().trim(),
      company: (json['company'] ?? json['customer_company'] ?? '').toString().trim(),
      package: (json['package'] ?? json['loan_amount'] ?? '').toString().trim(),
      loanType: (json['loan_type'] ?? 'Personal Loan').toString().trim(),
      status: rawStatus.toUpperCase().replaceAll(' ', '_'),
      stage: (json['lead_stage'] ?? json['stage'] ?? 'Warm').toString().trim(),
      priority: (json['priority'] ?? 'Medium').toString().trim(),
      loginBank: json['login_bank_name']?.toString() ?? json['login_bank']?.toString(),
      nextFollowup: json['next_followup_at']?.toString() ?? json['next_followup']?.toString(),
      otherInfo: (json['other_info'] ?? json['remarks'] ?? '').toString().trim(),
      assignedUser: (json['assigned_user'] ?? 'Gunjan Vishwakarma').toString().trim(),
      source: json['source']?.toString(),
      uploadTime: json['upload_time']?.toString() ?? json['created_at']?.toString(),
      callCount: int.tryParse(json['call_count']?.toString() ?? '0') ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'cust_id': custId,
      'name': name,
      'mobile': mobile,
      'company': company,
      'package': package,
      'loan_type': loanType,
      'status': status,
      'lead_stage': stage,
      'priority': priority,
      'login_bank_name': loginBank,
      'next_followup_at': nextFollowup,
      'other_info': otherInfo,
      'assigned_user': assignedUser,
      'source': source,
      'upload_time': uploadTime,
      'call_count': callCount,
    };
  }

  CrmLead copyWith({
    int? id,
    int? custId,
    String? name,
    String? mobile,
    String? company,
    String? package,
    String? loanType,
    String? status,
    String? stage,
    String? priority,
    String? loginBank,
    String? nextFollowup,
    String? otherInfo,
    String? assignedUser,
    String? source,
    String? uploadTime,
    int? callCount,
  }) {
    return CrmLead(
      id: id ?? this.id,
      custId: custId ?? this.custId,
      name: name ?? this.name,
      mobile: mobile ?? this.mobile,
      company: company ?? this.company,
      package: package ?? this.package,
      loanType: loanType ?? this.loanType,
      status: status ?? this.status,
      stage: stage ?? this.stage,
      priority: priority ?? this.priority,
      loginBank: loginBank ?? this.loginBank,
      nextFollowup: nextFollowup ?? this.nextFollowup,
      otherInfo: otherInfo ?? this.otherInfo,
      assignedUser: assignedUser ?? this.assignedUser,
      source: source ?? this.source,
      uploadTime: uploadTime ?? this.uploadTime,
      callCount: callCount ?? this.callCount,
    );
  }
}

