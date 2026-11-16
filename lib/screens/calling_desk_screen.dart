import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:callnow_new/constants/lead_stages.dart';
import 'package:callnow_new/screens/call_reports_screen.dart';
import 'package:callnow_new/services/api_service.dart';
import 'package:callnow_new/services/call_tracking_service.dart';
import 'package:callnow_new/services/calling_preferences_service.dart';
import 'package:callnow_new/services/config_service.dart';
import 'package:callnow_new/services/followup_service.dart';
import 'package:callnow_new/services/whatsapp_message_service.dart';

class CallingDeskScreen extends StatefulWidget {
  final VoidCallback? onOpenReports;
  const CallingDeskScreen({super.key, this.onOpenReports});

  static final Set<String> _sessionProcessedLeadIds = {};

  static void resetSessionQueue() => _sessionProcessedLeadIds.clear();

  @visibleForTesting
  static void clearSessionProcessedLeads() => _sessionProcessedLeadIds.clear();

  @visibleForTesting
  static Set<String> get sessionProcessedLeadIds => Set.unmodifiable(_sessionProcessedLeadIds);

  static void markLeadProcessed(String id) {
    if (id.isNotEmpty) _sessionProcessedLeadIds.add(id);
  }

  static String getLeadIdentifier(Map<String, dynamic> lead) {
    final id = lead['id']?.toString().trim();
    if (id != null && id.isNotEmpty && id != '0') return id;
    final leadId = lead['lead_id']?.toString().trim();
    if (leadId != null && leadId.isNotEmpty && leadId != '0') return leadId;
    final mobile = lead['mobile']?.toString().trim();
    if (mobile != null && mobile.isNotEmpty) return mobile;
    return '';
  }

  @override
  State<CallingDeskScreen> createState() => CallingDeskScreenState();
}

