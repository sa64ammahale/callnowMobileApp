import 'package:flutter/material.dart';
import 'package:callnow_new/constants/lead_stages.dart';
import 'package:callnow_new/services/api_service.dart';
import 'package:callnow_new/services/call_tracking_service.dart';

class IncomingCallActionDialog extends StatefulWidget {
  final String phoneNumber;
  final int durationSeconds;
  final String direction;
  final Map<String, dynamic>? contactData;
  final VoidCallback? onCompleted;

  const IncomingCallActionDialog({
    super.key,
    required this.phoneNumber,
    required this.durationSeconds,
    this.direction = 'INCOMING',
    this.contactData,
    this.onCompleted,
  });

  static Future<void> show(
    BuildContext context, {
    required String phoneNumber,
    required int durationSeconds,
    String direction = 'INCOMING',
    Map<String, dynamic>? contactData,
    VoidCallback? onCompleted,
  }) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => IncomingCallActionDialog(
        phoneNumber: phoneNumber,
        durationSeconds: durationSeconds,
        direction: direction,
        contactData: contactData,
        onCompleted: onCompleted,
      ),
    );
  }

  @override
  State<IncomingCallActionDialog> createState() => _IncomingCallActionDialogState();
}

class _IncomingCallActionDialogState extends State<IncomingCallActionDialog> {
  int _activeTab = 0; // 0: Quick Status, 1: Convert to Lead, 2: Schedule Followup
  bool _isSubmitting = false;
  String? _errorMessage;

  // Quick Status tab state
  late String _selectedStatus;
  final TextEditingController _notesController = TextEditingController();

  // Convert to Lead tab state
  final TextEditingController _leadNameController = TextEditingController();
  final TextEditingController _leadAmountController = TextEditingController();
  final TextEditingController _leadCustomBankController = TextEditingController();
  late String _selectedLoanType;
  late String _selectedBank;

  // Schedule Followup tab state
  DateTime _followupDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _followupTime = const TimeOfDay(hour: 11, minute: 0);
  final TextEditingController _followupNoteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final cData = widget.contactData;
    final prevStatus = cData?['status']?.toString();
    _selectedStatus = (prevStatus != null && prevStatus.isNotEmpty && prevStatus != 'Ringing')
        ? 'Interested'
        : 'Interested';

    final existingName = cData?['name']?.toString() ?? '';
    _leadNameController.text = existingName.isNotEmpty ? existingName : '';

