import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:callnow_new/constants/lead_stages.dart';
import 'package:callnow_new/model/crm_lead.dart';
import 'package:callnow_new/services/api_service.dart';
import 'package:callnow_new/services/call_tracking_service.dart';
import 'package:callnow_new/services/followup_service.dart';
import 'package:callnow_new/services/config_service.dart';

class LeadsScreen extends StatefulWidget {
  final VoidCallback? onOpenCallingDesk;
  final Function(Map<String, dynamic> lead)? onLeadCallRequested;

  const LeadsScreen({
    super.key,
    this.onOpenCallingDesk,
    this.onLeadCallRequested,
  });

  @override
  State<LeadsScreen> createState() => _LeadsScreenState();
}

class _LeadsScreenState extends State<LeadsScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<CrmLead> _allLeads = [];
  List<CrmLead> _filteredLeads = [];
  bool _isLoading = true;
  String? _errorMessage;
  String _activeStageFilter = 'ALL'; // 'ALL' or stageKey ('LEAD', 'LOGIN', etc.)
  int _currentPage = 1;
  int _totalLeadsCount = 0;
  int _totalPages = 1;
  bool _hasMoreLeads = false;
  bool _isLoadingMoreLeads = false;

  // Date filtering state - defaults to 'month' (Current Month leads on priority)
  String _selectedPeriod = 'month';
  DateTimeRange? _customDateRange;

  final List<Map<String, String>> _periodOptions = [
    {'id': 'month', 'label': 'This Month'},
    {'id': 'today', 'label': 'Today'},
    {'id': 'yesterday', 'label': 'Yesterday'},
    {'id': 'week', 'label': 'This Week'},
    {'id': 'last_month', 'label': 'Last Month'},
    {'id': 'custom', 'label': 'Custom Range'},
    {'id': 'all', 'label': 'All Time'},
  ];

  String get _currentPeriodLabel {
    if (_selectedPeriod == 'custom' && _customDateRange != null) {
      final start = '${_customDateRange!.start.day}/${_customDateRange!.start.month}';
      final end = '${_customDateRange!.end.day}/${_customDateRange!.end.month}';
      return '$start - $end';
    }
    final match = _periodOptions.firstWhere(
      (p) => p['id'] == _selectedPeriod,
      orElse: () => {'id': _selectedPeriod, 'label': 'This Month'},
    );
    return match['label'] ?? 'This Month';
  }

  (String?, String?, String?) _computeDateParams() {
    String? dateFrom;
    String? dateTo;
    String? periodParam = _selectedPeriod;

    if (_selectedPeriod == 'custom' && _customDateRange != null) {
      dateFrom = _customDateRange!.start.toIso8601String().substring(0, 10);
      dateTo = _customDateRange!.end.toIso8601String().substring(0, 10);
      periodParam = null;
    } else if (_selectedPeriod == 'last_month') {
      final now = DateTime.now();
      final firstDayLastMonth = DateTime(now.year, now.month - 1, 1);
      final lastDayLastMonth = DateTime(now.year, now.month, 0);
      dateFrom = firstDayLastMonth.toIso8601String().substring(0, 10);
      dateTo = lastDayLastMonth.toIso8601String().substring(0, 10);
      periodParam = null;
    } else if (_selectedPeriod == 'month') {
      periodParam = 'month';
      final now = DateTime.now();
      final firstDayThisMonth = DateTime(now.year, now.month, 1);
      dateFrom = firstDayThisMonth.toIso8601String().substring(0, 10);
    } else if (_selectedPeriod == 'all') {
      periodParam = null;
    }

    return (periodParam, dateFrom, dateTo);
  }

  @override
  void initState() {
    super.initState();
    _fetchLeads();
    _searchController.addListener(_applyFilters);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchLeads() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final (periodParam, dateFrom, dateTo) = _computeDateParams();
      final res = await ApiService.getCreatedLeads(
        page: 1,
        limit: 20,
        source: 'all',
        period: periodParam,
        dateFrom: dateFrom,
        dateTo: dateTo,
        scope: 'mine',
      );
      debugPrint('[LeadsScreen] getCreatedLeads RAW RESPONSE: $res');
      final raw = res['leads'];
      final pagObj = res['pagination'];
      final total = (pagObj is Map ? pagObj['total'] : null) ?? (raw is List ? raw.length : 0);
      final totalPages = (pagObj is Map ? pagObj['total_pages'] : null) ?? 1;

      List<CrmLead> list = [];
      if (raw is List) {
        list = raw
            .whereType<Map>()
            .map((e) => CrmLead.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }

      if (mounted) {
        setState(() {
          _allLeads = list;
          _currentPage = 1;
          _totalLeadsCount = (total as num).toInt();
          _totalPages = (totalPages as num).toInt();
          _hasMoreLeads = _currentPage < _totalPages;
          _isLoading = false;
        });
        _applyFilters();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  Future<void> _loadMoreLeads() async {
    if (_isLoadingMoreLeads || !_hasMoreLeads) return;
    setState(() => _isLoadingMoreLeads = true);

    try {
      final nextPage = _currentPage + 1;
      final (periodParam, dateFrom, dateTo) = _computeDateParams();
      final res = await ApiService.getCreatedLeads(
        page: nextPage,
        limit: 30,
        source: 'all',
        period: periodParam,
        dateFrom: dateFrom,
        dateTo: dateTo,
        scope: 'mine',
      );
      final raw = res['leads'];
      final pagObj = res['pagination'];
      final total = (pagObj is Map ? pagObj['total'] : null) ?? _totalLeadsCount;
      final totalPages = (pagObj is Map ? pagObj['total_pages'] : null) ?? _totalPages;

      List<CrmLead> list = [];
      if (raw is List) {
        list = raw
            .whereType<Map>()
            .map((e) => CrmLead.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }

      if (mounted) {
        setState(() {
          _allLeads.addAll(list);
          _currentPage = nextPage;
          _totalLeadsCount = (total as num).toInt();
          _totalPages = (totalPages as num).toInt();
          _hasMoreLeads = _currentPage < _totalPages;
          _isLoadingMoreLeads = false;
        });
        _applyFilters();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingMoreLeads = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load more leads: $e')),
        );
      }
    }
  }

  void _applyFilters() {
    final query = _searchController.text.trim().toLowerCase();
    final currentUserId = ConfigService.userProfile.id;
    final isSupervisor = ConfigService.isManagementOrSupervisor;

    setState(() {
      var filtered = _allLeads.where((lead) {
        final matchesSearch = query.isEmpty ||
            lead.name.toLowerCase().contains(query) ||
            lead.mobile.contains(query) ||
            lead.company.toLowerCase().contains(query) ||
            lead.loanType.toLowerCase().contains(query) ||
            (lead.loginBank ?? '').toLowerCase().contains(query) ||
            lead.otherInfo.toLowerCase().contains(query) ||
            lead.assignedUser.toLowerCase().contains(query);

        if (!matchesSearch) return false;

        if (_activeStageFilter == 'ALL') return true;
        return lead.status == _activeStageFilter;
      }).toList();

      // For higher-level users (Super Admin, Admin, Supervisor), prioritize own leads at the top
      if (isSupervisor) {
        filtered.sort((a, b) {
          final aIsOwn = a.isOwnLead || (currentUserId > 0 && a.assignedUserId == currentUserId);
          final bIsOwn = b.isOwnLead || (currentUserId > 0 && b.assignedUserId == currentUserId);
          if (aIsOwn && !bIsOwn) return -1;
          if (!aIsOwn && bIsOwn) return 1;
          return 0; // preserve fetched chronological order
        });
      }

      _filteredLeads = filtered;
    });
  }

  int _getStageCount(String stageKey) {
    if (stageKey == 'ALL') return _allLeads.length;
    return _allLeads.where((l) => l.status == stageKey).length;
  }

  Future<void> _makeCall(CrmLead lead) async {
    final cleanPhone = lead.cleanMobile;
    try {
      await CallTrackingService.makePhoneCall(cleanPhone);
    } catch (_) {
      final uri = Uri.parse('tel:$cleanPhone');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    }
  }

  Future<void> _openWhatsApp(CrmLead lead) async {
    final cleanPhone = lead.cleanMobile;
    final msg =
        'Hello ${lead.name}, I am following up from InCredit Solutions regarding your ${lead.loanType} enquiry.';
    await CallTrackingService.openWhatsApp(cleanPhone, message: msg);
  }

  void _showAdvanceStageModal(CrmLead lead) {
    if (!ConfigService.canMoveLeadStage) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Permission Denied: Sales Officers cannot change lead status. Only Super Admin, Admin, and Supervisor can move stages.',
          ),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
      return;
    }
    String selectedStage = lead.status;
    final remarksCtrl = TextEditingController(text: lead.otherInfo);
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                top: 20,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Advance Lead Pipeline Stage',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              Text(
                                '${lead.name} • ${lead.formattedPackage}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Current Stage Pill
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: LeadStageHelper.getColor(lead.status)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: LeadStageHelper.getColor(lead.status)
                                .withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(LeadStageHelper.getIcon(lead.status),
                              color: LeadStageHelper.getColor(lead.status),
                              size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'Current Stage: ${LeadStageHelper.getLabel(lead.status)}',
                            style: TextStyle(
                              color: LeadStageHelper.getColor(lead.status),
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    const Text(
                      'Select New Stage:',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF334155),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Stage Selection Grid
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: LeadStageHelper.stageKeys.map((key) {
                        final isSelected = selectedStage == key;
                        final color = LeadStageHelper.getColor(key);
                        return ChoiceChip(
                          avatar: Icon(
                            LeadStageHelper.getIcon(key),
                            size: 16,
                            color: isSelected ? Colors.white : color,
                          ),
                          label: Text(LeadStageHelper.getLabel(key)),
                          selected: isSelected,
                          selectedColor: color,
                          backgroundColor: Colors.white,
                          side: BorderSide(
                              color: isSelected ? color : const Color(0xFFCBD5E1)),
                          labelStyle: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isSelected ? Colors.white : const Color(0xFF0F172A),
                          ),
                          onSelected: (val) {
                            if (val) {
                              setModalState(() => selectedStage = key);
                            }
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),

                    // Remarks Field
                    TextField(
                      controller: remarksCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Stage Transition Remarks / Notes',
                        border: OutlineInputBorder(),
                        isDense: true,
                        hintText: 'e.g. CIBIL score verified, file submitted to HDFC',
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Action Button
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: LeadStageHelper.getColor(selectedStage),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: isSaving
                          ? null
                          : () async {
                              setModalState(() => isSaving = true);
                              try {
                                debugPrint(
                                  '[LeadsScreen] Advancing lead: id=${lead.id}, source=${lead.source ?? "MAIN"}, newStage=$selectedStage, remarks=${remarksCtrl.text.trim()}',
                                );
                                await ApiService.updateLeadStage(
                                  id: lead.id,
                                  source: lead.source ?? 'MAIN',
                                  newStage: selectedStage,
                                  remarks: remarksCtrl.text.trim(),
                                );

                                if (ctx.mounted) Navigator.pop(ctx);
                                await _fetchLeads();

                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Stage updated to ${LeadStageHelper.getLabel(selectedStage)}!',
                                      ),
                                      backgroundColor:
                                          LeadStageHelper.getColor(selectedStage),
                                    ),
                                  );
                                }
                              } catch (e) {
                                setModalState(() => isSaving = false);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(e.toString()),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              }
                            },
                      child: isSaving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              'Advance to ${LeadStageHelper.getLabel(selectedStage)}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showScheduleFollowupModal(CrmLead lead) {
    DateTime scheduledTime = DateTime.now().add(const Duration(hours: 2));
    final notesCtrl = TextEditingController(
      text: 'Callback regarding ${lead.loanType}',
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                top: 20,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Schedule Follow-up: ${lead.name}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Follow-up Reason',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Quick Preset Chips
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ActionChip(
                            label: const Text('+30m'),
                            onPressed: () => setModalState(() {
                              scheduledTime =
                                  DateTime.now().add(const Duration(minutes: 30));
                            }),
                          ),
                          const SizedBox(width: 6),
                          ActionChip(
                            label: const Text('+1 Hour'),
                            onPressed: () => setModalState(() {
                              scheduledTime =
                                  DateTime.now().add(const Duration(hours: 1));
                            }),
                          ),
                          const SizedBox(width: 6),
                          ActionChip(
                            label: const Text('+2 Hours'),
                            onPressed: () => setModalState(() {
                              scheduledTime =
                                  DateTime.now().add(const Duration(hours: 2));
                            }),
                          ),
                          const SizedBox(width: 6),
                          ActionChip(
                            label: const Text('Tomorrow 10 AM'),
                            onPressed: () => setModalState(() {
                              final tom =
                                  DateTime.now().add(const Duration(days: 1));
                              scheduledTime =
                                  DateTime(tom.year, tom.month, tom.day, 10, 0);
                            }),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Pick Custom Date/Time
                    InkWell(
                      onTap: () async {
                        final now = DateTime.now();
                        final d = await showDatePicker(
                          context: context,
                          initialDate: scheduledTime,
                          firstDate: now,
                          lastDate: now.add(const Duration(days: 90)),
                        );
                        if (d != null && context.mounted) {
                          final t = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.fromDateTime(scheduledTime),
                          );
                          if (t != null) {
                            setModalState(() {
                              scheduledTime = DateTime(
                                  d.year, d.month, d.day, t.hour, t.minute);
                            });
                          }
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '⏰ ${scheduledTime.day}/${scheduledTime.month}/${scheduledTime.year} at ${scheduledTime.hour.toString().padLeft(2, '0')}:${scheduledTime.minute.toString().padLeft(2, '0')}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1E293B)),
                            ),
                            const Text(
                              'Custom Time',
                              style: TextStyle(
                                  color: Color(0xFF2563EB),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () async {
                        await FollowupService.instance.addFollowup(
                          customerName: lead.name,
                          phoneNumber: lead.mobile,
                          company: lead.company,
                          scheduledTime: scheduledTime,
                          notes: notesCtrl.text.trim(),
                          leadId: lead.id,
                        );

                        if (ctx.mounted) Navigator.pop(ctx);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Follow-up scheduled with alert!'),
                              backgroundColor: Color(0xFF16A34A),
                            ),
                          );
                        }
                      },
                      child: const Text('Save & Set Reminder',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showAddLeadModal() {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController();
    final mobileCtrl = TextEditingController();
    final companyCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final salaryCtrl = TextEditingController();
    final cityCtrl = TextEditingController();
    final remarksCtrl = TextEditingController();
    final customBankCtrl = TextEditingController();

    String selectedLoanType = LeadStageHelper.loanTypes.first;
    String selectedStage = 'LEAD';
    String selectedBank = LeadStageHelper.partnerBanks.first;
    bool isCustomBank = false;
    String selectedPriority = 'Medium';
    String selectedTemp = 'Warm';
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                top: 20,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(modalCtx).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Create CRM Lead',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              Text(
                                'Synchronized with TBL_LEADS & DND protection',
                                style: TextStyle(
                                    fontSize: 12, color: Color(0xFF64748B)),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(modalCtx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Section 1: Contact Identity
                      _buildFormSectionHeader('1. Contact Identity', Icons.person_outline),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Customer Full Name *',
                          prefixIcon: Icon(Icons.badge_outlined),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'Name is required' : null,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: mobileCtrl,
                        keyboardType: TextInputType.phone,
                        maxLength: 10,
                        decoration: const InputDecoration(
                          labelText: '10-Digit Mobile Number *',
                          prefixIcon: Icon(Icons.phone_outlined),
                          prefixText: '+91 ',
                          counterText: '',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Mobile is required';
                          final clean = v.replaceAll(RegExp(r'\D'), '');
                          if (clean.length != 10) return 'Must be a 10-digit number';
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: companyCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Employer / Company',
                                prefixIcon: Icon(Icons.business_outlined),
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: cityCtrl,
                              decoration: const InputDecoration(
                                labelText: 'City / Location',
                                prefixIcon: Icon(Icons.location_on_outlined),
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Section 2: Loan & Financials
                      _buildFormSectionHeader('2. Loan & Financials', Icons.currency_rupee),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: selectedLoanType,
                        decoration: const InputDecoration(
                          labelText: 'Loan Type',
                          prefixIcon: Icon(Icons.category_outlined),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: LeadStageHelper.loanTypes.map((t) {
                          return DropdownMenuItem(value: t, child: Text(t));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) setModalState(() => selectedLoanType = val);
                        },
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: amountCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Required Loan Amount',
                                prefixText: '₹ ',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: salaryCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Net Monthly Salary',
                                prefixText: '₹ ',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Section 3: Pipeline & Sourcing
                      _buildFormSectionHeader('3. Pipeline & Sourcing', Icons.timeline),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: selectedStage,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Initial Stage',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              selectedItemBuilder: (context) {
                                return LeadStageHelper.stageKeys.map((k) {
                                  return Text(
                                    LeadStageHelper.getLabel(k),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13),
                                  );
                                }).toList();
                              },
                              items: LeadStageHelper.stageKeys.map((k) {
                                return DropdownMenuItem(
                                  value: k,
                                  child: Text(
                                    LeadStageHelper.getLabel(k),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) setModalState(() => selectedStage = val);
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: selectedBank,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Target Bank',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              selectedItemBuilder: (context) {
                                final bankList = [...LeadStageHelper.partnerBanks, LeadStageHelper.otherBankOption];
                                return bankList.map((b) {
                                  return Text(
                                    b,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13),
                                  );
                                }).toList();
                              },
                              items: [
                                ...LeadStageHelper.partnerBanks.map((b) {
                                  return DropdownMenuItem(
                                    value: b,
                                    child: Text(
                                      b,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  );
                                }),
                                const DropdownMenuItem(
                                  value: LeadStageHelper.otherBankOption,
                                  child: Text(
                                    LeadStageHelper.otherBankOption,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF2563EB),
                                    ),
                                  ),
                                ),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  setModalState(() {
                                    selectedBank = val;
                                    isCustomBank = (val == LeadStageHelper.otherBankOption);
                                  });
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      if (isCustomBank) ...[
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: customBankCtrl,
                          autofocus: true,
                          decoration: const InputDecoration(
                            labelText: 'Enter Target Bank Name *',
                            prefixIcon: Icon(Icons.account_balance_outlined),
                            hintText: 'e.g. Standard Chartered, RBL Bank, etc.',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          validator: (v) {
                            if (isCustomBank && (v == null || v.trim().isEmpty)) {
                              return 'Bank name is required';
                            }
                            return null;
                          },
                        ),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: selectedPriority,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Priority',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              items: LeadStageHelper.priorities.map((p) {
                                return DropdownMenuItem(
                                  value: p,
                                  child: Text(p, maxLines: 1, overflow: TextOverflow.ellipsis),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) setModalState(() => selectedPriority = val);
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: selectedTemp,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Temperature',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              items: LeadStageHelper.temperatures.map((t) {
                                return DropdownMenuItem(
                                  value: t,
                                  child: Text(t, maxLines: 1, overflow: TextOverflow.ellipsis),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) setModalState(() => selectedTemp = val);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: remarksCtrl,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Notes / Remarks',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Submit Button
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: isSubmitting
                            ? null
                            : () async {
                                if (!formKey.currentState!.validate()) return;
                                setModalState(() => isSubmitting = true);

                                try {
                                  final effectiveBank = isCustomBank
                                      ? customBankCtrl.text.trim()
                                      : (selectedBank == LeadStageHelper.otherBankOption ? '' : selectedBank);

                                  await ApiService.createLead(
                                    name: nameCtrl.text.trim(),
                                    mobile: mobileCtrl.text.trim(),
                                    company: companyCtrl.text.trim(),
                                    package: amountCtrl.text.trim(),
                                    otherInfo: remarksCtrl.text.trim(),
                                    status: selectedStage,
                                    loanType: selectedLoanType,
                                    stage: selectedTemp,
                                    priority: selectedPriority,
                                    loginBank: effectiveBank,
                                    source: 'MAIN',
                                  );

                                  if (modalCtx.mounted) Navigator.pop(modalCtx);
                                  await _fetchLeads();

                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Lead created & added to CRM queue!'),
                                        backgroundColor: Color(0xFF16A34A),
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  setModalState(() => isSubmitting = false);
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(e.toString()),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                }
                              },
                        child: isSubmitting
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Create & Sync Lead',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFormSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF2563EB)),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1E293B),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _fetchLeads,
        child: Column(
          children: [
            // Top Stage Filter Carousel (compact)
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    _buildStageCarouselChip(
                      key: 'ALL',
                      label: 'All Leads',
                      count: _getStageCount('ALL'),
                      icon: Icons.all_inbox_rounded,
                      color: const Color(0xFF2563EB),
                    ),
                    const SizedBox(width: 6),
                    ...LeadStageHelper.stageKeys.map((stageKey) {
                      final count = _getStageCount(stageKey);
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: _buildStageCarouselChip(
                          key: stageKey,
                          label: LeadStageHelper.getShortLabel(stageKey),
                          count: count,
                          icon: LeadStageHelper.getIcon(stageKey),
                          color: LeadStageHelper.getColor(stageKey),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),

            // Search Bar (optimized height)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
              child: SizedBox(
                height: 36,
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search leads by name, mobile, loan type, company...',
                    hintStyle: const TextStyle(fontSize: 12),
                    prefixIcon: const Icon(Icons.search, size: 16),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 15),
                            onPressed: () => _searchController.clear(),
                          )
                        : null,
                    contentPadding: EdgeInsets.zero,
                    filled: true,
                    fillColor: const Color(0xFFF1F5F9),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ),

            // Consolidated Filter Bar (Date Filter + Subordinate Officer Filter)
            _buildFilterBar(),

            // Lead List
            Expanded(
              child: _buildBody(),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddLeadModal,
        backgroundColor: const Color(0xFF2563EB),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add Lead'),
      ),
    );
  }

  Widget _buildStageCarouselChip({
    required String key,
    required String label,
    required int count,
    required IconData icon,
    required Color color,
  }) {
    final isSelected = _activeStageFilter == key;
    return InkWell(
      onTap: () {
        setState(() => _activeStageFilter = key);
        _applyFilters();
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? color : color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? color : color.withValues(alpha: 0.25),
            width: isSelected ? 1.4 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: isSelected ? Colors.white : color,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                color: isSelected ? Colors.white : const Color(0xFF1E293B),
              ),
            ),
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.25)
                    : color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterBar() {
    final isDateFiltered = _selectedPeriod != 'all';

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Row(
        children: [
          // Date Filter Pill (Kept as requested)
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _showPeriodSelectionSheet,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: isDateFiltered ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDateFiltered ? const Color(0xFF3B82F6) : const Color(0xFFE2E8F0),
                    width: isDateFiltered ? 1.2 : 1.0,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.calendar_today_outlined,
                      size: 12,
                      color: isDateFiltered ? const Color(0xFF2563EB) : const Color(0xFF64748B),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _currentPeriodLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isDateFiltered ? FontWeight.bold : FontWeight.w500,
                        color: isDateFiltered ? const Color(0xFF1D4ED8) : const Color(0xFF475569),
                      ),
                    ),
                    const SizedBox(width: 3),
                    const Icon(Icons.arrow_drop_down, size: 14, color: Color(0xFF64748B)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Right aligned status / lead counter
          Expanded(
            child: Text(
              '${_filteredLeads.length} leads',
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showPeriodSelectionSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Icon(Icons.calendar_month, color: Color(0xFF2563EB), size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Filter Leads by Date',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ..._periodOptions.map((opt) {
                final id = opt['id']!;
                final label = opt['label']!;
                final isSelected = _selectedPeriod == id;

                IconData icon;
                switch (id) {
                  case 'month':
                    icon = Icons.calendar_month_outlined;
                    break;
                  case 'today':
                    icon = Icons.today_outlined;
                    break;
                  case 'yesterday':
                    icon = Icons.history_toggle_off;
                    break;
                  case 'week':
                    icon = Icons.view_week_outlined;
                    break;
                  case 'last_month':
                    icon = Icons.history_outlined;
                    break;
                  case 'custom':
                    icon = Icons.date_range_outlined;
                    break;
                  case 'all':
                  default:
                    icon = Icons.all_inclusive;
                    break;
                }

                return ListTile(
                  dense: true,
                  visualDensity: const VisualDensity(vertical: -1),
                  leading: Icon(
                    icon,
                    size: 18,
                    color: isSelected ? const Color(0xFF2563EB) : const Color(0xFF64748B),
                  ),
                  title: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected ? const Color(0xFF2563EB) : const Color(0xFF1E293B),
                    ),
                  ),
                  trailing: isSelected
                      ? const Icon(Icons.check_circle, color: Color(0xFF2563EB), size: 18)
                      : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    if (id == 'custom') {
                      _selectCustomDateRange();
                    } else {
                      setState(() {
                        _selectedPeriod = id;
                        _customDateRange = null;
                      });
                      _fetchLeads();
                    }
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Future<void> _selectCustomDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _customDateRange ??
          DateTimeRange(
            start: DateTime(now.year, now.month, 1),
            end: now,
          ),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF2563EB),
              onPrimary: Colors.white,
              onSurface: Color(0xFF1E293B),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedPeriod = 'custom';
        _customDateRange = picked;
      });
      _fetchLeads();
    }
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red, fontSize: 14),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _fetchLeads,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    if (_filteredLeads.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.person_search_outlined,
                  size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(
                _searchController.text.isNotEmpty || _activeStageFilter != 'ALL'
                    ? 'No leads matching the selected filter/search.'
                    : 'No leads found in CRM.\nTap "+ Add Lead" to create a new client.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
      );
    }

    final showLoadMoreButton = _hasMoreLeads && !_isLoadingMoreLeads;
    final filterOrSearchActive = _activeStageFilter != 'ALL' || _searchController.text.isNotEmpty;
    final showAllLoaded = !_hasMoreLeads && _filteredLeads.isNotEmpty;
    final showFooter = _isLoadingMoreLeads || showLoadMoreButton || showAllLoaded;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 80),
      itemCount: _filteredLeads.length + (showFooter ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _filteredLeads.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12.0),
            child: Center(
              child: _isLoadingMoreLeads
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : showAllLoaded
                      ? const Text(
                          'All leads loaded',
                          style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                        )
                      : Builder(
                          builder: (context) {
                            final loadMoreBtn = OutlinedButton.icon(
                              onPressed: filterOrSearchActive ? null : _loadMoreLeads,
                              icon: const Icon(Icons.arrow_downward, size: 18),
                              label: Text(
                                'Load More Leads (${_totalLeadsCount - _allLeads.length} remaining)',
                              ),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            );
                            if (filterOrSearchActive) {
                              return Tooltip(
                                message:
                                    'Search and stage filters are applied client-side on the already-fetched batch. Clear filters to load more from the server.',
                                child: loadMoreBtn,
                              );
                            }
                            return loadMoreBtn;
                          },
                        ),
            ),
          );
        }
        final lead = _filteredLeads[index];
        return _buildLeadCard(lead);
      },
    );
  }

  Widget _buildLeadCard(CrmLead lead) {
    final stageColor = LeadStageHelper.getColor(lead.status);
    final stageLabel = LeadStageHelper.getLabel(lead.status);

    Color cardBg;
    Color cardBorder;
    Color accentColor;

    if (lead.isRework) {
      // Warning Card when Rework
      cardBg = const Color(0xFFFFFBEB);
      cardBorder = const Color(0xFFFDE68A);
      accentColor = const Color(0xFFD97706);
    } else if (lead.isRejected) {
      // Danger Card for Reject
      cardBg = const Color(0xFFFEF2F2);
      cardBorder = const Color(0xFFFECDD3);
      accentColor = const Color(0xFFDC2626);
    } else if (lead.isDisbursed) {
      // Success Card for Disbursal
      cardBg = const Color(0xFFF0FDF4);
      cardBorder = const Color(0xFFBBF7D0);
      accentColor = const Color(0xFF16A34A);
    } else if (lead.status.toUpperCase() == 'LEAD') {
      // Regular Card for Lead
      cardBg = Colors.white;
      cardBorder = const Color(0xFFE2E8F0);
      accentColor = const Color(0xFF6D45F9);
    } else if (lead.status.toUpperCase() == 'FOLLOWUP') {
      cardBg = const Color(0xFFF0F9FF);
      cardBorder = const Color(0xFFBAE6FD);
      accentColor = const Color(0xFF0284C7);
    } else if (lead.status.toUpperCase() == 'LOGIN') {
      cardBg = const Color(0xFFFFFDF0);
      cardBorder = const Color(0xFFFEF08A);
      accentColor = const Color(0xFFCA8A04);
    } else if (lead.status.toUpperCase() == 'BANK_UNDERWRITING') {
      cardBg = const Color(0xFFFAF5FF);
      cardBorder = const Color(0xFFE9D5FF);
      accentColor = const Color(0xFF9333EA);
    } else if (lead.status.toUpperCase() == 'SANCTIONED') {
      cardBg = const Color(0xFFECFDF5);
      cardBorder = const Color(0xFFA7F3D0);
      accentColor = const Color(0xFF059669);
    } else {
      cardBg = const Color(0xFFF8FAFC);
      cardBorder = const Color(0xFFCBD5E1);
      accentColor = stageColor;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorder, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: accentColor, width: 4.5),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (lead.isRework) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFF59E0B)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.warning_amber_rounded, size: 14, color: Color(0xFFB45309)),
                        SizedBox(width: 6),
                        Text(
                          'ACTION REQUIRED: REWORK',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFB45309),
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                // Top Row: Avatar + Name + Company & Status Badge
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      backgroundColor: stageColor.withValues(alpha: 0.15),
                      radius: 20,
                      child: Text(
                        lead.name.isNotEmpty ? lead.name[0].toUpperCase() : '?',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: stageColor,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            lead.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          if (lead.company.isNotEmpty)
                            Text(
                              lead.company,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF475569),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          if (ConfigService.isManagementOrSupervisor) ...[
                            const SizedBox(height: 4),
                            if (lead.isOwnLead || (ConfigService.userProfile.id > 0 && lead.assignedUserId == ConfigService.userProfile.id))
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEEF2FF),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFFC7D2FE)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (ConfigService.userAvatarImageProvider != null)
                                      Padding(
                                        padding: const EdgeInsets.only(right: 3.0),
                                        child: CircleAvatar(
                                          radius: 6,
                                          backgroundImage: ConfigService.userAvatarImageProvider,
                                        ),
                                      )
                                    else
                                      const Icon(Icons.star, size: 11, color: Color(0xFF4F46E5)),
                                    const SizedBox(width: 3),
                                    const Text(
                                      'My Lead',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF4F46E5),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                    // Status Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: stageColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: stageColor.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LeadStageHelper.getIcon(lead.status),
                              size: 13, color: stageColor),
                          const SizedBox(width: 4),
                          Text(
                            stageLabel,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: stageColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Journey Progress Stepper
                _buildJourneyStepper(lead),
                const SizedBox(height: 10),

                // Financial Pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: cardBorder),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.currency_rupee, size: 14, color: Color(0xFF16A34A)),
                      Text(
                        lead.formattedPackage,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(height: 12, width: 1, color: const Color(0xFFCBD5E1)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${lead.loanType}${lead.loginBank != null && lead.loginBank!.isNotEmpty ? " • ${lead.loginBank}" : ""}',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Secondary Metadata (Temperature, Priority, Mobile)
                Row(
                  children: [
                    // Phone
                    const Icon(Icons.phone, size: 13, color: Color(0xFF64748B)),
                    const SizedBox(width: 4),
                    Text(
                      lead.mobile,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF334155),
                      ),
                    ),
                    const Spacer(),
                    // Temperature Chip
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: LeadStageHelper.getTemperatureColor(lead.stage)
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        lead.stage == 'Hot'
                            ? '🔥 Hot'
                            : (lead.stage == 'Warm' ? '⚡ Warm' : '❄️ Cold'),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: LeadStageHelper.getTemperatureColor(lead.stage),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Priority Chip
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: LeadStageHelper.getPriorityColor(lead.priority)
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${lead.priority} Prio',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: LeadStageHelper.getPriorityColor(lead.priority),
                        ),
                      ),
                    ),
                  ],
                ),

                if (lead.otherInfo.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    '“${lead.otherInfo}”',
                    style: const TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: Color(0xFF64748B),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],

                const SizedBox(height: 10),
                Divider(height: 1, color: cardBorder),
                const SizedBox(height: 8),

                // Action Buttons Row
                Row(
                  children: [
                    // Call Now
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _makeCall(lead),
                        icon: const Icon(Icons.phone, size: 15),
                        label: const Text('Call', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF16A34A),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          elevation: 0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),

                    // WhatsApp
                    IconButton.filledTonal(
                      icon: const Icon(Icons.chat_bubble_outline, size: 15, color: Color(0xFF25D366)),
                      tooltip: 'WhatsApp',
                      onPressed: () => _openWhatsApp(lead),
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFFDCFCE7),
                        padding: const EdgeInsets.all(8),
                      ),
                    ),
                    const SizedBox(width: 6),

                    // Advance Stage - Only Super Admin, Admin, and Supervisor can move stage
                    if (ConfigService.canMoveLeadStage) ...[
                      ElevatedButton.icon(
                        onPressed: () => _showAdvanceStageModal(lead),
                        icon: const Icon(Icons.swap_horiz, size: 15),
                        label: const Text('Advance', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: stageColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          elevation: 0,
                        ),
                      ),
                      const SizedBox(width: 6),
                    ] else ...[
                      // Sales Officer / Telecaller: Read-only locked stage indicator
                      Tooltip(
                        message: 'Stage movement is restricted to Supervisor & Admin',
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.lock_outline, size: 12, color: Color(0xFF64748B)),
                              const SizedBox(width: 4),
                              Text(
                                LeadStageHelper.getShortLabel(lead.status),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],

                    // Follow-up
                    IconButton.filledTonal(
                      icon: const Icon(Icons.alarm_add, size: 15, color: Color(0xFF2563EB)),
                      tooltip: 'Schedule Callback',
                      onPressed: () => _showScheduleFollowupModal(lead),
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFFEFF6FF),
                        padding: const EdgeInsets.all(8),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildJourneyStepper(CrmLead lead) {
    if (lead.isRejected) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFFCA5A5)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cancel, size: 13, color: Color(0xFFEF4444)),
            SizedBox(width: 4),
            Text(
              'Application Closed / Lost',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFDC2626)),
            ),
          ],
        ),
      );
    }

    final currentStep = lead.stepNumber; // 1 to 7
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Stage $currentStep of 7: ${LeadStageHelper.getLabel(lead.status)}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: LeadStageHelper.getColor(lead.status),
              ),
            ),
            Text(
              '${((currentStep / 7) * 100).toInt()}% Complete',
              style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: currentStep / 7.0,
            minHeight: 5,
            backgroundColor: const Color(0xFFE2E8F0),
            valueColor: AlwaysStoppedAnimation<Color>(LeadStageHelper.getColor(lead.status)),
          ),
        ),
      ],
    );
  }
}
