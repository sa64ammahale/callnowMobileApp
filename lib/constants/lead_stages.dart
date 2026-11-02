import 'package:flutter/material.dart';

class LeadStageHelper {
  static const Map<String, Map<String, dynamic>> stages = {
    'LEAD': {
      'label': 'Qualification',
      'shortLabel': 'Lead',
      'color': Color(0xFF5E6AD2),
      'icon': Icons.person_outline,
      'step': 1,
      'description': 'Fresh enquiry, qualification in progress',
    },
    'FOLLOWUP': {
      'label': 'Follow-up',
      'shortLabel': 'Follow-up',
      'color': Color(0xFF0EA5E9),
      'icon': Icons.update,
      'step': 2,
      'description': 'Customer requested call back or document collection',
    },
    'INTERNAL_UNDERWRITING': {
      'label': 'Underwriting',
      'shortLabel': 'Internal UW',
      'color': Color(0xFF8B8FA3),
      'icon': Icons.fact_check_outlined,
      'step': 3,
      'description': 'Documents collected; eligibility and CIBIL check',
    },
    'LOGIN': {
      'label': 'Bank Login',
      'shortLabel': 'Login',
      'color': Color(0xFFF59E0B),
      'icon': Icons.login,
      'step': 4,
      'description': 'Application logged in partner bank portal',
    },
    'BANK_UNDERWRITING': {
      'label': 'Bank UW',
      'shortLabel': 'Bank UW',
      'color': Color(0xFF7C3AED),
      'icon': Icons.account_balance,
      'step': 5,
      'description': 'Bank credit review and verification',
    },
    'SANCTIONED': {
      'label': 'Sanctioned',
      'shortLabel': 'Sanctioned',
      'color': Color(0xFF10B981),
      'icon': Icons.verified_outlined,
      'step': 6,
      'description': 'Loan approved by bank; sanction letter issued',
    },
    'DISBURSED': {
      'label': 'Disbursed',
      'shortLabel': 'Disbursed',
      'color': Color(0xFF059669),
      'icon': Icons.payments_outlined,
      'step': 7,
      'description': 'Loan disbursed into client bank account',
    },
    'REJECT': {
      'label': 'Rejected',
      'shortLabel': 'Rejected',
      'color': Color(0xFFEF4444),
      'icon': Icons.cancel_outlined,
      'step': 0,
      'description': 'Application rejected or client declined',
    },
  };

  static const List<String> stageKeys = [
    'LEAD',
    'FOLLOWUP',
    'INTERNAL_UNDERWRITING',
    'LOGIN',
    'BANK_UNDERWRITING',
    'SANCTIONED',
    'DISBURSED',
    'REJECT',
  ];

  static const List<String> loanTypes = [
    'Personal Loan',
    'Home Loan',
    'Business Loan',
    'Car Loan',
    'Loan Against Property (LAP)',
    'Balance Transfer',
    'Credit Card',
    'Working Capital Loan',
    'Professional Loan',
    'Education Loan',
  ];

  static const List<String> partnerBanks = [
    'HDFC Bank',
    'State Bank of India (SBI)',
    'ICICI Bank',
    'Axis Bank',
    'Kotak Mahindra Bank',
    'Punjab National Bank (PNB)',
    'Bank of Baroda',
    'IndusInd Bank',
    'IDFC FIRST Bank',
    'Yes Bank',
    'Federal Bank',
    'AU Small Finance Bank',
    'Bajaj Finserv',
    'Tata Capital',
  ];

  static const List<String> temperatures = [
    'Hot',
    'Warm',
    'Cold',
  ];

  static const List<String> priorities = [
    'High',
    'Medium',
    'Low',
  ];

  static Color getColor(String? status) {
    if (status == null) return const Color(0xFF64748B);
    final normalized = status.toUpperCase().replaceAll(' ', '_');
    return stages[normalized]?['color'] as Color? ?? const Color(0xFF64748B);
  }

  static String getLabel(String? status) {
    if (status == null || status.isEmpty) return 'Qualification';
    final normalized = status.toUpperCase().replaceAll(' ', '_');
    return stages[normalized]?['label'] as String? ?? status;
  }

  static String getShortLabel(String? status) {
    if (status == null || status.isEmpty) return 'Lead';
    final normalized = status.toUpperCase().replaceAll(' ', '_');
    return stages[normalized]?['shortLabel'] as String? ?? status;
  }

  static IconData getIcon(String? status) {
    if (status == null) return Icons.circle_outlined;
    final normalized = status.toUpperCase().replaceAll(' ', '_');
    return stages[normalized]?['icon'] as IconData? ?? Icons.circle_outlined;
  }

  static int getStep(String? status) {
    if (status == null) return 1;
    final normalized = status.toUpperCase().replaceAll(' ', '_');
    return stages[normalized]?['step'] as int? ?? 1;
  }

  static Color getTemperatureColor(String? temp) {
    switch (temp?.toLowerCase()) {
      case 'hot':
        return const Color(0xFFDC2626);
      case 'warm':
        return const Color(0xFFD97706);
      case 'cold':
        return const Color(0xFF2563EB);
      default:
        return const Color(0xFF64748B);
    }
  }

  static Color getPriorityColor(String? prio) {
    switch (prio?.toLowerCase()) {
      case 'high':
        return const Color(0xFFDC2626);
      case 'medium':
        return const Color(0xFFD97706);
      case 'low':
        return const Color(0xFF16A34A);
      default:
        return const Color(0xFF64748B);
    }
  }
}