    _selectedLoanType = LeadStageHelper.loanTypes.first;
    _selectedBank = LeadStageHelper.partnerBanks.first;
  }

  @override
  void dispose() {
    _notesController.dispose();
    _leadNameController.dispose();
    _leadAmountController.dispose();
    _leadCustomBankController.dispose();
    _followupNoteController.dispose();
    super.dispose();
  }

  String _formatDuration(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m}m ${s}s';
  }

  Future<void> _handleQuickStatusSubmit() async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final cData = widget.contactData;
      final recordId = (cData?['record_id'] as num?)?.toInt() ?? 0;
      final source = (cData?['source_type']?.toString().toUpperCase() == 'TEMP') ? 'TEMP' : 'MAIN';

      if (recordId <= 0) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = 'Cannot update status: No valid CRM record found for this number.';
        });
        return;
      }

      await ApiService.submitCallResult(
        callId: recordId,
        source: source,
        status: _selectedStatus,
        notes: _notesController.text.trim().isNotEmpty
            ? _notesController.text.trim()
            : 'Conversation callback completed (${_formatDuration(widget.durationSeconds)})',
        durationSeconds: widget.durationSeconds,
        timingClassification: widget.durationSeconds > 20
            ? 'CONNECTED_CONVERSATION'
            : (widget.durationSeconds > 0 ? 'CONNECTED_SHORT' : 'NOT_CONNECTED'),
        phoneNumber: widget.phoneNumber,
      );

      await CallTrackingService.clearPendingPostCall();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Call status updated to $_selectedStatus'),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
        widget.onCompleted?.call();
      }
    } catch (e) {
      setState(() {
        _isSubmitting = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _handleConvertToLeadSubmit() async {
    final name = _leadNameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorMessage = 'Please enter customer name');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final cData = widget.contactData;
      final recordId = (cData?['record_id'] as num?)?.toInt() ?? 0;
      final source = (cData?['source_type']?.toString().toUpperCase() == 'TEMP') ? 'TEMP' : 'MAIN';

      if (recordId <= 0) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = 'Cannot update status: No valid CRM record found for this number.';
        });
        return;
      }
      final finalBank = _selectedBank == 'Other Bank'
          ? _leadCustomBankController.text.trim()
          : _selectedBank;

      final loanQualification = {
        'loan_type': _selectedLoanType,
        'loan_amount': _leadAmountController.text.trim(),
        'target_bank': finalBank,
        'source': source,
        'temperature': 'HOT',
      };

      await ApiService.submitCallResult(
        callId: recordId,
        source: source,
        status: 'Interested',
        notes: _notesController.text.trim().isNotEmpty
            ? _notesController.text.trim()
            : 'Lead created via callback conversation',
        durationSeconds: widget.durationSeconds,
        timingClassification: 'CONNECTED_CONVERSATION',
        loanQualification: loanQualification,
        phoneNumber: widget.phoneNumber,
      );

      await CallTrackingService.clearPendingPostCall();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lead created successfully for $name!'),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
        widget.onCompleted?.call();
      }
    } catch (e) {
      setState(() {
        _isSubmitting = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _handleFollowupSubmit() async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final scheduledDateTime = DateTime(
        _followupDate.year,
        _followupDate.month,
        _followupDate.day,
        _followupTime.hour,
        _followupTime.minute,
      );

      final cData = widget.contactData;
      final recordId = (cData?['record_id'] as num?)?.toInt();
      final leadId = (cData?['lead_id'] as num?)?.toInt();
      final source = (cData?['source_type']?.toString().toUpperCase() == 'TEMP') ? 'TEMP' : 'MAIN';

      if ((recordId == null || recordId <= 0) && (leadId == null || leadId <= 0)) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = 'Cannot schedule follow-up: No valid CRM record found for this number.';
        });
        return;
      }

      await ApiService.createServerFollowup(
        leadId: leadId,
        clientContactId: recordId,
        contactSource: source,
        followupAt: scheduledDateTime,
        note: _followupNoteController.text.trim().isNotEmpty
            ? _followupNoteController.text.trim()
            : 'Follow-up scheduled after incoming callback (${_formatDuration(widget.durationSeconds)})',
        phoneNumber: widget.phoneNumber,
      );

      await CallTrackingService.clearPendingPostCall();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Follow-up scheduled successfully!'),
            backgroundColor: Color(0xFF0284C7),
            behavior: SnackBarBehavior.floating,
          ),
        );
        widget.onCompleted?.call();
      }
    } catch (e) {
      setState(() {
        _isSubmitting = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cData = widget.contactData;
    final contactName = cData?['name']?.toString() ?? '';
    final previousStatus = cData?['status']?.toString() ?? 'Pending';
    final isLead = cData?['is_lead'] == true;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header Banner
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.phone_callback_rounded,
                    color: Color(0xFF059669),
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            widget.direction == 'INCOMING' ? 'Incoming Call Connected' : 'Call Connected',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close, size: 20, color: Color(0xFF64748B)),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () {
                              CallTrackingService.clearPendingPostCall();
                              Navigator.pop(context);
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        contactName.isNotEmpty ? contactName : widget.phoneNumber,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF334155),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.timer_outlined, size: 12, color: Color(0xFF475569)),
                                const SizedBox(width: 4),
                                Text(
                                  _formatDuration(widget.durationSeconds),
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF475569),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: previousStatus.toLowerCase() == 'ringing'
                                  ? const Color(0xFFFEF3C7)
                                  : const Color(0xFFE0E7FF),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  previousStatus.toLowerCase() == 'ringing'
                                      ? Icons.ring_volume
                                      : Icons.bookmark_border,
                                  size: 12,
                                  color: previousStatus.toLowerCase() == 'ringing'
                                      ? const Color(0xFFD97706)
                                      : const Color(0xFF4338CA),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Was: $previousStatus',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: previousStatus.toLowerCase() == 'ringing'
                                        ? const Color(0xFFB45309)
                                        : const Color(0xFF3730A3),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isLead)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFDCFCE7),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'CRM Lead',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF15803D),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 12),

            // Tab bar
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  _buildTabItem(0, 'Quick Status', Icons.check_circle_outline),
                  _buildTabItem(1, 'Convert to Lead', Icons.star_border),
                  _buildTabItem(2, 'Follow-up', Icons.event_available),
                ],
              ),
            ),
            const SizedBox(height: 16),

            if (_errorMessage != null)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFCA5A5)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, size: 16, color: Color(0xFFDC2626)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(fontSize: 12, color: Color(0xFFDC2626)),
                      ),
                    ),
                  ],
                ),
              ),

            // Tab views
            if (_activeTab == 0) _buildQuickStatusTab(),
            if (_activeTab == 1) _buildConvertToLeadTab(),
            if (_activeTab == 2) _buildFollowupTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildTabItem(int index, String label, IconData icon) {
    final isSelected = _activeTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _activeTab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected
                ? [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4, offset: const Offset(0, 1))]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: isSelected ? const Color(0xFF0284C7) : const Color(0xFF64748B),
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? const Color(0xFF0284C7) : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickStatusTab() {
    final statusList = ['Interested', 'Follow-up', 'Not Interested', 'Ringing', 'Busy / No Answer'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Select Call Outcome:',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: statusList.map((st) {
            final isSel = _selectedStatus == st;
            return ChoiceChip(
              label: Text(st),
              selected: isSel,
              selectedColor: const Color(0xFF0284C7),
              labelStyle: TextStyle(
                fontSize: 12,
                fontWeight: isSel ? FontWeight.w600 : FontWeight.w500,
                color: isSel ? Colors.white : const Color(0xFF334155),
              ),
              onSelected: (_) => setState(() => _selectedStatus = st),
            );
          }).toList(),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _notesController,
          maxLines: 2,
          decoration: InputDecoration(
            hintText: 'Add conversation notes...',
            hintStyle: const TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8)),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF0284C7), width: 1.5)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: ElevatedButton(
            onPressed: _isSubmitting ? null : _handleQuickStatusSubmit,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0284C7),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: _isSubmitting
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Save Call Outcome', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  Widget _buildConvertToLeadTab() {
    final banks = [...LeadStageHelper.partnerBanks, 'Other Bank'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _leadNameController,
          decoration: InputDecoration(
            labelText: 'Client Full Name *',
            labelStyle: const TextStyle(fontSize: 12.5),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _selectedLoanType,
                decoration: InputDecoration(
                  labelText: 'Loan Type',
                  labelStyle: const TextStyle(fontSize: 12.5),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                items: LeadStageHelper.loanTypes.map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 12)))).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedLoanType = val);
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _leadAmountController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Loan Amount (₹)',
                  labelStyle: const TextStyle(fontSize: 12.5),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _selectedBank,
          decoration: InputDecoration(
            labelText: 'Target Partner Bank',
            labelStyle: const TextStyle(fontSize: 12.5),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          items: banks.map((b) => DropdownMenuItem(value: b, child: Text(b, style: const TextStyle(fontSize: 12)))).toList(),
          onChanged: (val) {
            if (val != null) setState(() => _selectedBank = val);
          },
        ),
        if (_selectedBank == 'Other Bank') ...[
          const SizedBox(height: 10),
          TextField(
            controller: _leadCustomBankController,
            decoration: InputDecoration(
              labelText: 'Enter Bank Name *',
              labelStyle: const TextStyle(fontSize: 12.5),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: ElevatedButton.icon(
            onPressed: _isSubmitting ? null : _handleConvertToLeadSubmit,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: _isSubmitting
                ? const SizedBox.shrink()
                : const Icon(Icons.star_rounded, size: 18),
            label: _isSubmitting
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Convert to CRM Lead & Save', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  Widget _buildFollowupTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today, size: 16),
                label: Text(
                  '${_followupDate.day}/${_followupDate.month}/${_followupDate.year}',
                  style: const TextStyle(fontSize: 12.5),
                ),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _followupDate,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 90)),
                  );
                  if (picked != null) setState(() => _followupDate = picked);
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.access_time, size: 16),
                label: Text(_followupTime.format(context), style: const TextStyle(fontSize: 12.5)),
                onPressed: () async {
                  final picked = await showTimePicker(context: context, initialTime: _followupTime);
                  if (picked != null) setState(() => _followupTime = picked);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _followupNoteController,
          maxLines: 2,
          decoration: InputDecoration(
            hintText: 'Follow-up discussion notes / agenda...',
            hintStyle: const TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8)),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: ElevatedButton.icon(
            onPressed: _isSubmitting ? null : _handleFollowupSubmit,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0EA5E9),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: _isSubmitting
                ? const SizedBox.shrink()
                : const Icon(Icons.calendar_month_outlined, size: 18),
            label: _isSubmitting
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Schedule Follow-up', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }
}
