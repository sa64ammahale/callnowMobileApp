import 'package:flutter/material.dart';
import 'package:callnow_new/services/api_service.dart';
import 'package:callnow_new/services/call_tracking_service.dart';

class CallingDeskScreen extends StatefulWidget {
  const CallingDeskScreen({super.key});

  @override
  State<CallingDeskScreen> createState() => _CallingDeskScreenState();
}

class _CallingDeskScreenState extends State<CallingDeskScreen> with WidgetsBindingObserver {
  final List<Map<String, dynamic>> _leads = [];
  int _currentIndex = 0;
  bool _isLoading = true;
  bool _isFetchingMore = false;
  bool _isSubmitting = false;
  String? _errorMessage;

  // Verified call log state from Android OS
  VerifiedCallLog? _verifiedCallLog;
  bool _isCheckingCallLog = false;

  // Current lead form state
  String _selectedDisposition = 'NOT_CONNECTED_BUSY';
  final TextEditingController _notesController = TextEditingController();
  int _durationSeconds = 0;
  String _timingClassification = 'NOT_CONNECTED';
  DateTime? _followupDateTime;
  bool _hasCallOccurred = false;
  bool? _overrideShowConnected;

  bool get _isCallConnected => _overrideShowConnected ?? (_durationSeconds > 0);

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
    _loadInitialBatch();
    CallTrackingService.activeCallSession.addListener(_onCallSessionDetected);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    CallTrackingService.activeCallSession.removeListener(_onCallSessionDetected);
    _notesController.dispose();
    super.dispose();
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

