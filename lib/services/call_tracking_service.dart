import 'dart:convert';
import 'dart:developer';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:phone_state_background/phone_state_background.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:callnow_new/services/config_service.dart';
import 'package:callnow_new/services/notification_service.dart';
import 'package:callnow_new/services/permission_service.dart';
import 'package:callnow_new/services/secure_http_client.dart';
import 'package:callnow_new/services/today_dialed_history_service.dart';

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
        return 'IVR / Voicemail';
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
      // NOTE: We do not auto-sync outgoing calls to the backend from the background listener.
      // Outgoing calls are initiated from Calling Desk and strictly verified & submitted via
      // CallingDeskScreen._submitAndNext() with user-selected disposition and remarks.
      // Auto-syncing in background caused duplicate CRM submissions and leaked personal calls.
      break;

    case PhoneStateBackgroundEvent.incomingstart:
      log('[CallTracker] Incoming call ringing from: $number');
      break;

    case PhoneStateBackgroundEvent.incomingreceived:
      log('[CallTracker] Incoming call answered from: $number');
      break;

    case PhoneStateBackgroundEvent.incomingmissed:
      log('[CallTracker] Incoming call missed from: $number');
      break;

    case PhoneStateBackgroundEvent.incomingend:
      log('[CallTracker] Incoming call ended from: $number, duration: $duration s');
      if (duration > 0 && number.isNotEmpty) {
        // Strict check: Only store pending post-call if number was dialed today!
        final wasDialed = await TodayDialedHistoryService.instance.wasDialedToday(number);
        if (wasDialed) {
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('pending_post_call_number', number);
            await prefs.setInt('pending_post_call_duration', duration);
            await prefs.setString('pending_post_call_direction', 'INCOMING');
            await prefs.setInt('pending_post_call_time', DateTime.now().millisecondsSinceEpoch);

            // Trigger high priority customer callback alert notification
            final lead = await TodayDialedHistoryService.instance.findDialedCall(number);
            final customerName = lead?['name']?.toString() ?? 'Customer';
            await NotificationService.showInstantAlert(
              title: '📞 Customer Callback Received',
              body: 'Callback from $customerName ($number) connected (${duration}s). Open app to update lead status.',
            );
          } catch (_) {}
        } else {
          log('[CallTracker] Incoming call from $number ignored (not in Today\'s Dialed History).');
        }
      }
      break;
  }
}

class CallTrackingService {
  static final http.Client _httpClient = SecureHttpClient(
    requireHttps: true,
    enablePinning: SslPinningConfig.enabled,
  );

  static final ValueNotifier<bool> isTrackingActive = ValueNotifier<bool>(false);
  static final ValueNotifier<String> lastCallEvent =
      ValueNotifier<String>('Waiting for call activity...');
  static final ValueNotifier<int> totalCallsTracked = ValueNotifier<int>(0);

  /// Live notifier for active calling desk session
  static final ValueNotifier<CallSessionEvent?> activeCallSession =
      ValueNotifier<CallSessionEvent?>(null);

  static DateTime? _currentCallStartTime;
  static String? _currentCallNumber;
  static DateTime? _lastDialTime;

  static DateTime? get lastDialTime => _lastDialTime;
  static int get lastDialTimestamp => _lastDialTime?.millisecondsSinceEpoch ?? 0;

  /// Mark outgoing call started
  static void markCallStarted(String number) {
    _currentCallNumber = number;
    _currentCallStartTime = DateTime.now();
    _lastDialTime = _currentCallStartTime;
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

  /// Determine database source from phone number format
  static String _determineSource(String number) {
    return 'MAIN';
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

      final response = await _httpClient.post(
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

  /// Opens application system settings on Android
  static Future<bool> openAppSettings() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      return await _verifierChannel.invokeMethod<bool>('openAppSettings') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Helper to trigger a phone call via the system dialer
  static Future<bool> makePhoneCall(String phoneNumber) async {
    final cleanNumber = phoneNumber.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri(scheme: 'tel', path: cleanNumber);
    try {
      if (await canLaunchUrl(uri)) {
        _lastDialTime = DateTime.now();
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
    final effectiveTimestamp = afterTimestamp ?? (_lastDialTime != null ? _lastDialTime!.millisecondsSinceEpoch : 0);
    try {
      final res = await _verifierChannel.invokeMethod('getLatestCallLog', {
        'phoneNumber': phoneNumber,
        'afterTimestamp': effectiveTimestamp,
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
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        return await _verifierChannel.invokeMethod<bool>('openWhatsApp', {
              'phoneNumber': cleanNumber,
              'message': message,
            }) ??
            false;
      }

      final whatsappUrl = Uri.parse(
        'https://wa.me/$cleanNumber${message.isNotEmpty ? '?text=${Uri.encodeComponent(message)}' : ''}',
      );
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

  /// Query recent calls from native Android CallLog
  static Future<List<Map<String, dynamic>>> getRecentCallLogs({
    int limit = 15,
    int afterTimestamp = 0,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return [];
    try {
      final res = await _verifierChannel.invokeMethod('getRecentCallLogs', {
        'limit': limit,
        'afterTimestamp': afterTimestamp,
      });
      if (res is List) {
        return res.map((item) => Map<String, dynamic>.from(item as Map)).toList();
      }
    } catch (e) {
      log('[CallTracker] getRecentCallLogs error: $e');
    }
    return [];
  }

  /// Store a pending post-call prompt record
  static Future<void> savePendingPostCall({
    required String number,
    required int duration,
    required String direction,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pending_post_call_number', number);
      await prefs.setInt('pending_post_call_duration', duration);
      await prefs.setString('pending_post_call_direction', direction);
      await prefs.setInt('pending_post_call_time', DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  /// Check if there is an unhandled pending post-call prompt
  static Future<Map<String, dynamic>?> getPendingPostCall() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final number = prefs.getString('pending_post_call_number');
      final duration = prefs.getInt('pending_post_call_duration') ?? 0;
      final direction = prefs.getString('pending_post_call_direction') ?? 'INCOMING';
      final timestamp = prefs.getInt('pending_post_call_time') ?? 0;

      if (number != null && number.isNotEmpty) {
        final ageMs = DateTime.now().millisecondsSinceEpoch - timestamp;
        if (ageMs < 30 * 60 * 1000) {
          return {
            'number': number,
            'duration': duration,
            'direction': direction,
            'timestamp': timestamp,
          };
        } else {
          await clearPendingPostCall();
        }
      }
    } catch (_) {}
    return null;
  }

  /// Clear pending post-call record
  static Future<void> clearPendingPostCall() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('pending_post_call_number');
      await prefs.remove('pending_post_call_duration');
      await prefs.remove('pending_post_call_direction');
      await prefs.remove('pending_post_call_time');
    } catch (_) {}
  }

  /// Check if a call timestamp has already been processed/prompted
  static Future<bool> isCallProcessed(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('processed_call_keys') ?? [];
      return list.contains(key);
    } catch (_) {
      return false;
    }
  }

  /// Mark a call as processed/prompted
  static Future<void> markCallProcessed(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('processed_call_keys') ?? [];
      if (!list.contains(key)) {
        list.add(key);
        if (list.length > 100) list.removeAt(0);
        await prefs.setStringList('processed_call_keys', list);
      }
    } catch (_) {}
  }
}