import 'dart:convert';
import 'dart:developer';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:phone_state_background/phone_state_background.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:callnow_new/services/config_service.dart';
import 'package:callnow_new/services/permission_service.dart';

/// Model representing verified Android CallLog entry for a dialed number
class VerifiedCallLog {
  final bool isDialed;
  final bool hasPermission;
  final String number;
  final int durationSeconds;
  final int timestamp;
  final int type;
  final String? error;

  VerifiedCallLog({
    required this.isDialed,
    this.hasPermission = true,
    required this.number,
    required this.durationSeconds,
    required this.timestamp,
    required this.type,
    this.error,
  });

  /// Check if call duration is between 1s and 18s (classic automated voicemail / carrier IVR)
  bool get isVoicemailLikely => isDialed && durationSeconds > 0 && durationSeconds <= 18;

  String get durationFormatted {
    if (durationSeconds < 60) return '${durationSeconds}s';
    final m = durationSeconds ~/ 60;
    final s = durationSeconds % 60;
    return '${m}m ${s}s';
  }

  factory VerifiedCallLog.fromMap(Map<dynamic, dynamic> map) {
    return VerifiedCallLog(
      isDialed: map['isDialed'] == true,
      hasPermission: map['hasPermission'] ?? true,
      number: (map['number'] ?? '').toString(),
      durationSeconds: (map['duration'] as num?)?.toInt() ?? 0,
      timestamp: (map['timestamp'] as num?)?.toInt() ?? 0,
      type: (map['type'] as num?)?.toInt() ?? 0,
      error: map['error']?.toString(),
    );
  }
}

/// Model for active call tracking session with spoken duration classification
class CallSessionEvent {
  final String number;
  final int durationSeconds;
  final String timingClassification; // 'NOT_CONNECTED', 'CONNECTED_SHORT', 'CONNECTED_CONVERSATION'
  final DateTime startTime;
  final DateTime endTime;

  CallSessionEvent({
    required this.number,
    required this.durationSeconds,
    required this.timingClassification,
    required this.startTime,
    required this.endTime,
  });

  String get durationFormatted {
    if (durationSeconds < 60) return '${durationSeconds}s';
    final m = durationSeconds ~/ 60;
    final s = durationSeconds % 60;
    return '${m}m ${s}s';
  }

  String get timingTierLabel {
    switch (timingClassification) {
      case 'CONNECTED_CONVERSATION':
        return 'Connected (Conversation)';
      case 'CONNECTED_SHORT':
        return 'Connected (Short Call)';
      case 'VOICEMAIL':
        return 'Voicemail / Automated Machine';
      case 'NOT_CONNECTED':
      default:
        return 'Not Connected / Missed';
    }
  }
}

/// Top-level background callback required by phone_state_background.
/// Must be annotated with @pragma('vm:entry-point') to prevent tree-shaking in release builds.
@pragma('vm:entry-point')
Future<void> phoneStateBackgroundCallbackHandler(
  PhoneStateBackgroundEvent event,
  String number,
  int duration,
) async {
  final now = DateTime.now();
  log('[CallTracker] Event: $event | Number: $number | Duration: ${duration}s at $now');

  // Update in-memory status if the app isolate is active
  CallTrackingService.lastCallEvent.value =
      '${event.name.toUpperCase()} ($number, ${duration}s)';

  switch (event) {
    case PhoneStateBackgroundEvent.outgoingstart:
      log('[CallTracker] Outgoing call started to: $number');
      CallTrackingService.markCallStarted(number);
      break;

    case PhoneStateBackgroundEvent.outgoingend:
      log('[CallTracker] Outgoing call ended to: $number, duration: $duration s');
      CallTrackingService.markCallEnded(number, duration);
      await CallTrackingService._syncCallActivityBackground(
        number: number,
        duration: duration,
        direction: 'OUTGOING',
        status: duration > 0 ? 'Connected' : 'Missed/Cancelled',
      );
      break;

    case PhoneStateBackgroundEvent.incomingstart:
      log('[CallTracker] Incoming call ringing from: $number');
      break;

    case PhoneStateBackgroundEvent.incomingreceived:
      log('[CallTracker] Incoming call answered from: $number');
      break;

    case PhoneStateBackgroundEvent.incomingmissed:
      log('[CallTracker] Incoming call missed from: $number');
      await CallTrackingService._syncCallActivityBackground(
        number: number,
        duration: 0,
        direction: 'INCOMING',
        status: 'Missed',
      );
      break;

    case PhoneStateBackgroundEvent.incomingend:
      log('[CallTracker] Incoming call ended from: $number, duration: $duration s');
      await CallTrackingService._syncCallActivityBackground(
        number: number,
        duration: duration,
        direction: 'INCOMING',
        status: 'Received',
      );
      break;
  }
}

