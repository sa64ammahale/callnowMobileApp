import 'dart:developer';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:phone_state_background/phone_state_background.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:callnow_new/services/web_url.dart';

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
      break;

    case PhoneStateBackgroundEvent.outgoingend:
      log('[CallTracker] Outgoing call ended to: $number, duration: $duration s');
      await CallTrackingService.syncCallActivity(
        number: number,
        duration: duration,
        direction: 'OUTGOING',
        status: duration > 0 ? 'CONNECTED' : 'MISSED/CANCELLED',
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
      await CallTrackingService.syncCallActivity(
        number: number,
        duration: 0,
        direction: 'INCOMING',
        status: 'MISSED',
      );
      break;

    case PhoneStateBackgroundEvent.incomingend:
      log('[CallTracker] Incoming call ended from: $number, duration: $duration s');
      await CallTrackingService.syncCallActivity(
        number: number,
        duration: duration,
        direction: 'INCOMING',
        status: 'RECEIVED',
      );
      break;
  }
}

class CallTrackingService {
  static final ValueNotifier<bool> isTrackingActive = ValueNotifier<bool>(false);
  static final ValueNotifier<String> lastCallEvent =
      ValueNotifier<String>('Waiting for call activity...');
  static final ValueNotifier<int> totalCallsTracked = ValueNotifier<int>(0);

  /// Check if the required Android permissions (READ_PHONE_STATE, READ_CALL_LOG) are granted
  static Future<bool> checkPermission() async {
    try {
      return await PhoneStateBackground.checkPermission();
    } catch (e) {
      log('[CallTracker] checkPermission error: $e');
      return false;
    }
  }

  /// Request required Android permissions
  static Future<bool> requestPermissions() async {
    try {
      await PhoneStateBackground.requestPermissions();
      return await checkPermission();
    } catch (e) {
      log('[CallTracker] requestPermissions error: $e');
      return false;
    }
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

  /// Sync call records to backend API (Url.dialDataActivity)
  static Future<void> syncCallActivity({
    required String number,
    required int duration,
    required String direction,
    required String status,
  }) async {
    totalCallsTracked.value++;
    try {
      final response = await http.post(
        Uri.parse(Url.dialDataActivity),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'MOBILE': number,
          'DURATION': duration.toString(),
          'STATUS': status,
          'CALL_BY': 'APP_USER',
          'CALL_TIME': DateTime.now().toIso8601String(),
          'DIRECTION': direction,
        },
      );
      log('[CallTracker] Sync response code: ${response.statusCode}');
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