class CallingDeskScreenState extends State<CallingDeskScreen>
    with WidgetsBindingObserver {
  final List<Map<String, dynamic>> _leads = [];
  int _currentIndex = 0;
  bool _isLoading = true;
  bool _isFetchingMore = false;
  bool _isSubmitting = false;
  String? _errorMessage;

  /// Bucket tracking — 15 calls per fill, valid for 15 minutes only.
  DateTime? _bucketFilledAt;
  static const Duration _bucketExpiryDuration = Duration(minutes: 15);

  /// True when the current bucket has expired (15 minutes since last fill).
  bool get _isBucketExpired {
    if (_bucketFilledAt == null) return true;
    return DateTime.now().difference(_bucketFilledAt!) >= _bucketExpiryDuration;
  }

  /// True when there are leads in the queue that haven't been submitted/skipped yet.
  bool get _hasUncompletedCalls {
    if (_leads.isEmpty) return false;
    // Current lead or any remaining leads ahead are uncompleted
    return _currentIndex < _leads.length;
  }

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

  @visibleForTesting
  bool get isCallConnected => _durationSeconds > 0;

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

  static const Map<String, dynamic> _voicemailOption = {
    'id': 'IVR_VOICEMAIL',
    'label': 'IVR / Voicemail',
    'serverStatus': 'IVR / Voicemail',
    'icon': Icons.voicemail_rounded,
    'color': Colors.deepPurple,
  };

  List<Map<String, dynamic>> get _allDispositionOptions => [
        ..._connectedOptions,
        ..._unconnectedOptions,
        _voicemailOption,
      ];

  final List<String> _quickRemarks = [
    'DND / Do not call',
    'Callback later',
    'Sent brochure on WA',
    'Needs loan urgently',
    'Busy in meeting',
    'Wrong person',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ConfigService.registerLogoutCallback(CallingDeskScreen.clearSessionProcessedLeads);
    _startInactivityTimer();
    _loadInitialBatch();
    CallTrackingService.activeCallSession.addListener(_onCallSessionDetected);
  }

  @visibleForTesting
  List<Map<String, dynamic>> get leads => _leads;

  @visibleForTesting
  int get currentIndex => _currentIndex;

  @visibleForTesting
  String get selectedDisposition => _selectedDisposition;

  @visibleForTesting
  TextEditingController get notesController => _notesController;

  @visibleForTesting
  Future<void> refreshBatchForTesting() => _refreshBatch();

  @visibleForTesting
  void setVerifiedCallLogForTesting(VerifiedCallLog? log) {
    setState(() {
      _verifiedCallLog = log;
      _showOutcomes = log != null;
      if (log != null) {
        _durationSeconds = log.durationSeconds;
        if (log.durationSeconds == 0) {
          _selectedDisposition = 'RINGING';
        } else if (log.isVoicemailLikely) {
          _selectedDisposition = '';
        } else {
          _selectedDisposition = 'NOT_INTERESTED';
        }
      }
    });
  }

  @visibleForTesting
  Future<void> skipLeadForTesting() => _skipLead();

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
      CallingPreferencesService.triggerCallEndVibration();
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
            } else if (verified.isVoicemailLikely) {
              _selectedDisposition = '';
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

    // If forced refresh but we have an active lead in-progress, delegate to _refreshBatch to preserve state
    if (force && _currentLead != null) {
      await _refreshBatch();
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final batch = await ApiService.getBatchLeads(limit: 15);
      final freshBatch = batch.where((item) {
        final id = CallingDeskScreen.getLeadIdentifier(item);
        return id.isEmpty || !CallingDeskScreen._sessionProcessedLeadIds.contains(id);
      }).toList();

      if (mounted) {
        setState(() {
          _leads.clear();
          _leads.addAll(freshBatch);
          _currentIndex = 0;
          _isLoading = false;
          _bucketFilledAt = DateTime.now(); // Mark when this 15-call bucket was filled
          _resetFormForCurrentLead();
        });
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

  Future<void> _refreshBatch() async {
    // Queue empty — fill with a fresh bucket of 15
    if (_leads.isEmpty) {
      await _loadInitialBatch(force: true);
      return;
    }

    // If bucket hasn't expired and there are uncompleted calls, block the refresh
    if (!_isBucketExpired && _hasUncompletedCalls) {
      if (mounted) {
        final remainingMinutes =
            (_bucketExpiryDuration.inSeconds -
                    DateTime.now().difference(_bucketFilledAt!).inSeconds)
                .clamp(0, _bucketExpiryDuration.inSeconds) ~/
            60;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Complete your current calls before refreshing. '
                    'Bucket expires in ~$remainingMinutes min.',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFFF59E0B),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    // Bucket expired — clear completed queue and refill with a fresh bucket of 15
    try {
      final batch = await ApiService.getBatchLeads(limit: 15);

      final freshBatch = batch.where((item) {
        final id = CallingDeskScreen.getLeadIdentifier(item);
        return id.isEmpty || !CallingDeskScreen._sessionProcessedLeadIds.contains(id);
      }).toList();

      if (mounted) {
        setState(() {
          _leads.clear();
          _leads.addAll(freshBatch);
          _currentIndex = 0;
          _bucketFilledAt = DateTime.now(); // New bucket fill time
          _resetFormForCurrentLead();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.refresh, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'New bucket of 15 calls loaded (valid for 15 minutes).',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            backgroundColor: Color(0xFF0F766E),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to refresh batch: ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _fetchMoreLeads() async {
    if (_isFetchingMore) return;
    setState(() => _isFetchingMore = true);

    try {
      final batch = await ApiService.getBatchLeads(limit: 15);
      if (mounted) {
        final existingIdentifiers = <String>{};
        for (final l in _leads) {
          final id = CallingDeskScreen.getLeadIdentifier(l);
          if (id.isNotEmpty) existingIdentifiers.add(id);
        }
        final newLeads = batch.where((lead) {
          final id = CallingDeskScreen.getLeadIdentifier(lead);
          if (id.isEmpty) return true;
          return !CallingDeskScreen._sessionProcessedLeadIds.contains(id) &&
              !existingIdentifiers.contains(id);
        }).toList();

        setState(() {
          _leads.addAll(newLeads);
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
      final bool isShort = _durationSeconds > 0 && _durationSeconds <= 18;
      setState(() {
        _showOutcomes = true;
        if (!isConnected) {
          _selectedDisposition = 'RINGING';
        } else if (isShort) {
          _selectedDisposition = '';
        } else {
          _selectedDisposition = 'NOT_INTERESTED';
        }
      });

      // Bottom floating pill toast — compact, no overflow
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          elevation: 0,
          backgroundColor: Colors.transparent,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          // Tight horizontal margin so the pill never exceeds screen width
          margin: const EdgeInsets.only(bottom: 24, left: 48, right: 48),
          padding: EdgeInsets.zero,
          content: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
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
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: !isConnected
                        ? const Color(0xFFFFEDD5)
                        : (isShort
                            ? const Color(0xFFFEF3C7)
                            : const Color(0xFFDCFCE7)),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    !isConnected
                        ? Icons.phone_missed_rounded
                        : (isShort
                            ? Icons.phone_in_talk_rounded
                            : Icons.call_made_rounded),
                    size: 13,
                    color: !isConnected
                        ? const Color(0xFFEA580C)
                        : (isShort
                            ? const Color(0xFFD97706)
                            : const Color(0xFF16A34A)),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    !isConnected
                        ? '✗ Not Connected'
                        : (isShort
                            ? '📞 Short Call (${_durationSeconds}s)'
                            : '✓ Connected'),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E293B),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
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

    if (await CallingPreferencesService.isAutoCopyNumberEnabled()) {
      Clipboard.setData(ClipboardData(text: mobile));
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
    String msg = '';
    try {
      if (await WhatsAppMessageService.isIntroEnabled()) {
        final template = await WhatsAppMessageService.loadTemplate();
        final name = (lead['name'] ?? 'Client').toString();
        msg = WhatsAppMessageService.personalize(template, name);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load WhatsApp message: $error')),
        );
      }
      return;
    }

    final launched = await CallTrackingService.openWhatsApp(mobile, message: msg);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open WhatsApp or WhatsApp Business.')),
      );
    }
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
    if (package.isEmpty) return 'RS. 0 LACS';
    final cleaned = package.replaceAll(RegExp(r'[^\d.]'), '');
    final numVal = double.tryParse(cleaned);
    if (numVal != null && numVal > 0) {
      if (numVal >= 10000000) {
        return 'RS. ${(numVal / 10000000).toStringAsFixed(2)} CR';
      } else if (numVal >= 100000) {
        return 'RS. ${(numVal / 100000).toStringAsFixed(2)} LACS';
      }
      return 'RS. ${numVal.toInt()}';
    }
    final upper = package.toUpperCase().replaceAll('₹', 'RS. ').trim();
    return upper.startsWith('RS.') ? upper : 'RS. $upper';
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

  Future<void> _skipLead() async {
    final lead = _currentLead;
    if (lead == null) return;

    final bool isDialed = _verifiedCallLog != null && _verifiedCallLog!.isDialed;
    final bool hasNotes = _notesController.text.trim().isNotEmpty;

    if (isDialed || hasNotes) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFF59E0B), size: 24),
              SizedBox(width: 8),
              Text('Discard Call Details?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Text(
            isDialed
                ? 'You placed a call (${_durationSeconds}s) to this contact. Skipping without submitting will discard the call record for this session. Are you sure you want to skip?'
                : 'You have entered notes for this contact. Skipping will discard your notes. Are you sure you want to skip?',
            style: const TextStyle(fontSize: 14, color: Color(0xFF334155)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Discard & Skip'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
    }

    final leadId = CallingDeskScreen.getLeadIdentifier(lead);
    CallingDeskScreen.markLeadProcessed(leadId);

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
      setState(() {
        _currentIndex++;
        _resetFormForCurrentLead();
      });
      _loadInitialBatch(force: true);
    }
  }

  void _showEngagementFeedback(Map<String, dynamic>? result, {String? fallbackMessage}) {
    if (result != null && result['engagement'] != null) {
      final dynamic rawEng = result['engagement'];
      final Map<String, dynamic> eng = rawEng is Map<String, dynamic>
          ? rawEng
          : (rawEng is Map ? Map<String, dynamic>.from(rawEng) : {});
      final xpEarned = (eng['xp_earned'] as num?)?.toInt() ?? int.tryParse(eng['xp_earned']?.toString() ?? '0') ?? 0;
      final bonusXp = (eng['target_bonus_xp'] as num?)?.toInt() ?? int.tryParse(eng['target_bonus_xp']?.toString() ?? '0') ?? 0;
      if (mounted && xpEarned > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.deepPurple.shade900,
            duration: const Duration(seconds: 2),
            content: Row(
              children: [
                const Icon(Icons.stars, color: Colors.amberAccent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    bonusXp > 0
                        ? '🎯 Target Hit! +$xpEarned XP (Bonus included!)'
                        : '+$xpEarned XP Earned!',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        );
        return;
      }
    }

    if (fallbackMessage != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(fallbackMessage),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _submitAndNext() async {
    final lead = _currentLead;
    if (lead == null) return;

    if (_selectedDisposition.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Please select a call outcome before saving.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.red.shade800,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    final wasInterested = _selectedDisposition == 'ENQUIRY_INTERESTED';
    final currentLeadSnapshot = Map<String, dynamic>.from(lead);
    final currentRemarksSnapshot = _notesController.text.trim();

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

    final effectiveTiming = _selectedDisposition == 'IVR_VOICEMAIL'
        ? 'VOICEMAIL'
        : (isConnectedOutcome
            ? (verifiedDur > 20 ? 'CONNECTED_CONVERSATION' : 'CONNECTED_SHORT')
            : 'NOT_CONNECTED');

    // Auto-schedule callback 2 hours later if CallBack/Busy was selected without explicit preset
    if (_selectedDisposition == 'CALLBACK_BUSY' && _followupDateTime == null) {
      _followupDateTime = DateTime.now().add(const Duration(hours: 2));
    }

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
          clientContactId: int.tryParse(leadId.toString()),
          source: source,
        );
      } catch (e) {
        debugPrint('Error saving local followup: $e');
      }
    }

    // When customer is interested, capture loan qualification and convert Contact to Lead
    if (wasInterested) {
      _showCreateLeadModal(
        leadData: currentLeadSnapshot,
        initialRemarks: currentRemarksSnapshot,
        verifiedDur: verifiedDur,
        effectiveTiming: effectiveTiming,
        followupIso: followupIso,
        statusLabel: statusLabel,
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final result = await ApiService.submitCallResult(
        callId: leadId,
        source: source,
        status: statusLabel,
        notes: _notesController.text.trim().isNotEmpty ? _notesController.text.trim() : null,
        durationSeconds: verifiedDur,
        timingClassification: effectiveTiming,
        nextFollowupAt: followupIso,
        loanQualification: null, // Strictly Client Contact!
        phoneNumber: lead['mobile']?.toString(),
      );

      if (mounted) {
        final leadIdentifier = CallingDeskScreen.getLeadIdentifier(lead);
        CallingDeskScreen.markLeadProcessed(leadIdentifier);

        final followupNotice = _followupDateTime != null
            ? ' (⏰ Callback set for ${_followupDateTime!.day}/${_followupDateTime!.month} ${_followupDateTime!.hour.toString().padLeft(2, '0')}:${_followupDateTime!.minute.toString().padLeft(2, '0')})'
            : '';

        _showEngagementFeedback(
          result,
          fallbackMessage: 'Call saved: $statusLabel for ${lead['name']}$followupNotice',
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

  /// Opens the Create CRM Lead modal pre-filled with the current prospect's details
  void _showCreateLeadModal({
    required Map<String, dynamic> leadData,
    String? initialRemarks,
    int? verifiedDur,
    String? effectiveTiming,
    String? followupIso,
    String? statusLabel,
  }) {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: leadData['name']?.toString() ?? '');

    // Format 10-digit mobile number cleanly
    String rawMobile = leadData['mobile']?.toString() ?? '';
    final digits = rawMobile.replaceAll(RegExp(r'\D'), '');
    final cleanMobile = digits.length > 10 ? digits.substring(digits.length - 10) : digits;
    final mobileCtrl = TextEditingController(text: cleanMobile);

    final companyCtrl = TextEditingController(
      text: (leadData['company'] != null && leadData['company'] != 'Individual')
          ? leadData['company'].toString()
          : '',
    );
    final amountCtrl = TextEditingController(text: leadData['package']?.toString() ?? '');
    final salaryCtrl = TextEditingController();
    final salaryAccountCtrl = TextEditingController();
    final bankCtrl = TextEditingController();
    final remarksCtrl = TextEditingController(
      text: (initialRemarks != null && initialRemarks.isNotEmpty)
          ? initialRemarks
          : (leadData['other_info']?.toString() ?? ''),
    );

    String selectedLoanType = LeadStageHelper.loanTypes.contains(leadData['loan_type'])
        ? leadData['loan_type'].toString()
        : LeadStageHelper.loanTypes.first;
    String selectedStage = 'LEAD';
    String selectedPriority = 'High';
    String selectedTemp = 'Hot';
    bool isModalSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (modalCtx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
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
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDCFCE7),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.person_add_alt_1_rounded, color: Color(0xFF16A34A), size: 22),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Loan Qualification & Lead Conversion',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                Text(
                                  'Customer interested — capture details and convert to Lead',
                                  style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
                            onPressed: () => Navigator.pop(modalCtx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      const Divider(height: 1),
                      const SizedBox(height: 14),

                      // Customer Full Name
                      TextFormField(
                        controller: nameCtrl,
                        decoration: InputDecoration(
                          labelText: 'Customer Full Name *',
                          prefixIcon: const Icon(Icons.person_outline, size: 20),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          isDense: true,
                        ),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Name is required' : null,
                      ),
                      const SizedBox(height: 11),

                      // 10-Digit Mobile Number
                      TextFormField(
                        controller: mobileCtrl,
                        keyboardType: TextInputType.phone,
                        maxLength: 10,
                        decoration: InputDecoration(
                          labelText: '10-Digit Mobile Number *',
                          prefixIcon: const Icon(Icons.phone_outlined, size: 20),
                          prefixText: '+91 ',
                          counterText: '',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          isDense: true,
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Mobile is required';
                          final clean = v.replaceAll(RegExp(r'\D'), '');
                          if (clean.length != 10) return 'Must be 10 digits';
                          return null;
                        },
                      ),
                      const SizedBox(height: 11),

                      // Employer / Company & Loan Package Row
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: companyCtrl,
                              decoration: InputDecoration(
                                labelText: 'Company / Employer',
                                prefixIcon: const Icon(Icons.business_outlined, size: 20),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: amountCtrl,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: 'Required Loan (₹) *',
                                prefixIcon: const Icon(Icons.currency_rupee, size: 20),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                isDense: true,
                              ),
                              validator: (v) => v == null || v.trim().isEmpty ? 'Loan amount is required' : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 11),

                      // Monthly Net Salary & Salary Bank Row
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: salaryCtrl,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: 'Net Monthly Salary (₹)',
                                prefixIcon: const Icon(Icons.account_balance_wallet_outlined, size: 20),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: salaryAccountCtrl,
                              decoration: InputDecoration(
                                labelText: 'Salary Account Bank',
                                prefixIcon: const Icon(Icons.account_balance_outlined, size: 20),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 11),

                      // Loan Type & Applied Bank Row
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: selectedLoanType,
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: 'Loan Type *',
                                prefixIcon: const Icon(Icons.category_outlined, size: 20),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                isDense: true,
                              ),
                              items: LeadStageHelper.loanTypes.map((t) {
                                return DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 12.5)));
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) setModalState(() => selectedLoanType = val);
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: bankCtrl,
                              decoration: InputDecoration(
                                labelText: 'Preferred Bank',
                                prefixIcon: const Icon(Icons.storefront_outlined, size: 20),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 11),

                      // Lead Temperature Row
                      DropdownButtonFormField<String>(
                        initialValue: selectedTemp,
                        decoration: InputDecoration(
                          labelText: 'Temperature',
                          prefixIcon: const Icon(Icons.whatshot_rounded, size: 20, color: Colors.deepOrange),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(value: 'Hot', child: Text('🔥 Hot', style: TextStyle(fontSize: 12.5))),
                          DropdownMenuItem(value: 'Warm', child: Text('☀️ Warm', style: TextStyle(fontSize: 12.5))),
                          DropdownMenuItem(value: 'Cold', child: Text('❄️ Cold', style: TextStyle(fontSize: 12.5))),
                        ],
                        onChanged: (val) {
                          if (val != null) setModalState(() => selectedTemp = val);
                        },
                      ),
                      const SizedBox(height: 11),

                      // Notes / Discussion Remarks
                      TextFormField(
                        controller: remarksCtrl,
                        maxLines: 2,
                        decoration: InputDecoration(
                          labelText: 'Notes / Remarks',
                          prefixIcon: const Icon(Icons.notes_rounded, size: 20),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Submit Button
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981), // Emerald green
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: isModalSubmitting
                            ? null
                            : () async {
                                if (!formKey.currentState!.validate()) return;
                                setModalState(() => isModalSubmitting = true);

                                try {
                                  final leadId = int.tryParse(leadData['id'].toString()) ?? 0;
                                  final source = (leadData['source'] ?? 'TEMPORARY').toString();

                                  // Submit call with loan qualification (converts Client Contact -> Lead on server)
                                  final result = await ApiService.submitCallResult(
                                    callId: leadId,
                                    source: source,
                                    status: statusLabel ?? 'Enquiry/ Intrested',
                                    notes: remarksCtrl.text.trim().isNotEmpty ? remarksCtrl.text.trim() : null,
                                    durationSeconds: verifiedDur ?? 0,
                                    timingClassification: effectiveTiming ?? 'CONNECTED_CONVERSATION',
                                    nextFollowupAt: followupIso,
                                    loanQualification: {
                                      'loan_type': selectedLoanType,
                                      'loan_amount': amountCtrl.text.trim(),
                                      'net_salary': salaryCtrl.text.trim(),
                                      'salary_account': salaryAccountCtrl.text.trim(),
                                      'bank_name': bankCtrl.text.trim(),
                                      'stage': selectedTemp,
                                      'priority': selectedPriority,
                                      'lead_status': selectedStage,
                                    },
                                    phoneNumber: leadData['mobile']?.toString(),
                                  );

                                  if (modalCtx.mounted) Navigator.pop(modalCtx);

                                  if (mounted) {
                                    final leadIdentifier = CallingDeskScreen.getLeadIdentifier(leadData);
                                    CallingDeskScreen.markLeadProcessed(leadIdentifier);

                                    _showEngagementFeedback(
                                      result,
                                      fallbackMessage: 'Contact converted to Lead for ${nameCtrl.text.trim()}! Added to pipeline.',
                                    );

                                    setState(() {
                                      _isSubmitting = false;
                                      _currentIndex++;
                                      _resetFormForCurrentLead();
                                    });

                                    if (_leads.length - _currentIndex <= 3) {
                                      _fetchMoreLeads();
                                    }
                                  }
                                } catch (e) {
                                  setModalState(() => isModalSubmitting = false);
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Failed to convert contact: $e'),
                                        backgroundColor: Colors.red.shade700,
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  }
                                }
                              },
                        icon: isModalSubmitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.check_circle_rounded, size: 20),
                        label: Text(
                          isModalSubmitting ? 'Converting Contact...' : 'Convert to Lead & Save',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // No AppBar here — HomeScreen's AppBar is shown on all tabs
      body: _buildBody(),
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
              backgroundColor: const Color(0xFF4CAF50), // Bright green matching screenshots
              foregroundColor: Colors.white,
              elevation: 1.5,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
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
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: _isSubmitting ? null : _skipLead,
          child: const Text(
            'Skip this lead',
            style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Fetching call queue from server...', style: TextStyle(fontSize: 14, color: Color(0xFF64748B))),
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
              const Text(
                'Failed to load contacts',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF64748B)),
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
      // Determine whether we can refill now or must wait for bucket expiry
      final canRefill = _isBucketExpired || _leads.isEmpty;
      final waitText = _bucketFilledAt != null && !_isBucketExpired
          ? 'Bucket expires in ~${((_bucketExpiryDuration.inSeconds - DateTime.now().difference(_bucketFilledAt!).inSeconds).clamp(0, _bucketExpiryDuration.inSeconds) ~/ 60)} min.'
          : '';
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
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
              ),
              const SizedBox(height: 8),
              if (waitText.isNotEmpty)
                Text(
                  waitText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF9A3412), fontWeight: FontWeight.w600, fontSize: 13),
                ),
              if (waitText.isNotEmpty) const SizedBox(height: 8),
              Text(
                canRefill
                    ? 'Tap below to fetch the next batch of 15 calls.'
                    : 'Wait for the bucket to expire before fetching new calls.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: canRefill ? _loadInitialBatch : null,
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
    final otherInfo = (lead['other_info'] ??
            lead['otherInfo'] ??
            lead['notes'] ??
            lead['remarks'] ??
            lead['CUST_OTHER_INFO'] ??
            lead['MAINDATABASE_OTHER_INFO'] ??
            '')
        .toString()
        .trim();

    // Lead count & call status from API
    final callCount = int.tryParse(lead['call_count']?.toString() ?? '0') ?? 0;
    final lastStatus = (lead['last_status'] ?? '').toString().trim();
    final isCalledBefore = callCount > 0;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        FocusScope.of(context).unfocus();
        if (_verifiedCallLog == null || !_verifiedCallLog!.isDialed) {
          _startInactivityTimer();
        }
      },
      child: RefreshIndicator(
        onRefresh: _refreshBatch,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
          child: _buildUnifiedCard(
            name: name,
            mobile: mobile,
            company: company,
            formattedPkg: formattedPkg,
            otherInfo: otherInfo,
            callCount: callCount,
            lastStatus: lastStatus,
            isCalledBefore: isCalledBefore,
          ),
        ),
      ),
    );
  }

  /// Unified contact + actions card — Material white theme matching Dashboard
  Widget _buildUnifiedCard({
    required String name,
    required String mobile,
    required String company,
    required String formattedPkg,
    required String otherInfo,
    required int callCount,
    required String lastStatus,
    required bool isCalledBefore,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Lead counter + call-status badge row ──────────────────────────
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Lead ${_currentIndex + 1} of ${_leads.length}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isCalledBefore
                      ? const Color(0xFFDCFCE7) // green tint = called
                      : const Color(0xFFFFEDD5), // orange tint = not called
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isCalledBefore
                        ? const Color(0xFF86EFAC)
                        : const Color(0xFFFDBA74),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isCalledBefore ? Icons.check_circle_rounded : Icons.phone_missed_rounded,
                      size: 12,
                      color: isCalledBefore
                          ? const Color(0xFF16A34A)
                          : const Color(0xFFEA580C),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isCalledBefore
                          ? 'Called $callCount× · $lastStatus'
                          : 'Not Called',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isCalledBefore
                            ? const Color(0xFF166534)
                            : const Color(0xFF9A3412),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // ── Contact Details Card ──────────────────────────────────────────
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoRow(
                  icon: Icons.person_rounded,
                  label: 'Name',
                  valueWidget: Text(
                    name,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Color(0xFF0F172A),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Divider(height: 16, thickness: 0.5),
                _buildInfoRow(
                  icon: Icons.phone_rounded,
                  label: 'Mobile',
                  valueWidget: Text(
                    mobile,
                    style: const TextStyle(
                      fontSize: 15.5,
                      color: Color(0xFF1E293B),
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                if (company.isNotEmpty && company != 'Individual') ...[
                  const Divider(height: 16, thickness: 0.5),
                  _buildInfoRow(
                    icon: Icons.business_rounded,
                    label: 'Company',
                    valueWidget: Text(
                      company,
                      style: const TextStyle(
                        fontSize: 14.5,
                        color: Color(0xFFEA580C),
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                  ),
                ],
                const Divider(height: 16, thickness: 0.5),
                _buildInfoRow(
                  icon: Icons.currency_rupee_rounded,
                  label: 'Package',
                  valueWidget: Text(
                    formattedPkg,
                    style: const TextStyle(
                      fontSize: 14.5,
                      color: Color(0xFF059669),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (otherInfo.isNotEmpty) ...[
                  const Divider(height: 16, thickness: 0.5),
                  _buildInfoRow(
                    icon: Icons.notes_rounded,
                    label: 'Other Info',
                    valueWidget: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Text(
                        otherInfo,
                        style: const TextStyle(
                          fontSize: 13.5,
                          color: Color(0xFF334155),
                          fontWeight: FontWeight.w500,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // ── Action Buttons Card ───────────────────────────────────────────
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Row: WhatsApp | History | Call
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildCircularActionButton(
                      iconWidget: Image.asset(
                        'assets/images/whatsapp.png',
                        width: 32,
                        height: 32,
                        fit: BoxFit.contain,
                      ),
                      color: const Color(0xFF25D366),
                      tooltip: 'Message on WhatsApp',
                      onTap: _whatsappCurrentLead,
                    ),
                    _buildCircularActionButton(
                      icon: Icons.history_rounded,
                      color: const Color(0xFF78909C),
                      tooltip: "Today's Call History",
                      onTap: () {
                        if (widget.onOpenReports != null) {
                          widget.onOpenReports!();
                        } else {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const CallReportsScreen(
                                initialTabIndex: 1,
                                initialPeriod: 'today',
                              ),
                            ),
                          );
                        }
                      },
                    ),
                    _buildCircularActionButton(
                      icon: Icons.call_rounded,
                      color: const Color(0xFF4CAF50),
                      tooltip: 'Call Now',
                      onTap: _callCurrentLead,
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Get Status button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isCheckingCallLog ? null : _onGetStatusTapped,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF334155),
                      foregroundColor: Colors.white,
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: _isCheckingCallLog
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text(
                            'Get Status',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.2,
                            ),
                          ),
                  ),
                ),

                // Outcomes + Save — shown only after 'Get Status' is tapped
                if (_showOutcomes) ...[
                  const SizedBox(height: 10),
                  _buildDispositionCard(),
                  if (_selectedDisposition == 'CALLBACK_BUSY' || _followupDateTime != null) ...[
                    const SizedBox(height: 10),
                    _buildFollowupCard(),
                  ],
                  const SizedBox(height: 10),
                  _buildRemarksCard(),
                  const SizedBox(height: 10),
                  _buildSaveAndSubmitActions(),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  /// Helper row for contact details — icon + label + value
  Widget _buildInfoRow({
    IconData? icon,
    required String label,
    required Widget valueWidget,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 17, color: const Color(0xFF64748B)),
          const SizedBox(width: 8),
        ],
        SizedBox(
          width: 78,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(child: valueWidget),
      ],
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

  /// 4. Structured Call Disposition & Outcome Card (2x2 Radio Grid + Voicemail matching screenshot)
  Widget _buildDispositionCard() {
    final bool isConnected = _durationSeconds > 0;
    final bool isShort = _durationSeconds > 0 && _durationSeconds <= 18;
    final isConnectedOutcomes = isConnected && !_allowUnconnectedOverrideForShortCalls;
    final options = isConnectedOutcomes ? _connectedOptions : _unconnectedOptions;

    // Header badge styling & text
    Color badgeBg;
    Color badgeFg;
    IconData badgeIcon;
    String badgeText;

    if (!isConnected) {
      badgeBg = const Color(0xFFFFEDD5);
      badgeFg = const Color(0xFFEA580C);
      badgeIcon = Icons.phone_missed_rounded;
      badgeText = '✗ Not Connected';
    } else if (_selectedDisposition == 'IVR_VOICEMAIL') {
      badgeBg = const Color(0xFFF3E8FF);
      badgeFg = const Color(0xFF7E22CE);
      badgeIcon = Icons.voicemail_rounded;
      badgeText = '✗ Not Connected (Voicemail)';
    } else if (isShort && _selectedDisposition.isEmpty) {
      badgeBg = const Color(0xFFFEF3C7);
      badgeFg = const Color(0xFFD97706);
      badgeIcon = Icons.phone_in_talk_rounded;
      badgeText = '📞 Short Call (${_durationSeconds}s) • Choose Outcome';
    } else {
      badgeBg = const Color(0xFFDCFCE7);
      badgeFg = const Color(0xFF16A34A);
      badgeIcon = Icons.call_made_rounded;
      badgeText = '✓ Connected (${_durationSeconds}s)';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC), // Light Material surface
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status Pill Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(badgeIcon, size: 13, color: badgeFg),
                    const SizedBox(width: 6),
                    Text(
                      badgeText,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: badgeFg,
                      ),
                    ),
                  ],
                ),
              ),
              if (isShort)
                InkWell(
                  onTap: () {
                    setState(() {
                      _allowUnconnectedOverrideForShortCalls = !_allowUnconnectedOverrideForShortCalls;
                    });
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Text(
                      _allowUnconnectedOverrideForShortCalls ? 'Show Connected' : 'Show Unconnected',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF2563EB),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

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
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          const SizedBox(height: 10),
          // Dedicated IVR / Voicemail Option (Always accessible)
          _buildRadioOutcomeItem(
            id: _voicemailOption['id'] as String,
            label: _voicemailOption['label'] as String,
            activeColor: Colors.deepPurple,
          ),
        ],
      ),
    );
  }

  Widget _buildRadioOutcomeItem({
    required String id,
    required String label,
    Color? activeColor,
  }) {
    final isSelected = _selectedDisposition == id;
    final primaryColor = activeColor ?? const Color(0xFF26C6DA);

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
                  color: isSelected ? primaryColor : const Color(0xFF94A3B8),
                  width: isSelected ? 2.2 : 1.8,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: primaryColor,
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
                  color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF475569),
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

          // Quick Remarks Chips — short labels, compact wrap
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: _quickRemarks.map((remark) {
              return ActionChip(
                label: Text(
                  remark,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: Color(0xFF334155),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                labelPadding: const EdgeInsets.symmetric(horizontal: 2),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                backgroundColor: const Color(0xFFF1F5F9),
                side: const BorderSide(color: Color(0xFFCBD5E1)),
                onPressed: () {
                  final current = _notesController.text;
                  if (current.isEmpty) {
                    _notesController.text = remark;
                  } else {
                    _notesController.text = '$current | $remark';
                  }
                },
              );
            }).toList(),
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