class CallTrackingService {
  static final ValueNotifier<bool> isTrackingActive = ValueNotifier<bool>(false);
  static final ValueNotifier<String> lastCallEvent =
      ValueNotifier<String>('Waiting for call activity...');
  static final ValueNotifier<int> totalCallsTracked = ValueNotifier<int>(0);

  /// Live notifier for active calling desk session
  static final ValueNotifier<CallSessionEvent?> activeCallSession =
      ValueNotifier<CallSessionEvent?>(null);

  static DateTime? _currentCallStartTime;
  static String? _currentCallNumber;

  /// Mark outgoing call started
  static void markCallStarted(String number) {
    _currentCallNumber = number;
    _currentCallStartTime = DateTime.now();
    lastCallEvent.value = 'CALLING ($number)';
  }

  /// Mark outgoing call ended with duration and auto-classify timing tier
  static void markCallEnded(String number, int duration) {
    final now = DateTime.now();
    final start = _currentCallStartTime ?? now.subtract(Duration(seconds: duration));
    final num = number.isNotEmpty ? number : (_currentCallNumber ?? '');

    String tier = 'NOT_CONNECTED';
    if (duration > 20) {
      tier = 'CONNECTED_CONVERSATION';
    } else if (duration > 0) {
      tier = 'CONNECTED_SHORT';
    }

    final session = CallSessionEvent(
      number: num,
      durationSeconds: duration,
      timingClassification: tier,
      startTime: start,
      endTime: now,
    );

    activeCallSession.value = session;
    lastCallEvent.value = 'ENDED ($num, ${duration}s - $tier)';
    _currentCallStartTime = null;
    _currentCallNumber = null;
  }

  /// Check if the required Android permissions (READ_PHONE_STATE, READ_CALL_LOG) are granted
  static Future<bool> checkPermission() async {
    return await PermissionService.hasAllPermissions();
  }

  /// Request required Android permissions
  static Future<bool> requestPermissions() async {
    final report = await PermissionService.requestAllPermissions();
    return report.allGranted;
  }

  /// Initialize the background listener service
  static Future<bool> initialize() async {
    try {
      bool hasPermission = await checkPermission();
      if (!hasPermission) {
        await requestPermissions();
        hasPermission = await checkPermission();
      }

      if (!hasPermission) {
        log('[CallTracker] Permissions not granted. Cannot initialize call tracker.');
        isTrackingActive.value = false;
        return false;
      }

      if (PermissionService.isMockActive || kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
        isTrackingActive.value = true;
        return true;
      }

      await PhoneStateBackground.initialize(phoneStateBackgroundCallbackHandler);
      isTrackingActive.value = true;
      log('[CallTracker] Successfully initialized background phone state listener.');
      return true;
    } catch (e) {
      log('[CallTracker] Initialization error: $e');
      isTrackingActive.value = false;
      return false;
    }
  }

