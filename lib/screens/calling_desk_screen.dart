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
  String _selectedDisposition = 'RINGING';
  final TextEditingController _notesController = TextEditingController();
  int _durationSeconds = 0;
  DateTime? _followupDateTime;
  bool _allowUnconnectedOverrideForShortCalls = false;
  bool _isOtherInfoExpanded = false;

  bool get _isCallConnected => _durationSeconds > 0;

  final List<Map<String, dynamic>> _connectedOptions = [
    {
      'id': 'DND',
      'label': 'DND',
      'serverStatus': 'DND',
      'icon': Icons.do_not_disturb_on_rounded,
      'color': Colors.deepOrange,
    },
    {
      'id': 'NOT_INTERESTED',
      'label': 'Not Intrested',
      'serverStatus': 'Not Intrested',
      'icon': Icons.thumb_down_alt_rounded,
      'color': Colors.grey,
    },
    {
      'id': 'CALLBACK_BUSY',
      'label': 'CallBack/ Busy',
      'serverStatus': 'CallBack/ Busy',
      'icon': Icons.schedule_rounded,
      'color': Colors.orange,
    },
    {
      'id': 'ENQUIRY_INTERESTED',
      'label': 'Enquiry/ Intrested',
      'serverStatus': 'Enquiry/ Intrested',
      'icon': Icons.thumb_up_alt_rounded,
      'color': Colors.green,
    },
  ];

  final List<Map<String, dynamic>> _unconnectedOptions = [
    {
      'id': 'SWITCH_OFF',
      'label': 'Switch OFF',
      'serverStatus': 'Switch OFF',
      'icon': Icons.power_settings_new_rounded,
      'color': Colors.blueGrey,
    },
    {
      'id': 'RINGING',
      'label': 'Ringing',
      'serverStatus': 'Ringing',
      'icon': Icons.phone_forwarded_rounded,
      'color': Colors.amber.shade800,
    },
    {
      'id': 'NOT_REACHABLE',
      'label': 'Not Rechable',
      'serverStatus': 'Not Rechable',
      'icon': Icons.signal_cellular_connected_no_internet_0_bar_rounded,
      'color': Colors.deepOrange,
    },
    {
      'id': 'INVALID_DELETE',
      'label': 'Invalid/Delete',
      'serverStatus': 'Invalid/Delete',
      'icon': Icons.delete_outline_rounded,
      'color': Colors.red,
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
            _durationSeconds = verified.durationSeconds;
            _stopInactivityBlink();

            if (verified.durationSeconds == 0) {
              _selectedDisposition = 'RINGING';
              _allowUnconnectedOverrideForShortCalls = false;
            } else {
              _selectedDisposition = 'NOT_INTERESTED';
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
    _followupDateTime = null;
    _allowUnconnectedOverrideForShortCalls = false;
    _isOtherInfoExpanded = false;
    _selectedDisposition = 'RINGING';
    _verifiedCallLog = null;
    _isCheckingCallLog = false;
    _showOutcomes = false;
    _startInactivityTimer();
  }

  Future<void> _onGetStatusTapped() async {
    setState(() => _isCheckingCallLog = true);
    await _verifyCallWithAndroidLog(showToast: false);
    if (mounted) setState(() => _isCheckingCallLog = false);

    final bool isDialed = _verifiedCallLog != null && _verifiedCallLog!.isDialed;
    if (!isDialed) {
      if (mounted) {
        setState(() {
          _showOutcomes = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.phone_missed_rounded, color: Colors.white, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Please dial the call first. Outcomes will unlock after dialing.',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
      return;
    }

    if (mounted) {
      final bool isConnected = _durationSeconds > 0;
      setState(() {
        _showOutcomes = true;
        _selectedDisposition = isConnected ? 'NOT_INTERESTED' : 'RINGING';
      });

      // Bottom floating pill toast matching screenshot:
      // "Status: Connected. CallType.outgoing" / "Status: Not Connected. CallType.outgoing"
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          elevation: 0,
          backgroundColor: Colors.transparent,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          margin: const EdgeInsets.only(bottom: 24, left: 32, right: 32),
          content: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: const BoxDecoration(
                      color: Color(0xFFFFEDD5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.call_made_rounded,
                      size: 15,
                      color: Color(0xFFEA580C),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Text(
                    isConnected
                        ? 'Status: Connected. CallType.outgoing'
                        : 'Status: Not Connected. CallType.outgoing',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
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
    return ActionChip(
      label: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Color(0xFF334155),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      backgroundColor: Colors.white,
      side: const BorderSide(color: Color(0xFFCBD5E1)),
      onPressed: onTap,
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
    if (verifiedDur == 0 && isConnectedOutcome) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Fraud Prevention: Call duration was 0s (unconnected). Please choose an unconnected outcome.',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          backgroundColor: Colors.red.shade800,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    // Anti-Fraud Rule 2: Connected call (>20s) cannot be marked as Switch OFF
    if (verifiedDur > 20 && _selectedDisposition == 'SWITCH_OFF') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Validation Error: Call was connected for ${verifiedDur}s. Cannot report as Switch OFF.',
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

    // Map disposition to exact label / server status
    String statusLabel = _selectedDisposition;
    for (final opt in _allDispositionOptions) {
      if (opt['id'] == _selectedDisposition) {
        statusLabel = (opt['serverStatus'] ?? opt['label']) as String;
        break;
      }
    }

    final effectiveTiming = isConnectedOutcome
        ? (verifiedDur > 20 ? 'CONNECTED_CONVERSATION' : 'CONNECTED_SHORT')
        : 'NOT_CONNECTED';

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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: _isSubmitting ? null : _submitAndNext,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4CAF50), // Vibrant green matching screenshot
              foregroundColor: Colors.white,
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: _isSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text(
                    'Save & Next',
                    style: TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 6),
        TextButton.icon(
          onPressed: _isSubmitting ? null : _skipLead,
          icon: const Icon(Icons.skip_next_rounded, size: 18, color: Color(0xFF64748B)),
          label: const Text(
            'Skip this lead',
            style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
          ),
        ),
      ],
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
              // Primary Contact Card (with queue badge & actions)
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
                // Structured 2x2 Outcome Card
                _buildDispositionCard(),
                const SizedBox(height: 10),

                // If CallBack/Busy is selected or followup is scheduled, show reminder card
                if (_selectedDisposition == 'CALLBACK_BUSY' || _followupDateTime != null) ...[
                  _buildFollowupCard(),
                  const SizedBox(height: 10),
                ],

                // Telecaller Remarks & Quick Notes Card
                _buildRemarksCard(),
                const SizedBox(height: 12),

                // Save & Next Button
                _buildSaveAndSubmitActions(),
                const SizedBox(height: 24),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 2. Primary Contact Details Card (Structured table format matching telecaller workflow)
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
    final total = _leads.length;
    final current = _currentIndex + 1;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Accent / Header with Corner Queue Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                border: Border(
                  bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1),
                ),
              ),
              child: Row(
                children: [
                  // Lead Stage Tag
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: stageColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
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
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: stageColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  // Top Corner Queue Badge: 'Lead 1 of 15'
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFA7F3D0)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.format_list_numbered_rounded, size: 12.5, color: Color(0xFF047857)),
                        const SizedBox(width: 4),
                        Text(
                          'Lead $current of $total',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF047857),
                          ),
                        ),
                        if (_isFetchingMore) ...[
                          const SizedBox(width: 5),
                          const SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF047857)),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Structured Contact Details Body
            Padding(
              padding: const EdgeInsets.all(14.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Structured Key-Value Details (Clean & high-clarity)
                  _buildContactDetailRow(
                    label: 'Name:',
                    valueWidget: Text(
                      name.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  _buildContactDetailRow(
                    label: 'Mobile:',
                    valueWidget: Row(
                      children: [
                        Text(
                          mobile,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E293B),
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(width: 8),
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
                            padding: const EdgeInsets.all(3.0),
                            child: Icon(Icons.copy_rounded, size: 14, color: Colors.grey.shade600),
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (company.isNotEmpty && company != 'Individual') ...[
                    const SizedBox(height: 8),
                    _buildContactDetailRow(
                      label: 'Company:',
                      valueWidget: Text(
                        company.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFEA580C),
                        ),
                      ),
                    ),
                  ],

                  if (formattedPkg.isNotEmpty && formattedPkg != 'General Enquiry') ...[
                    const SizedBox(height: 8),
                    _buildContactDetailRow(
                      label: 'Package:',
                      valueWidget: Text(
                        formattedPkg.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF059669),
                        ),
                      ),
                    ),
                  ],

                  if (loanType.isNotEmpty || (leadStage.isNotEmpty && leadStage != stageLabel)) ...[
                    const SizedBox(height: 8),
                    _buildContactDetailRow(
                      label: 'Type / Stage:',
                      valueWidget: Text(
                        [if (loanType.isNotEmpty) loanType, if (leadStage.isNotEmpty && leadStage != stageLabel) leadStage].join(' • '),
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF475569),
                        ),
                      ),
                    ),
                  ],

                  if (callCount > 0 || (lastStatus.isNotEmpty && lastStatus != 'Not Called')) ...[
                    const SizedBox(height: 8),
                    _buildContactDetailRow(
                      label: 'History:',
                      valueWidget: Text(
                        callCount > 0
                            ? 'Dialed $callCount time${callCount > 1 ? 's' : ''}${lastStatus.isNotEmpty ? ' ($lastStatus)' : ''}'
                            : lastStatus,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ),
                  ],

                  if (otherInfo.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _buildContactDetailRow(
                      label: 'Notes:',
                      valueWidget: RichText(
                        text: TextSpan(
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1.35,
                            color: Color(0xFF78350F),
                            fontWeight: FontWeight.w500,
                          ),
                          children: [
                            TextSpan(
                              text: (!(_isOtherInfoExpanded) && otherInfo.length > 80)
                                  ? '${otherInfo.substring(0, 80)}...'
                                  : otherInfo,
                            ),
                            if (otherInfo.length > 80) ...[
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

                  const SizedBox(height: 16),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  const SizedBox(height: 14),

                  // 3 Circular Action Buttons Row (WhatsApp, Call History, Call Now)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // 1. WhatsApp Button with recognizable WhatsApp icon (52px diameter)
                      _buildCircularActionButton(
                        iconWidget: _buildWhatsAppIcon(size: 22),
                        color: const Color(0xFF25D366),
                        tooltip: 'Message on WhatsApp',
                        onTap: _whatsappCurrentLead,
                      ),
                      // 2. Call History Button (52px diameter)
                      _buildCircularActionButton(
                        icon: Icons.history_rounded,
                        color: const Color(0xFF64748B),
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
                      // 3. Call Now Button (52px diameter)
                      _buildCircularActionButton(
                        icon: Icons.call_rounded,
                        color: const Color(0xFF16A34A),
                        tooltip: 'Call Now',
                        onTap: _callCurrentLead,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Get Status Button (Full Width, Sleek Dark Style matching reference)
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _isCheckingCallLog ? null : _onGetStatusTapped,
                      icon: _isCheckingCallLog
                          ? const SizedBox(
                              width: 17,
                              height: 17,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.refresh_rounded, size: 20, color: Colors.white),
                      label: Text(
                        _isCheckingCallLog ? 'Getting Status...' : 'Get Status',
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.3,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF334155),
                        foregroundColor: Colors.white,
                        elevation: 1.5,
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

  /// Helper row for structured contact details
  Widget _buildContactDetailRow({
    required String label,
    required Widget valueWidget,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 82,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B),
            ),
          ),
        ),
        Expanded(child: valueWidget),
      ],
    );
  }

  /// WhatsApp Icon composite widget (Speech bubble with inner rotated phone receiver)
  Widget _buildWhatsAppIcon({double size = 22}) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.chat_bubble_rounded, size: size, color: Colors.white),
          Transform.rotate(
            angle: -0.22,
            child: Icon(Icons.call, size: size * 0.52, color: const Color(0xFF25D366)),
          ),
        ],
      ),
    );
  }

  Widget _buildCircularActionButton({
    Widget? iconWidget,
    IconData? icon,
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
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.3),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: iconWidget ??
                  Icon(
                    icon,
                    color: Colors.white,
                    size: 22,
                  ),
            ),
          ),
        ),
      ),
    );
  }

  /// 4. Structured Call Disposition & Outcome Card (2x2 Radio Grid matching screenshot)
  Widget _buildDispositionCard() {
    final isConnectedOutcomes = _isCallConnected && !_allowUnconnectedOverrideForShortCalls;
    final options = isConnectedOutcomes ? _connectedOptions : _unconnectedOptions;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF333742), // Dark card matching user screenshot
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row 1 (Col 1 & Col 2)
          Row(
            children: [
              Expanded(
                child: _buildRadioOutcomeItem(
                  id: options[0]['id'] as String,
                  label: options[0]['label'] as String,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildRadioOutcomeItem(
                  id: options[1]['id'] as String,
                  label: options[1]['label'] as String,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Row 2 (Col 1 & Col 2)
          Row(
            children: [
              Expanded(
                child: _buildRadioOutcomeItem(
                  id: options[2]['id'] as String,
                  label: options[2]['label'] as String,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildRadioOutcomeItem(
                  id: options[3]['id'] as String,
                  label: options[3]['label'] as String,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRadioOutcomeItem({
    required String id,
    required String label,
  }) {
    final isSelected = _selectedDisposition == id;

    return InkWell(
      onTap: () {
        setState(() {
          _selectedDisposition = id;
          if (id == 'CALLBACK_BUSY' && _followupDateTime == null) {
            _followupDateTime = DateTime.now().add(const Duration(days: 1));
          }
        });
      },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Custom Radio Circle matching screenshot
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? const Color(0xFF26C6DA) : const Color(0xFF94A3B8),
                  width: isSelected ? 2.2 : 1.8,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFF26C6DA), // Cyan dot matching screenshot
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  fontStyle: FontStyle.italic,
                  color: isSelected ? Colors.white : const Color(0xFFE2E8F0),
                  letterSpacing: 0.1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 5. Callback & Follow-up Reminder Card
  Widget _buildFollowupCard() {
    final isFollowupSet = _followupDateTime != null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isFollowupSet ? const Color(0xFFFFFBEB) : const Color(0xFFF6FAF7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isFollowupSet ? const Color(0xFFFDE68A) : const Color(0xFFD1FAE5),
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
                color: isFollowupSet ? const Color(0xFFD97706) : const Color(0xFF059669),
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
                    color: isFollowupSet ? const Color(0xFF92400E) : const Color(0xFF065F46),
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
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              // Highlighted Date & Time Picker
              ActionChip(
                avatar: const Icon(Icons.calendar_month_rounded, size: 14, color: Color(0xFF059669)),
                label: const Text(
                  'Pick Date & Time',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF065F46),
                  ),
                ),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                backgroundColor: const Color(0xFFECFDF5),
                side: const BorderSide(color: Color(0xFFA7F3D0), width: 1.1),
                onPressed: _pickFollowupDateTime,
              ),
              _buildPresetChip('+15m', () => _setFollowupPreset(const Duration(minutes: 15))),
              _buildPresetChip('+30m', () => _setFollowupPreset(const Duration(minutes: 30))),
              _buildPresetChip('+1h', () => _setFollowupPreset(const Duration(hours: 1))),
              _buildPresetChip('+2h', () => _setFollowupPreset(const Duration(hours: 2))),
              _buildPresetChip('Tmrw 10 AM', () => _setFollowupPresetAbsolute(hour: 10, minute: 0, tomorrow: true)),
              _buildPresetChip('Tmrw 3 PM', () => _setFollowupPresetAbsolute(hour: 15, minute: 0, tomorrow: true)),
            ],
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
}
