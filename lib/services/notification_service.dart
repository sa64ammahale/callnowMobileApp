import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:callnow_new/model/followup_model.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  static final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static const String channelId = 'callnow_callbacks_channel';
  static const String channelName = 'Client Callback Reminders';
  static const String channelDescription =
      'High priority alerts when a client callback is due.';

  static final StreamController<String?> _selectNotificationStream =
      StreamController<String?>.broadcast();

  static Stream<String?> get onNotificationTap =>
      _selectNotificationStream.stream;

  static bool _isInitialized = false;

  static Future<void> init() async {
    if (_isInitialized) return;

    try {
      tz_data.initializeTimeZones();
      // Use local timezone or fallback to UTC if device timezone lookup fails
      try {
        final localName = DateTime.now().timeZoneName;
        if (tz.timeZoneDatabase.locations.containsKey(localName)) {
          tz.setLocalLocation(tz.getLocation(localName));
        }
      } catch (_) {}

      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      const InitializationSettings initializationSettings =
          InitializationSettings(
        android: initializationSettingsAndroid,
      );

      await _flutterLocalNotificationsPlugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse:
            (NotificationResponse notificationResponse) {
          final payload = notificationResponse.payload;
          _selectNotificationStream.add(payload);
        },
      );

      // Create Android Notification Channel
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        channelId,
        channelName,
        description: channelDescription,
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );

      await _flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);

      _isInitialized = true;
    } catch (e) {
      debugPrint('NotificationService init error: $e');
    }
  }

  static Future<bool> requestPermissions() async {
    final androidImplementation = _flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidImplementation != null) {
      final granted =
          await androidImplementation.requestNotificationsPermission();
      return granted ?? false;
    }
    return true;
  }

  static int _getNotificationId(String followupId) {
    return followupId.hashCode.abs() % 2147483647;
  }

  static Future<void> scheduleFollowupNotification(
      FollowupModel followup) async {
    try {
      await init();
      final id = _getNotificationId(followup.id);

      // Only schedule if scheduledTime is in future
      if (followup.scheduledTime.isBefore(DateTime.now())) {
        return;
      }

      final scheduledDate =
          tz.TZDateTime.from(followup.scheduledTime, tz.local);

      final androidPlatformChannelSpecifics = AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDescription,
        importance: Importance.max,
        priority: Priority.high,
        ticker: 'Callback due: ${followup.customerName}',
        playSound: true,
        enableVibration: true,
        fullScreenIntent: true,
        actions: <AndroidNotificationAction>[
          const AndroidNotificationAction(
            'action_call',
            '📞 Call Now',
            showsUserInterface: true,
          ),
          const AndroidNotificationAction(
            'action_open',
            'View Follow-up',
            showsUserInterface: true,
          ),
        ],
      );

      final notificationDetails = NotificationDetails(
        android: androidPlatformChannelSpecifics,
      );

      final payloadMap = {
        'id': followup.id,
        'customer_name': followup.customerName,
        'phone_number': followup.phoneNumber,
        'company': followup.company,
        'notes': followup.notes,
        'scheduled_time': followup.scheduledTime.toIso8601String(),
      };

      await _flutterLocalNotificationsPlugin.zonedSchedule(
        id,
        '📞 Callback: ${followup.customerName}',
        '${followup.phoneNumber} • ${followup.notes.isNotEmpty ? followup.notes : "Call scheduled for this time"}',
        scheduledDate,
        notificationDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        payload: jsonEncode(payloadMap),
      );
    } catch (e) {
      debugPrint('Error scheduling notification: $e');
    }
  }

  static Future<void> cancelFollowupNotification(String followupId) async {
    try {
      final id = _getNotificationId(followupId);
      await _flutterLocalNotificationsPlugin.cancel(id);
    } catch (e) {
      debugPrint('Error cancelling notification: $e');
    }
  }

  static Future<void> showInstantAlert({
    required String title,
    required String body,
    String? payload,
  }) async {
    try {
      await init();
      const androidPlatformChannelSpecifics = AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDescription,
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
      );

      const notificationDetails = NotificationDetails(
        android: androidPlatformChannelSpecifics,
      );

      final id = DateTime.now().millisecondsSinceEpoch.remainder(100000);
      await _flutterLocalNotificationsPlugin.show(
        id,
        title,
        body,
        notificationDetails,
        payload: payload,
      );
    } catch (e) {
      debugPrint('Error showing instant alert: $e');
    }
  }
}