  /// Sync call records to backend API (new submit_call.php endpoint with Bearer token)
  static Future<void> _syncCallActivityBackground({
    required String number,
    required int duration,
    required String direction,
    required String status,
  }) async {
    totalCallsTracked.value++;
    try {
      // Read token from SharedPreferences directly (background isolate)
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      final baseUrl = prefs.getString('base_url') ?? ConfigService.defaultBaseUrl;

      if (token == null) {
        log('[CallTracker] No auth token found. Cannot sync call activity.');
        return;
      }

      // Determine source based on number format or use a default
      final source = _determineSource(number);
      
      // For the new API, we need a record_id. Since we only have the phone number,
      // we'll use the direct submit endpoint which accepts record_id
      // For now, we'll use a lookup approach - but the API requires record_id
      // We'll use the phone number as record_id for temporary records, 
      // or we can search for the record first
      
      final response = await http.post(
        Uri.parse('$baseUrl/telecaller/submit_call.php'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'record_id': number, // Using phone number as identifier
          'source': source,
          'call_status': status,
          'call_duration': duration,
          'notes': 'Auto-logged via background call tracking',
          'next_followup': null,
          'recording_url': null,
        }),
      );
      log('[CallTracker] Sync response code: ${response.statusCode} - ${response.body}');
    } catch (e) {
      log('[CallTracker] Failed to sync call activity to API: $e');
    }
  }

  /// Determine database source from phone number format
  static String _determineSource(String number) {
    // Default to temporary database for auto-logged calls
    return 'temporary';
  }

  /// Sync call activity from foreground (with full context)
  static Future<void> syncCallActivity({
    required String number,
    required int duration,
    required String direction,
    required String status,
    int? recordId,
    String? source,
    String? notes,
  }) async {
    totalCallsTracked.value++;
    try {
      final token = ConfigService.token;
      final baseUrl = ConfigService.baseUrl;

      if (token == null) {
        log('[CallTracker] No auth token. Cannot sync call activity.');
        return;
      }

      final src = source ?? _determineSource(number);
      final rid = recordId ?? int.tryParse(number.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

      final response = await http.post(
        Uri.parse('$baseUrl/telecaller/submit_call.php'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'record_id': rid,
          'source': src.toUpperCase(),
          'call_status': status,
          'call_duration': duration,
          'notes': notes ?? 'Auto-logged via background call tracking',
          'next_followup': null,
          'recording_url': null,
        }),
      );
      log('[CallTracker] Sync response code: ${response.statusCode} - ${response.body}');
    } catch (e) {
      log('[CallTracker] Failed to sync call activity to API: $e');
    }
  }

  /// Helper to trigger a phone call via the system dialer
  static Future<bool> makePhoneCall(String phoneNumber) async {
    final cleanNumber = phoneNumber.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri(scheme: 'tel', path: cleanNumber);
    try {
      if (await canLaunchUrl(uri)) {
        markCallStarted(cleanNumber);
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        log('[CallTracker] Could not launch tel: uri for $cleanNumber');
        return false;
      }
    } catch (e) {
      log('[CallTracker] Error launching dialer: $e');
      return false;
    }
  }

  static const MethodChannel _verifierChannel = MethodChannel('com.example.callnow/call_verifier');

  /// Query native Android CallLog to verify if an outgoing call was placed to [phoneNumber]
  static Future<VerifiedCallLog> verifyCallLog(String phoneNumber, {int? afterTimestamp}) async {
    try {
      final res = await _verifierChannel.invokeMethod('getLatestCallLog', {
        'phoneNumber': phoneNumber,
        'afterTimestamp': afterTimestamp ?? 0,
      });
      if (res is Map) {
        return VerifiedCallLog.fromMap(res);
      }
    } catch (e) {
      log('[CallTracker] verifyCallLog error: $e');
    }
    return VerifiedCallLog(
      isDialed: false,
      number: phoneNumber,
      durationSeconds: 0,
      timestamp: 0,
      type: 0,
      error: 'CHANNEL_ERROR',
    );
  }

  /// Helper to trigger WhatsApp chat with pre-filled text
  static Future<bool> openWhatsApp(String phoneNumber, {String message = ''}) async {
    final cleanNumber = phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
    final whatsappUrl = Uri.parse(
      'https://wa.me/$cleanNumber${message.isNotEmpty ? '?text=${Uri.encodeComponent(message)}' : ''}',
    );
    try {
      if (await canLaunchUrl(whatsappUrl)) {
        return await launchUrl(whatsappUrl, mode: LaunchMode.externalApplication);
      } else {
        log('[CallTracker] Could not launch WhatsApp uri for $cleanNumber');
        return false;
      }
    } catch (e) {
      log('[CallTracker] Error launching WhatsApp: $e');
      return false;
    }
  }
}