            if (verified.durationSeconds == 0) {
              _timingClassification = 'NOT_CONNECTED';
              _selectedDisposition = 'NOT_CONNECTED_BUSY';
              _overrideShowConnected = false;
            } else if (verified.isVoicemailLikely) {
              // 1s - 18s: Automated Voicemail / IVR pickup
              _timingClassification = 'VOICEMAIL';
              _selectedDisposition = 'VOICEMAIL';
              _overrideShowConnected = true;
            } else {
              _timingClassification = verified.durationSeconds > 20
                  ? 'CONNECTED_CONVERSATION'
                  : 'CONNECTED_SHORT';
              _selectedDisposition = 'CONNECTED_INTERESTED';
              _overrideShowConnected = true;
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
    _overrideShowConnected = null;
    _selectedDisposition = 'NOT_CONNECTED_BUSY';
    _verifiedCallLog = null;
    _isCheckingCallLog = false;
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

    // Strict Dial Enforcement: Outgoing call must be found in Android call logs
    if (_verifiedCallLog == null || !_verifiedCallLog!.isDialed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.lock_clock, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Dial verification required: Android call logs show no outgoing call to this number yet. Please dial first.',
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

    final verifiedDur = _verifiedCallLog!.durationSeconds;

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

    // Anti-Fraud Rule 3: Connected call (>20s) cannot be marked as Switched Off, DND, or Cancelled
    if (verifiedDur > 20 &&
        (_selectedDisposition == 'NOT_CONNECTED_SWITCHED_OFF' ||
            _selectedDisposition == 'NOT_CONNECTED_CANCELLED' ||
            _selectedDisposition == 'NOT_CONNECTED_DND')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Validation Error: Call was connected for ${verifiedDur}s. Cannot report as Switched Off, DND, or Cancelled.',
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
    if (_selectedDisposition == 'CONNECTED_FOLLOWUP' && _followupDateTime != null) {
      followupIso = _followupDateTime!.toIso8601String().replaceAll('T', ' ').substring(0, 19);
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Call saved: $statusLabel for ${lead['name']}'),
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
      appBar: AppBar(
        title: const Text('Calling Desk', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload Contacts',
            onPressed: _isLoading || _isSubmitting ? null : () => _loadInitialBatch(force: true),
          ),
        ],
      ),
      body: _buildBody(colorScheme),
      bottomNavigationBar: _buildBottomActionBar(colorScheme),
    );
  }

  Widget? _buildBottomActionBar(ColorScheme colorScheme) {
    if (_isLoading || _errorMessage != null || _currentLead == null) {
      return null;
    }

    final bool isDialed = _verifiedCallLog != null && _verifiedCallLog!.isDialed;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Call verification status bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: isDialed
                  ? Colors.green.withValues(alpha: 0.1)
                  : Colors.amber.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDialed ? Colors.green.shade300 : Colors.amber.shade300,
                width: 1,
              ),
            ),
            child: Row(
              children: [
                if (_isCheckingCallLog) ...[
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Verifying with Android call logs...',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ),
                ] else if (isDialed) ...[
                  const Icon(Icons.verified, size: 14, color: Colors.green),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '✓ Call Log Verified: Dialed • ${_verifiedCallLog!.durationFormatted} talk time',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade900,
                      ),
                    ),
                  ),
                ] else ...[
                  Icon(Icons.lock_clock, size: 14, color: Colors.amber.shade900),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Dial customer to unlock submit',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.amber.shade900,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _isSubmitting ? null : _skipLead,
                icon: const Icon(Icons.skip_next, size: 18),
                label: const Text('Skip'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _isSubmitting
                      ? null
                      : (isDialed
                          ? _submitAndNext
                          : () async {
                              // Tapping locked button immediately queries call log in case user just hung up
                              await _verifyCallWithAndroidLog(showToast: true);
                            }),
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Icon(
                          isDialed ? Icons.check_circle_outline : Icons.lock_outline,
                          size: 20,
                        ),
                  label: Text(
                    _isSubmitting
                        ? 'Saving...'
                        : (isDialed ? 'Submit & Next Call' : 'Dial to Unlock Submit'),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: isDialed ? Colors.green.shade700 : Colors.grey.shade400,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
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

    final source = (lead['source'] ?? 'TEMPORARY').toString().toUpperCase();
    final isMainDb = source == 'MAIN';
    final name = (lead['name'] ?? 'Unnamed Contact').toString();
    final mobile = (lead['mobile'] ?? '').toString();
    final company = (lead['company'] ?? '').toString().trim();
    final pkg = (lead['package'] ?? '').toString().trim();
    final otherInfo = (lead['other_info'] ?? '').toString().trim();
    final callCount = int.tryParse(lead['call_count']?.toString() ?? '0') ?? 0;
    final lastStatus = (lead['last_status'] ?? '').toString().trim();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusScope.of(context).unfocus(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Queue progress pill & source indicator
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Contact ${_currentIndex + 1} of ${_leads.length}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isMainDb
                      ? Colors.blue.withValues(alpha: 0.15)
                      : Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isMainDb ? Colors.blue.shade400 : Colors.orange.shade400,
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isMainDb ? Icons.verified : Icons.inventory_2_outlined,
                      size: 14,
                      color: isMainDb ? Colors.blue : Colors.orange.shade800,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isMainDb ? 'Priority Client' : 'New Contact',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isMainDb ? Colors.blue.shade900 : Colors.orange.shade900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Primary Contact Card
          Card(
            elevation: 3,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(18.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: colorScheme.primaryContainer,
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (company.isNotEmpty && company != 'Individual') ...[
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  Icon(Icons.business_rounded, size: 14, color: Colors.grey.shade600),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      company,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey.shade700,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            if (pkg.isNotEmpty && pkg != 'General Enquiry') ...[
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  Icon(Icons.sell_outlined, size: 14, color: colorScheme.primary),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      pkg,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: colorScheme.primary,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Phone Number Container (Number ID removed)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.phone_in_talk_rounded, size: 18, color: colorScheme.primary),
                        const SizedBox(width: 10),
                        Text(
                          mobile,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const Spacer(),
                        if (callCount > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Dialed $callCount time${callCount > 1 ? 's' : ''}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade800,
                              ),
                            ),
                          )
                        else if (lastStatus.isNotEmpty && lastStatus != 'Not Called')
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              lastStatus,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Other Information Banner (Notes, loan requirement, or extra details)
                  if (otherInfo.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.notes_rounded, size: 16, color: colorScheme.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              otherInfo,
                              style: TextStyle(
                                fontSize: 12.5,
                                height: 1.35,
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),

                  // Call & WhatsApp Action Buttons
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: FilledButton.icon(
                          onPressed: _callCurrentLead,
                          icon: const Icon(Icons.call_rounded),
                          label: const Text(
                            'Call Now',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: OutlinedButton.icon(
                          onPressed: _whatsappCurrentLead,
                          icon: const Icon(Icons.chat_bubble_outline, color: Colors.green),
                          label: const Text('WhatsApp', style: TextStyle(color: Colors.green)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            side: const BorderSide(color: Colors.green),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // The SINGLE Fetch Status Button in the Calling Desk
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isCheckingCallLog
                          ? null
                          : () => _verifyCallWithAndroidLog(showToast: true),
                      icon: _isCheckingCallLog
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              _verifiedCallLog?.isDialed == true
                                  ? Icons.check_circle_rounded
                                  : Icons.sync_rounded,
                              color: _verifiedCallLog?.isDialed == true
                                  ? Colors.green
                                  : Colors.indigo,
                              size: 18,
                            ),
                      label: Text(
                        _isCheckingCallLog
                            ? 'Checking Call History...'
                            : (_verifiedCallLog?.isDialed == true
                                ? 'Status Fetched (${_verifiedCallLog!.durationFormatted}) • Tap to Refresh'
                                : 'Fetch Status from Call History'),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: _verifiedCallLog?.isDialed == true
                               ? Colors.green.shade800
                              : Colors.indigo.shade800,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        backgroundColor: _verifiedCallLog?.isDialed == true
                            ? Colors.green.withValues(alpha: 0.08)
                            : Colors.indigo.withValues(alpha: 0.06),
                        side: BorderSide(
                          color: _verifiedCallLog?.isDialed == true
                              ? Colors.green.shade400
                              : Colors.indigo.shade300,
                        ),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Detected Call Timing Tier Banner (sync button removed)
          Card(
            color: _getTimingTierBgColor(),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: _getTimingTierBorderColor(), width: 1),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14.0),
              child: Row(
                children: [
                  Icon(_getTimingTierIcon(), color: _getTimingTierTextColor(), size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _getTimingTierTitle(),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _getTimingTierTextColor(),
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _verifiedCallLog?.isDialed == true
                              ? 'Android Call Log: ${_verifiedCallLog!.durationFormatted} talk time'
                              : 'Call not dialed yet (0s)',
                          style: TextStyle(
                            fontSize: 12,
                            color: _getTimingTierTextColor().withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Conditional Disposition Selection Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    _isCallConnected ? Icons.phone_in_talk_rounded : Icons.phone_missed_rounded,
                    size: 18,
                    color: _isCallConnected ? Colors.green : Colors.amber.shade900,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _isCallConnected ? 'Connected Outcomes' : 'Not Connected Outcomes',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                onPressed: () {
                  setState(() {
                    _overrideShowConnected = !_isCallConnected;
                    if (_isCallConnected) {
                      _selectedDisposition = 'CONNECTED_INTERESTED';
                    } else {
                      _selectedDisposition = 'NOT_CONNECTED_BUSY';
                    }
                  });
                },
                icon: const Icon(Icons.swap_horiz, size: 16),
                label: Text(
                  _isCallConnected ? 'Show Unconnected' : 'Show Connected',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Smart Voicemail Detection Banner for short connected calls (1-18s)
          if (_isCallConnected && _durationSeconds > 0 && _durationSeconds <= 18) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.deepPurple.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.deepPurple.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.voicemail_rounded, size: 20, color: Colors.deepPurple),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Short call (${_durationSeconds}s). Was this an automated Voicemail / IVR?',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.deepPurple,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      backgroundColor: _selectedDisposition == 'VOICEMAIL'
                          ? Colors.deepPurple
                          : Colors.deepPurple.withValues(alpha: 0.2),
                      foregroundColor: _selectedDisposition == 'VOICEMAIL'
                          ? Colors.white
                          : Colors.deepPurple,
                    ),
                    onPressed: () {
                      setState(() {
                        _selectedDisposition = 'VOICEMAIL';
                      });
                    },
                    child: const Text('Mark Voicemail', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ],

          // Filtered Choice Chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: (_isCallConnected ? _connectedOptions : _unconnectedOptions).map((opt) {
              final isSelected = _selectedDisposition == opt['id'];
              final color = opt['color'] as Color;
              return ChoiceChip(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      opt['icon'] as IconData,
                      size: 16,
                      color: isSelected ? Colors.white : color,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      opt['label'] as String,
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? Colors.white : Colors.black87,
                      ),
                    ),
                  ],
                ),
                selected: isSelected,
                selectedColor: color,
                backgroundColor: colorScheme.surface,
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
          const SizedBox(height: 10),

          // Follow-up Date Time picker if disposition is FOLLOWUP
          if (_selectedDisposition == 'CONNECTED_FOLLOWUP') ...[
            Card(
              color: Colors.orange.withValues(alpha: 0.08),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.orange.shade300),
              ),
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.event_available, color: Colors.orange),
                title: Text(
                  _followupDateTime != null
                      ? 'Follow-up: ${_followupDateTime!.day}/${_followupDateTime!.month}/${_followupDateTime!.year} at ${_followupDateTime!.hour.toString().padLeft(2, '0')}:${_followupDateTime!.minute.toString().padLeft(2, '0')}'
                      : 'Schedule Follow-up Date & Time',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                trailing: const Icon(Icons.edit_calendar, color: Colors.orange, size: 20),
                onTap: _pickFollowupDateTime,
              ),
            ),
            const SizedBox(height: 10),
          ],

          // Quick Remarks Chips
          const Text('Quick Remarks', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey)),
          const SizedBox(height: 4),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _quickRemarks.map((remark) {
                return Padding(
                  padding: const EdgeInsets.only(right: 6.0),
                  child: ActionChip(
                    label: Text(remark, style: const TextStyle(fontSize: 11)),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    visualDensity: VisualDensity.compact,
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
            maxLines: 2,
            decoration: InputDecoration(
              isDense: true,
              labelText: 'Telecaller Remarks / Notes',
              hintText: 'Enter feedback, loan interest, objections...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    ),
  );
}

  Color _getTimingTierBgColor() {
    switch (_timingClassification) {
      case 'CONNECTED_CONVERSATION':
        return Colors.green.withValues(alpha: 0.1);
      case 'CONNECTED_SHORT':
        return Colors.amber.withValues(alpha: 0.1);
      case 'VOICEMAIL':
        return Colors.deepPurple.withValues(alpha: 0.1);
      case 'NOT_CONNECTED':
      default:
        return Colors.blueGrey.withValues(alpha: 0.08);
    }
  }

  Color _getTimingTierBorderColor() {
    switch (_timingClassification) {
      case 'CONNECTED_CONVERSATION':
        return Colors.green.shade400;
      case 'CONNECTED_SHORT':
        return Colors.amber.shade400;
      case 'VOICEMAIL':
        return Colors.deepPurple.shade300;
      case 'NOT_CONNECTED':
      default:
        return Colors.blueGrey.shade300;
    }
  }

  Color _getTimingTierTextColor() {
    switch (_timingClassification) {
      case 'CONNECTED_CONVERSATION':
        return Colors.green.shade900;
      case 'CONNECTED_SHORT':
        return Colors.amber.shade900;
      case 'VOICEMAIL':
        return Colors.deepPurple.shade900;
      case 'NOT_CONNECTED':
      default:
        return Colors.blueGrey.shade800;
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
    return _hasCallOccurred ? 'Call Not Connected (0s)' : 'Ready for Call (Not Dialed)';
  }
}
