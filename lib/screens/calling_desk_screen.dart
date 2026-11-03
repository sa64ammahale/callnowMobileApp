import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:callnow_new/constants/lead_stages.dart';
import 'package:callnow_new/screens/call_reports_screen.dart';
import 'package:callnow_new/services/api_service.dart';
import 'package:callnow_new/services/call_tracking_service.dart';
import 'package:callnow_new/services/followup_service.dart';

class CallingDeskScreen extends StatefulWidget {
  const CallingDeskScreen({super.key});

  @override
  State<CallingDeskScreen> createState() => _CallingDeskScreenState();
}

class _CallingDeskScreenState extends State<CallingDeskScreen>
    with WidgetsBindingObserver {
  final List<Map<String, dynamic>> _leads = [];
  int _currentIndex = 0;
  bool _isLoading = true;
  bool _isFetchingMore = false;
  bool _isSubmitting = false;
  String? _errorMessage;

  // Inactivity tracking
  Timer? _inactivityTimer;

  // Verified call log state from Android OS
  VerifiedCallLog? _verifiedCallLog;
  bool _isCheckingCallLog = false;
  bool _showOutcomes = false;

  // Current lead form state
  String _selectedDisposition = 'NOT_CONNECTED_BUSY';
  final TextEditingController _notesController = TextEditingController();
  int _durationSeconds = 0;
  String _timingClassification = 'NOT_CONNECTED';
  DateTime? _followupDateTime;
  bool _hasCallOccurred = false;
  bool _allowUnconnectedOverrideForShortCalls = false;
  bool _isOtherInfoExpanded = false;

  bool get _isCallConnected => _durationSeconds > 0;

  final List<Map<String, dynamic>> _connectedOptions = [
    {
      'id': 'CONNECTED_INTERESTED',
      'label': 'Interested / Hot',
      'icon': Icons.thumb_up_alt_rounded,
      'color': Colors.green,
    },
    {
      'id': 'CONNECTED_FOLLOWUP',
      'label': 'Follow-up Needed',
      'icon': Icons.schedule_rounded,
      'color': Colors.orange,
    },
    {
      'id': 'CONNECTED_CONVERTED',
      'label': 'Deal Converted',
      'icon': Icons.verified_rounded,
      'color': Colors.teal,
    },
    {
      'id': 'CONNECTED_NOT_INTERESTED',
      'label': 'Not Interested',
      'icon': Icons.thumb_down_alt_rounded,
      'color': Colors.grey,
    },
    {
      'id': 'CONNECTED_DND',
      'label': 'DND Requested',
      'icon': Icons.do_not_disturb_on_rounded,
      'color': Colors.deepOrange,
    },
    {
      'id': 'VOICEMAIL',
      'label': 'Voicemail / Machine',
      'icon': Icons.voicemail_rounded,
      'color': Colors.deepPurple,
    },
  ];

  final List<Map<String, dynamic>> _unconnectedOptions = [
    {
      'id': 'NOT_CONNECTED_BUSY',
      'label': 'Busy / No Answer',
      'icon': Icons.phone_missed_rounded,
      'color': Colors.amber.shade800,
    },
    {
      'id': 'NOT_CONNECTED_SWITCHED_OFF',
      'label': 'Switched Off',
      'icon': Icons.power_settings_new_rounded,
      'color': Colors.blueGrey,
    },
    {
      'id': 'NOT_CONNECTED_DND',
      'label': 'DND Number',
      'icon': Icons.do_not_disturb_on_rounded,
      'color': Colors.deepOrange,
    },
    {
      'id': 'NOT_CONNECTED_WRONG_NUMBER',
      'label': 'Wrong Number',
      'icon': Icons.error_outline_rounded,
      'color': Colors.red,
    },
    {
      'id': 'NOT_CONNECTED_CANCELLED',
      'label': 'Call Cancelled',
      'icon': Icons.cancel_outlined,
      'color': Colors.brown,
    },
  ];

  List<Map<String, dynamic>> get _allDispositionOptions => [
        ..._connectedOptions,
        ..._unconnectedOptions,
      ];

  final List<String> _quickRemarks = [
    'Customer requested DND / Do not call',
    'Called, asked to callback later',
    'Shared brochure on WhatsApp',
    'Needs loan urgently (₹5L+)',
    'Currently busy in meeting',
    'Wrong person / not enquiring',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startInactivityTimer();
    _loadInitialBatch();
    CallTrackingService.activeCallSession.addListener(_onCallSessionDetected);
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    CallTrackingService.activeCallSession.removeListener(_onCallSessionDetected);
    _notesController.dispose();
    super.dispose();
  }

  void _startInactivityTimer() {
    _inactivityTimer?.cancel();
  }

  void _stopInactivityBlink() {
    _inactivityTimer?.cancel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // User returned from dialer, auto-verify call log immediately and with retry delays
      _verifyCallWithAndroidLog();
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (mounted && (_verifiedCallLog == null || !_verifiedCallLog!.isDialed)) {
          _verifyCallWithAndroidLog();
        }
      });
      Future.delayed(const Duration(milliseconds: 2500), () {
        if (mounted && (_verifiedCallLog == null || !_verifiedCallLog!.isDialed)) {
          _verifyCallWithAndroidLog();
        }
      });
    }
  }

  /// Query native Android CallLog to verify if active contact was actually dialed
  Future<void> _verifyCallWithAndroidLog({bool showToast = false}) async {
    final lead = _currentLead;
    if (lead == null) return;
    final mobile = (lead['mobile'] ?? '').toString();
    if (mobile.isEmpty) return;

    if (!mounted) return;
    setState(() => _isCheckingCallLog = true);

    try {
      // Query recent call logs for this mobile number
      final verified = await CallTrackingService.verifyCallLog(
        mobile,
        afterTimestamp: 0,
      );

      if (mounted) {
        setState(() {
          _isCheckingCallLog = false;
          _verifiedCallLog = verified;

          if (verified.isDialed) {
            _hasCallOccurred = true;
            _durationSeconds = verified.durationSeconds;
            _stopInactivityBlink();

            if (verified.durationSeconds == 0) {
              _timingClassification = 'NOT_CONNECTED';
              _selectedDisposition = 'NOT_CONNECTED_BUSY';
              _allowUnconnectedOverrideForShortCalls = false;
            } else if (verified.isVoicemailLikely) {
              // 1s - 18s: Automated Voicemail / IVR pickup
              _timingClassification = 'VOICEMAIL';
              _selectedDisposition = 'VOICEMAIL';
              _allowUnconnectedOverrideForShortCalls = false;
            } else {
              _timingClassification = verified.durationSeconds > 20
                  ? 'CONNECTED_CONVERSATION'
                  : 'CONNECTED_SHORT';
              _selectedDisposition = 'CONNECTED_INTERESTED';
              _allowUnconnectedOverrideForShortCalls = false;
            }
          }
        });

        if (showToast && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(
                    verified.isDialed ? Icons.check_circle : Icons.info_outline,
                    color: Colors.white,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      verified.isDialed
                          ? '✓ Call found in call history! (${verified.durationFormatted}) - Submit is unlocked.'
                          : 'No outgoing call to $mobile found in device history. Please ensure the call was placed.',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              backgroundColor:
                  verified.isDialed ? Colors.green.shade800 : Colors.orange.shade800,
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isCheckingCallLog = false);
    }
  }

  void _onCallSessionDetected() {
    // When background listener fires, also trigger real CallLog check
    _verifyCallWithAndroidLog();
  }

  Map<String, dynamic>? get _currentLead {
    if (_leads.isEmpty || _currentIndex >= _leads.length) return null;
    return _leads[_currentIndex];
  }

  Future<void> _loadInitialBatch({bool force = false}) async {
    // If not forced and we already have leads in memory, retain current lead
    if (!force && _leads.isNotEmpty && _currentIndex < _leads.length) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final batch = await ApiService.getBatchLeads(limit: 15);
      setState(() {
        _leads.clear();
        _leads.addAll(batch);
        _currentIndex = 0;
        _isLoading = false;
        _resetFormForCurrentLead();
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  Future<void> _fetchMoreLeads() async {
    if (_isFetchingMore) return;
    setState(() => _isFetchingMore = true);

    try {
      final batch = await ApiService.getBatchLeads(limit: 15);
      if (mounted) {
        setState(() {
          _leads.addAll(batch);
          _isFetchingMore = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isFetchingMore = false);
    }
  }

  void _resetFormForCurrentLead() {
    _notesController.clear();
    _durationSeconds = 0;
    _timingClassification = 'NOT_CONNECTED';
    _followupDateTime = null;
    _hasCallOccurred = false;
    _allowUnconnectedOverrideForShortCalls = false;
    _isOtherInfoExpanded = false;
    _selectedDisposition = 'NOT_CONNECTED_BUSY';
    _verifiedCallLog = null;
    _isCheckingCallLog = false;
    _showOutcomes = false;
    _startInactivityTimer();
  }

  Future<void> _onGetStatusTapped() async {
    setState(() {
      _showOutcomes = true;
    });
    await _verifyCallWithAndroidLog(showToast: true);
  }

  Future<void> _callCurrentLead() async {
    final lead = _currentLead;
    if (lead == null) return;
    final mobile = (lead['mobile'] ?? '').toString();
    if (mobile.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No mobile number available for this contact.')),
      );
      return;
    }

    final launched = await CallTrackingService.makePhoneCall(mobile);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open phone dialer.')),
      );
    } else {
      // Auto-trigger call log verification after dialer launch
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) _verifyCallWithAndroidLog();
      });
    }
  }

  Future<void> _whatsappCurrentLead() async {
    final lead = _currentLead;
    if (lead == null) return;
    final mobile = (lead['mobile'] ?? '').toString();
    final name = (lead['name'] ?? 'Client').toString();
    final pkg = (lead['package'] ?? 'financial assistance').toString();

    final msg = 'Hello $name, this is regarding your enquiry for $pkg on CallNow. Are you available for a quick conversation?';
    await CallTrackingService.openWhatsApp(mobile, message: msg);
  }

  Future<void> _pickFollowupDateTime() async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
    );

    if (pickedDate != null && mounted) {
      final pickedTime = await showTimePicker(
        context: context,
        initialTime: const TimeOfDay(hour: 11, minute: 0),
      );

      if (pickedTime != null && mounted) {
        setState(() {
          _followupDateTime = DateTime(
            pickedDate.year,
            pickedDate.month,
            pickedDate.day,
            pickedTime.hour,
            pickedTime.minute,
          );
        });
      }
    }
  }

  void _setFollowupPreset(Duration duration) {
    setState(() {
      _followupDateTime = DateTime.now().add(duration);
    });
  }

  void _setFollowupPresetAbsolute({required int hour, required int minute, bool tomorrow = false}) {
    final now = DateTime.now();
    final base = tomorrow ? now.add(const Duration(days: 1)) : now;
    setState(() {
      _followupDateTime = DateTime(base.year, base.month, base.day, hour, minute);
    });
  }

  String _formatPackageAmount(String package) {
    if (package.isEmpty) return '';
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

  Widget _buildPresetChip(String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ActionChip(
        label: Text(
          label,
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: Color(0xFF334155),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: const Color(0xFFF8FAFC),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
        onPressed: onTap,
      ),
    );
  }

  void _skipLead() {
    if (_currentIndex + 1 < _leads.length) {
      setState(() {
        _currentIndex++;
        _resetFormForCurrentLead();
      });
      // Check prefetch
      if (_leads.length - _currentIndex <= 3) {
        _fetchMoreLeads();
      }
    } else {
      _loadInitialBatch(force: true);
    }
  }

  Future<void> _submitAndNext() async {
    final lead = _currentLead;
    if (lead == null) return;

    final bool isDialed = _verifiedCallLog != null && _verifiedCallLog!.isDialed;
    final verifiedDur = isDialed ? _verifiedCallLog!.durationSeconds : 0;

    // Connected outcomes require verified outgoing talk time
    final isConnectedOutcome = _connectedOptions.any((o) => o['id'] == _selectedDisposition);
    if (isConnectedOutcome && (!isDialed || verifiedDur == 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.lock_clock, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Connected outcomes require verified talk time in device call log. Please place the call or choose an unconnected outcome.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.red.shade800,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    // Anti-Fraud Rule 1: Zero duration cannot be submitted with connected outcomes
    if (verifiedDur == 0) {
      final isConnected = _connectedOptions.any((o) => o['id'] == _selectedDisposition);
      if (isConnected) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Fraud Prevention: Call duration was 0s (unconnected). You cannot submit Connected, Interested, or Deal Converted.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            backgroundColor: Colors.red.shade800,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
        return;
      }
    }

    // Anti-Fraud Rule 2: Short duration (<=18s) cannot be marked Deal Converted
    if (verifiedDur <= 18 && _selectedDisposition == 'CONNECTED_CONVERTED') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Fraud Prevention: Call lasted only ${verifiedDur}s. "Deal Converted" requires verified conversation talk time (>20s).',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          backgroundColor: Colors.red.shade800,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    // Anti-Fraud Rule 3: Connected call (>20s) cannot be marked as Switched Off or Cancelled
    if (verifiedDur > 20 &&
        (_selectedDisposition == 'NOT_CONNECTED_SWITCHED_OFF' ||
            _selectedDisposition == 'NOT_CONNECTED_CANCELLED')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Validation Error: Call was connected for ${verifiedDur}s. Cannot report as Switched Off or Cancelled.',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          backgroundColor: Colors.red.shade800,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    final leadId = int.tryParse(lead['id'].toString()) ?? 0;
    final source = (lead['source'] ?? 'TEMPORARY').toString();

    // Map disposition to readable status string
    String statusLabel = _selectedDisposition;
    for (final opt in _allDispositionOptions) {
      if (opt['id'] == _selectedDisposition) {
        statusLabel = opt['label'] as String;
        break;
      }
    }
    if (_selectedDisposition == 'VOICEMAIL') {
      statusLabel = 'Voicemail';
    }

    // If Voicemail, force timingClassification to NOT_CONNECTED
    final effectiveTiming = _selectedDisposition == 'VOICEMAIL'
        ? 'NOT_CONNECTED'
        : _timingClassification;

    String? followupIso;
    if (_followupDateTime != null) {
      followupIso = _followupDateTime!.toIso8601String().replaceAll('T', ' ').substring(0, 19);
      try {
        await FollowupService.instance.addFollowup(
          customerName: lead['name']?.toString() ?? 'Customer',
          phoneNumber: lead['mobile']?.toString() ?? '',
          company: lead['company']?.toString(),
          scheduledTime: _followupDateTime!,
          notes: _notesController.text.trim().isNotEmpty
              ? _notesController.text.trim()
              : 'Follow-up requested from Calling Desk ($statusLabel)',
          leadId: int.tryParse(leadId.toString()),
          source: source,
        );
      } catch (e) {
        debugPrint('Error saving local followup: $e');
      }
    }

    setState(() => _isSubmitting = true);

    try {
      await ApiService.submitCallResult(
        callId: leadId,
        source: source,
        status: statusLabel,
        notes: _notesController.text.trim().isNotEmpty ? _notesController.text.trim() : null,
        durationSeconds: verifiedDur,
        timingClassification: effectiveTiming,
        nextFollowupAt: followupIso,
      );

      if (mounted) {
        final followupNotice = _followupDateTime != null
            ? ' (⏰ Callback set for ${_followupDateTime!.day}/${_followupDateTime!.month} ${_followupDateTime!.hour.toString().padLeft(2, '0')}:${_followupDateTime!.minute.toString().padLeft(2, '0')})'
            : '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Call saved: $statusLabel for ${lead['name']}$followupNotice'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );

        setState(() {
          _isSubmitting = false;
          _currentIndex++;
          _resetFormForCurrentLead();
        });

        // Trigger pre-fetch when queue runs low
        if (_leads.length - _currentIndex <= 3) {
          _fetchMoreLeads();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Submission failed: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: _buildBody(colorScheme),
      bottomNavigationBar: null,
    );
  }

  Widget _buildSaveAndSubmitActions() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          // Skip Lead button
          Expanded(
            flex: 2,
            child: OutlinedButton.icon(
              onPressed: _isSubmitting ? null : _skipLead,
              icon: const Icon(Icons.skip_next_rounded, size: 19),
              label: const Text(
                'Skip',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Save and Submit Call Details button
          Expanded(
            flex: 5,
            child: FilledButton.icon(
              onPressed: _isSubmitting ? null : _submitAndNext,
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check_circle_outline_rounded, size: 20),
              label: Text(
                _isSubmitting ? 'Saving Call...' : 'Save & Submit Call Details',
                style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(ColorScheme colorScheme) {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Fetching call queue from server...', style: TextStyle(fontSize: 14)),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.redAccent),
              const SizedBox(height: 16),
              Text(
                'Failed to load contacts',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _loadInitialBatch,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    final lead = _currentLead;
    if (lead == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.task_alt_rounded, size: 72, color: Colors.green),
              ),
              const SizedBox(height: 20),
              const Text(
                'All Calls Completed!',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'You have completed all contacts in the current batch. Tap below to fetch the next batch from the server.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _loadInitialBatch,
                icon: const Icon(Icons.download_rounded),
                label: const Text('Fetch Next Contacts Batch'),
              ),
            ],
          ),
        ),
      );
    }

    final name = (lead['name'] ?? 'Unnamed Contact').toString();
    final mobile = (lead['mobile'] ?? '').toString();
    final company = (lead['company'] ?? '').toString().trim();
    final pkg = (lead['package'] ?? '').toString().trim();
    final formattedPkg = _formatPackageAmount(pkg);
    final loanType = (lead['loan_type'] ?? '').toString().trim();
    final otherInfo = (lead['other_info'] ?? '').toString().trim();
    final callCount = int.tryParse(lead['call_count']?.toString() ?? '0') ?? 0;
    final lastStatus = (lead['last_status'] ?? '').toString().trim();

    final statusKey = (lead['status'] ?? lead['lead_status_new'] ?? lead['last_status'] ?? 'LEAD').toString().trim();
    final stageColor = LeadStageHelper.getColor(statusKey);
    final stageLabel = LeadStageHelper.getLabel(statusKey);
    final stageIcon = LeadStageHelper.getIcon(statusKey);
    final leadStage = (lead['lead_stage'] ?? lead['stage'] ?? '').toString().trim();
    final priority = (lead['priority'] ?? '').toString().trim();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        FocusScope.of(context).unfocus();
        if (_verifiedCallLog == null || !_verifiedCallLog!.isDialed) {
          _startInactivityTimer();
        }
      },
      child: RefreshIndicator(
        onRefresh: () => _loadInitialBatch(force: true),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Queue Progress Card
              _buildQueueProgressCard(),

              // 2. Stage-Dynamic Primary Contact Card
              _buildContactCard(
                name: name,
                mobile: mobile,
                company: company,
                pkg: pkg,
                formattedPkg: formattedPkg,
                loanType: loanType,
                otherInfo: otherInfo,
                callCount: callCount,
                lastStatus: lastStatus,
                statusKey: statusKey,
                stageColor: stageColor,
                stageLabel: stageLabel,
                stageIcon: stageIcon,
                leadStage: leadStage,
                priority: priority,
              ),
              const SizedBox(height: 12),

              // Outcomes & Submission - only shown after user taps 'Get Status'
              if (_showOutcomes) ...[
                // Verified Status Banner (talk time duration & connection classification)
                _buildVerifiedCallStatusBanner(),
                const SizedBox(height: 10),

                // Structured Disposition & Outcome Card
                _buildDispositionCard(),
                const SizedBox(height: 10),

                // Callback & Follow-up Reminder Card
                _buildFollowupCard(),
                const SizedBox(height: 10),

                // Telecaller Remarks & Quick Notes Card
                _buildRemarksCard(),
                const SizedBox(height: 12),

                // Save & Submit Button + Skip Lead Button
                _buildSaveAndSubmitActions(),
                const SizedBox(height: 24),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 1. Queue Progress Card
  Widget _buildQueueProgressCard() {
    final total = _leads.length;
    final current = _currentIndex + 1;
    final progress = total > 0 ? (current / total).clamp(0.0, 1.0) : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.queue_rounded, size: 14, color: Color(0xFF2563EB)),
              ),
              const SizedBox(width: 8),
              const Text(
                'Calling Desk Queue',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Lead $current of $total',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              if (_isFetchingMore) ...[
                const SizedBox(width: 6),
                const SizedBox(
                  width: 11,
                  height: 11,
                  child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF2563EB)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: const Color(0xFFF1F5F9),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF2563EB)),
            ),
          ),
        ],
      ),
    );
  }

  /// 2. Primary Contact Card with Stage-Dynamic Coloring
  Widget _buildContactCard({
    required String name,
    required String mobile,
    required String company,
    required String pkg,
    required String formattedPkg,
    required String loanType,
    required String otherInfo,
    required int callCount,
    required String lastStatus,
    required String statusKey,
    required Color stageColor,
    required String stageLabel,
    required IconData stageIcon,
    required String leadStage,
    required String priority,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: stageColor.withValues(alpha: 0.32), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: stageColor.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Accent Color Bar
            Container(
              height: 4.5,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [stageColor, stageColor.withValues(alpha: 0.6)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Row: Avatar + Name + Badges
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Stage-themed Avatar
                      CircleAvatar(
                        radius: 21,
                        backgroundColor: stageColor.withValues(alpha: 0.12),
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: stageColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                fontSize: 16.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F172A),
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (company.isNotEmpty && company != 'Individual') ...[
                              const SizedBox(height: 2),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  const Icon(Icons.business_rounded, size: 13, color: Color(0xFF64748B)),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      company,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF475569),
                                        fontWeight: FontWeight.w500,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      // Stage & Priority Badges Column
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                            decoration: BoxDecoration(
                              color: stageColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: stageColor.withValues(alpha: 0.28)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(stageIcon, size: 12, color: stageColor),
                                const SizedBox(width: 4),
                                Text(
                                  stageLabel,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                    color: stageColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (leadStage.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: LeadStageHelper.getTemperatureColor(leadStage).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: LeadStageHelper.getTemperatureColor(leadStage).withValues(alpha: 0.25),
                                ),
                              ),
                              child: Text(
                                leadStage,
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                  color: LeadStageHelper.getTemperatureColor(leadStage),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Metadata Pills Row (Loan Amount, Loan Type, Call count)
                  Wrap(
                    spacing: 6,
                    runSpacing: 5,
                    children: [
                      // Formatted Loan Package Pill
                      if (formattedPkg.isNotEmpty && formattedPkg != 'General Enquiry')
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFECFDF5),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFA7F3D0)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.payments_outlined, size: 13, color: Color(0xFF047857)),
                              const SizedBox(width: 4),
                              Text(
                                formattedPkg,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF047857),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Loan Type Pill
                      if (loanType.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFBFDBFE)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.account_balance_wallet_outlined, size: 12.5, color: Color(0xFF1D4ED8)),
                              const SizedBox(width: 4),
                              Text(
                                loanType,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1D4ED8),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Dialed count tag
                      if (callCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFCBD5E1)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.phone_forwarded_rounded, size: 12, color: Color(0xFF475569)),
                              const SizedBox(width: 4),
                              Text(
                                'Dialed $callCount time${callCount > 1 ? 's' : ''}',
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF334155),
                                ),
                              ),
                            ],
                          ),
                        )
                      else if (lastStatus.isNotEmpty && lastStatus != 'Not Called')
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Text(
                            lastStatus,
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF475569),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Phone Number Container
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.phone_in_talk_rounded, size: 16, color: stageColor),
                        const SizedBox(width: 8),
                        Text(
                          mobile,
                          style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                            letterSpacing: 0.4,
                          ),
                        ),
                        const Spacer(),
                        InkWell(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: mobile));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Copied $mobile to clipboard'),
                                duration: const Duration(seconds: 1),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: Icon(Icons.copy_rounded, size: 15, color: Colors.grey.shade600),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Other Information Banner (Warm note style)
                  if (otherInfo.isNotEmpty) ...[
                    const SizedBox(height: 9),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: const BorderRadius.only(
                          topRight: Radius.circular(8),
                          bottomRight: Radius.circular(8),
                          topLeft: Radius.circular(3),
                          bottomLeft: Radius.circular(3),
                        ),
                        border: const Border(
                          left: BorderSide(color: Color(0xFFF59E0B), width: 3.5),
                          top: BorderSide(color: Color(0xFFFEF3C7)),
                          right: BorderSide(color: Color(0xFFFEF3C7)),
                          bottom: BorderSide(color: Color(0xFFFEF3C7)),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.assignment_outlined, size: 14, color: Color(0xFFD97706)),
                          const SizedBox(width: 7),
                          Expanded(
                            child: RichText(
                              text: TextSpan(
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  height: 1.35,
                                  color: Color(0xFF78350F),
                                  fontWeight: FontWeight.w500,
                                ),
                                children: [
                                  TextSpan(
                                    text: (!(_isOtherInfoExpanded) && otherInfo.length > 90)
                                        ? '${otherInfo.substring(0, 90)}...'
                                        : otherInfo,
                                  ),
                                  if (otherInfo.length > 90) ...[
                                    const TextSpan(text: ' '),
                                    WidgetSpan(
                                      alignment: PlaceholderAlignment.middle,
                                      child: GestureDetector(
                                        onTap: () {
                                          setState(() {
                                            _isOtherInfoExpanded = !_isOtherInfoExpanded;
                                          });
                                        },
                                        child: Text(
                                          _isOtherInfoExpanded ? 'Show Less' : 'Read More',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFFB45309),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),

                  // 3 Circular Action Buttons Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // 1. WhatsApp / Message (Red Circle)
                      _buildCircularActionButton(
                        icon: Icons.chat_bubble_rounded,
                        color: const Color(0xFFEF4444),
                        tooltip: 'Message on WhatsApp',
                        onTap: _whatsappCurrentLead,
                      ),
                      // 2. Call History (Slate Circle) -> opens Today's Call History
                      _buildCircularActionButton(
                        icon: Icons.history_rounded,
                        color: const Color(0xFF475569),
                        tooltip: "Today's Call History",
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const CallReportsScreen(
                                initialTabIndex: 1,
                                initialPeriod: 'today',
                              ),
                            ),
                          );
                        },
                      ),
                      // 3. Call Now (Vibrant Green Circle)
                      _buildCircularActionButton(
                        icon: Icons.call_rounded,
                        color: const Color(0xFF16A34A),
                        tooltip: 'Call Now',
                        onTap: _callCurrentLead,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Get Status Button (Full Width, Prominent)
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _isCheckingCallLog ? null : _onGetStatusTapped,
                      icon: _isCheckingCallLog
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.refresh_rounded, size: 21, color: Colors.white),
                      label: Text(
                        _isCheckingCallLog ? 'Getting Status...' : 'Get Status',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.3,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF334155),
                        foregroundColor: Colors.white,
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCircularActionButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Ink(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Center(
              child: Icon(
                icon,
                color: Colors.white,
                size: 28,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 3. Verified Call Status & Timing Tier Banner (shown after Get Status)
  Widget _buildVerifiedCallStatusBanner() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _getTimingTierBgColor(),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _getTimingTierBorderColor(), width: 1.2),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: _getTimingTierIconBgColor(),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(_getTimingTierIcon(), color: _getTimingTierTextColor(), size: 18),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _getTimingTierTitle(),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _getTimingTierTextColor(),
                        fontSize: 12.5,
                      ),
                    ),
                    Text(
                      _verifiedCallLog?.isDialed == true
                          ? 'Android Log: ${_verifiedCallLog!.durationFormatted} talk time'
                          : 'Call not dialed yet (0s)',
                      style: TextStyle(
                        fontSize: 11,
                        color: _getTimingTierTextColor().withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: _isCheckingCallLog ? null : () => _verifyCallWithAndroidLog(showToast: true),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: _getTimingTierButtonBgColor(),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isCheckingCallLog)
                        const SizedBox(
                          width: 11,
                          height: 11,
                          child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white),
                        )
                      else
                        Icon(
                          _verifiedCallLog?.isDialed == true ? Icons.check_circle_rounded : Icons.sync_rounded,
                          size: 13,
                          color: Colors.white,
                        ),
                      const SizedBox(width: 4),
                      Text(
                        _isCheckingCallLog
                            ? 'Checking...'
                            : (_verifiedCallLog?.isDialed == true ? 'Refresh' : 'Verify'),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // Smart Voicemail Detection Banner for short connected calls (1-18s)
        if (_isCallConnected && _durationSeconds > 0 && _durationSeconds <= 18) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.deepPurple.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.deepPurple.shade200),
            ),
            child: Row(
              children: [
                const Icon(Icons.voicemail_rounded, size: 17, color: Colors.deepPurple),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Short call (${_durationSeconds}s). Was this Voicemail / IVR?',
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: Colors.deepPurple,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    backgroundColor: _selectedDisposition == 'VOICEMAIL'
                        ? Colors.deepPurple
                        : Colors.deepPurple.withValues(alpha: 0.2),
                    foregroundColor: _selectedDisposition == 'VOICEMAIL' ? Colors.white : Colors.deepPurple,
                  ),
                  onPressed: () {
                    setState(() {
                      _selectedDisposition = 'VOICEMAIL';
                    });
                  },
                  child: const Text('Mark Voicemail', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// 4. Structured Call Disposition & Outcome Card
  Widget _buildDispositionCard() {
    final isConnectedOutcomes = _isCallConnected && !_allowUnconnectedOverrideForShortCalls;
    final cardBorderColor = isConnectedOutcomes ? const Color(0xFF86EFAC) : const Color(0xFFFDE047);
    final headerIconColor = isConnectedOutcomes ? const Color(0xFF16A34A) : Colors.amber.shade800;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cardBorderColor, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              Icon(
                isConnectedOutcomes ? Icons.phone_in_talk_rounded : Icons.phone_missed_rounded,
                size: 16,
                color: headerIconColor,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  isConnectedOutcomes ? 'Connected Outcomes' : 'Not Connected Outcomes',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              if (_isCallConnected)
                InkWell(
                  onTap: () {
                    setState(() {
                      _allowUnconnectedOverrideForShortCalls = !_allowUnconnectedOverrideForShortCalls;
                      _selectedDisposition = _allowUnconnectedOverrideForShortCalls
                          ? 'NOT_CONNECTED_BUSY'
                          : 'CONNECTED_INTERESTED';
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.swap_horiz, size: 15, color: Color(0xFF2563EB)),
                        const SizedBox(width: 3),
                        Text(
                          _allowUnconnectedOverrideForShortCalls ? 'Show Connected' : 'Show Unconnected',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF2563EB), fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock_outline_rounded, size: 11, color: Color(0xFF64748B)),
                      SizedBox(width: 3),
                      Text(
                        'Connected Locked (0s)',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // Disposition ChoiceChips
          Wrap(
            spacing: 7,
            runSpacing: 6,
            children: (isConnectedOutcomes ? _connectedOptions : _unconnectedOptions).map((opt) {
              final isSelected = _selectedDisposition == opt['id'];
              final color = opt['color'] as Color;
              return ChoiceChip(
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      opt['icon'] as IconData,
                      size: 14,
                      color: isSelected ? Colors.white : color,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      opt['label'] as String,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        color: isSelected ? Colors.white : const Color(0xFF1E293B),
                      ),
                    ),
                  ],
                ),
                selected: isSelected,
                selectedColor: color,
                backgroundColor: const Color(0xFFF8FAFC),
                side: BorderSide(
                  color: isSelected ? color : color.withValues(alpha: 0.28),
                  width: 1,
                ),
                onSelected: (val) {
                  if (val) {
                    setState(() {
                      _selectedDisposition = opt['id'] as String;
                      if (_selectedDisposition == 'CONNECTED_FOLLOWUP' && _followupDateTime == null) {
                        _followupDateTime = DateTime.now().add(const Duration(days: 1));
                      }
                    });
                  }
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  /// 5. Callback & Follow-up Reminder Card
  Widget _buildFollowupCard() {
    final isFollowupSet = _followupDateTime != null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isFollowupSet ? const Color(0xFFFFFBEB) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isFollowupSet ? const Color(0xFFF59E0B) : const Color(0xFFE2E8F0),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.alarm_on_rounded,
                color: isFollowupSet ? const Color(0xFFD97706) : const Color(0xFF64748B),
                size: 16,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  isFollowupSet
                      ? 'Callback: ${_followupDateTime!.day}/${_followupDateTime!.month} at ${_followupDateTime!.hour.toString().padLeft(2, '0')}:${_followupDateTime!.minute.toString().padLeft(2, '0')}'
                      : 'Schedule Callback / Follow-Up Reminder',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isFollowupSet ? const Color(0xFF92400E) : const Color(0xFF1E293B),
                  ),
                ),
              ),
              if (isFollowupSet)
                InkWell(
                  onTap: () => setState(() => _followupDateTime = null),
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: Colors.red.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, size: 12, color: Colors.red),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // Highlighted Date & Time Picker
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ActionChip(
                    avatar: const Icon(Icons.calendar_month_rounded, size: 14, color: Color(0xFF2563EB)),
                    label: const Text(
                      'Pick Date & Time',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E40AF),
                      ),
                    ),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    backgroundColor: const Color(0xFFEFF6FF),
                    side: const BorderSide(color: Color(0xFFBFDBFE), width: 1.1),
                    onPressed: _pickFollowupDateTime,
                  ),
                ),
                _buildPresetChip('+15m', () => _setFollowupPreset(const Duration(minutes: 15))),
                _buildPresetChip('+30m', () => _setFollowupPreset(const Duration(minutes: 30))),
                _buildPresetChip('+1h', () => _setFollowupPreset(const Duration(hours: 1))),
                _buildPresetChip('+2h', () => _setFollowupPreset(const Duration(hours: 2))),
                _buildPresetChip('Tmrw 10 AM', () => _setFollowupPresetAbsolute(hour: 10, minute: 0, tomorrow: true)),
                _buildPresetChip('Tmrw 3 PM', () => _setFollowupPresetAbsolute(hour: 15, minute: 0, tomorrow: true)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 6. Telecaller Remarks & Quick Notes Card
  Widget _buildRemarksCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              const Icon(Icons.edit_note_rounded, size: 17, color: Color(0xFF64748B)),
              const SizedBox(width: 6),
              const Text(
                'Telecaller Remarks & Quick Notes',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Quick Remarks Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _quickRemarks.map((remark) {
                return Padding(
                  padding: const EdgeInsets.only(right: 5.0),
                  child: ActionChip(
                    label: Text(
                      remark,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: Color(0xFF334155),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    backgroundColor: const Color(0xFFF8FAFC),
                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                    onPressed: () {
                      final current = _notesController.text;
                      if (current.isEmpty) {
                        _notesController.text = remark;
                      } else {
                        _notesController.text = '$current | $remark';
                      }
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),

          // Detailed Notes Field
          TextField(
            controller: _notesController,
            minLines: 1,
            maxLines: 2,
            style: const TextStyle(fontSize: 12.5, color: Color(0xFF0F172A)),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Enter feedback, loan interest, objections...',
              hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
              prefixIcon: const Icon(Icons.notes_rounded, size: 17, color: Color(0xFF64748B)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
              ),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
            ),
          ),
        ],
      ),
    );
  }

  Color _getTimingTierBgColor() {
    switch (_timingClassification) {
      case 'CONNECTED_CONVERSATION':
        return const Color(0xFFF0FDF4); // soft emerald
      case 'CONNECTED_SHORT':
        return const Color(0xFFFEFCE8); // soft warm amber
      case 'VOICEMAIL':
        return const Color(0xFFFAF5FF); // soft lavender
      case 'NOT_CONNECTED':
      default:
        return _verifiedCallLog?.isDialed == true
            ? const Color(0xFFFFF7ED) // dialed 0s warm orange
            : const Color(0xFFF8FAFC); // not dialed cool slate
    }
  }

  Color _getTimingTierBorderColor() {
    switch (_timingClassification) {
      case 'CONNECTED_CONVERSATION':
        return const Color(0xFF86EFAC);
      case 'CONNECTED_SHORT':
        return const Color(0xFFFDE047);
      case 'VOICEMAIL':
        return const Color(0xFFD8B4FE);
      case 'NOT_CONNECTED':
      default:
        return _verifiedCallLog?.isDialed == true
            ? const Color(0xFFFDBA74)
            : const Color(0xFFCBD5E1);
    }
  }

  Color _getTimingTierTextColor() {
    switch (_timingClassification) {
      case 'CONNECTED_CONVERSATION':
        return const Color(0xFF14532D);
      case 'CONNECTED_SHORT':
        return const Color(0xFF854D0E);
      case 'VOICEMAIL':
        return const Color(0xFF581C87);
      case 'NOT_CONNECTED':
      default:
        return _verifiedCallLog?.isDialed == true
            ? const Color(0xFF9A3412)
            : const Color(0xFF334155);
    }
  }

  Color _getTimingTierIconBgColor() {
    switch (_timingClassification) {
      case 'CONNECTED_CONVERSATION':
        return const Color(0xFFDCFCE7);
      case 'CONNECTED_SHORT':
        return const Color(0xFFFEF08A);
      case 'VOICEMAIL':
        return const Color(0xFFF3E8FF);
      case 'NOT_CONNECTED':
      default:
        return _verifiedCallLog?.isDialed == true
            ? const Color(0xFFFFEDD5)
            : const Color(0xFFE2E8F0);
    }
  }

  Color _getTimingTierButtonBgColor() {
    switch (_timingClassification) {
      case 'CONNECTED_CONVERSATION':
        return const Color(0xFF16A34A);
      case 'CONNECTED_SHORT':
        return const Color(0xFFD97706);
      case 'VOICEMAIL':
        return const Color(0xFF7C3AED);
      case 'NOT_CONNECTED':
      default:
        return _verifiedCallLog?.isDialed == true
            ? const Color(0xFFEA580C)
            : const Color(0xFF2563EB); // vibrant modern blue for ready to call
    }
  }

  IconData _getTimingTierIcon() {
    switch (_timingClassification) {
      case 'CONNECTED_CONVERSATION':
        return Icons.chat_rounded;
      case 'CONNECTED_SHORT':
        return Icons.timer_outlined;
      case 'VOICEMAIL':
        return Icons.voicemail_rounded;
      case 'NOT_CONNECTED':
      default:
        return Icons.phone_disabled_rounded;
    }
  }

  String _getTimingTierTitle() {
    if (_verifiedCallLog != null && _verifiedCallLog!.isDialed) {
      if (_verifiedCallLog!.durationSeconds > 20) {
        return 'Verified Conversation (>20s)';
      } else if (_verifiedCallLog!.isVoicemailLikely) {
        return 'Voicemail / Automated Machine (${_verifiedCallLog!.durationSeconds}s)';
      } else if (_verifiedCallLog!.durationSeconds > 0) {
        return 'Short Connected Call (${_verifiedCallLog!.durationSeconds}s)';
      } else {
        return 'Call Dialed • Not Connected (0s)';
      }
    }
    return _hasCallOccurred ? 'Call Not Connected (0s)' : 'Status Retrieved (0s Talk Time)';
  }
}
