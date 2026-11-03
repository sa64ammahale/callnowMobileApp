import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:phone_state_background/phone_state_background.dart';
import 'package:callnow_new/services/notification_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class PermissionStatusReport {
  final bool phoneState;
  final bool callLog;
  final bool callPhone;
  final bool notifications;

  const PermissionStatusReport({
    required this.phoneState,
    required this.callLog,
    required this.callPhone,
    required this.notifications,
  });

  bool get allGranted => phoneState && callLog && callPhone && notifications;

  /// Whether READ_CALL_LOG is specifically denied/restricted.
  /// On Android 10+ this is a restricted permission requiring Play Store approval.
  bool get isCallLogRestricted => !callLog;

  int get grantedCount {
    int count = 0;
    if (phoneState) count++;
    if (callLog) count++;
    if (callPhone) count++;
    if (notifications) count++;
    return count;
  }

  int get totalCount => 4;
}

class PermissionService {
  /// In-memory mock override for unit and widget testing
  @visibleForTesting
  static PermissionStatusReport? mockReport;

  /// Whether a test mock report is currently set
  static bool get isMockActive => mockReport != null;

  /// Check status of all 4 required permissions
  static Future<PermissionStatusReport> checkAllPermissions() async {
    if (mockReport != null) {
      return mockReport!;
    }

    if (kIsWeb || !Platform.isAndroid) {
      return const PermissionStatusReport(
        phoneState: true,
        callLog: true,
        callPhone: true,
        notifications: true,
      );
    }

    try {
      final details = await PhoneStateBackground.checkPermissionDetails();
      final phoneState = details['phone_state'] ?? false;
      final callLog = details['call_log'] ?? false;
      final callPhone = details['call_phone'] ?? false;

      // Notifications check
      bool notifications = true;
      try {
        final notificationsPlugin = FlutterLocalNotificationsPlugin();
        final androidImpl = notificationsPlugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        if (androidImpl != null) {
          final enabled = await androidImpl.areNotificationsEnabled();
          notifications = enabled ?? true;
        }
      } catch (_) {
        notifications = true;
      }

      return PermissionStatusReport(
        phoneState: phoneState,
        callLog: callLog,
        callPhone: callPhone,
        notifications: notifications,
      );
    } catch (e) {
      debugPrint('[PermissionService] checkAllPermissions error: $e');
      return const PermissionStatusReport(
        phoneState: false,
        callLog: false,
        callPhone: false,
        notifications: false,
      );
    }
  }

  /// True if all 4 required permissions are granted
  static Future<bool> hasAllPermissions() async {
    final report = await checkAllPermissions();
    return report.allGranted;
  }

  /// Whether READ_CALL_LOG specifically is denied/restricted.
  /// Helpful for UI degradation: call-log verification becomes best-effort.
  static Future<bool> isReadCallLogRestricted() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    if (mockReport != null) return !mockReport!.callLog;
    try {
      final details = await PhoneStateBackground.checkPermissionDetails();
      return details['call_log'] != true;
    } catch (_) {
      return true;
    }
  }

  /// Request all ungranted permissions in a gentle sequence
  static Future<PermissionStatusReport> requestAllPermissions() async {
    if (mockReport != null) {
      return mockReport!;
    }

    if (kIsWeb || !Platform.isAndroid) {
      return const PermissionStatusReport(
        phoneState: true,
        callLog: true,
        callPhone: true,
        notifications: true,
      );
    }

    try {
      // 1. Request Phone State, Call Log, and Call Phone via Android system dialog
      await PhoneStateBackground.requestPermissions();

      // 2. Request Notifications permission (Android 13+)
      await NotificationService.requestPermissions();

      return await checkAllPermissions();
    } catch (e) {
      debugPrint('[PermissionService] requestAllPermissions error: $e');
      return await checkAllPermissions();
    }
  }

  /// Open device settings so user can manually enable permissions
  static Future<bool> openDeviceSettings() async {
    try {
      return await PhoneStateBackground.openAppSettings();
    } catch (e) {
      debugPrint('[PermissionService] openDeviceSettings error: $e');
      return false;
    }
  }
}
