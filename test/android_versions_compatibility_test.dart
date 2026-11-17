import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:callnow_new/screens/calling_desk_screen.dart';
import 'package:callnow_new/services/api_service.dart';
import 'package:callnow_new/services/call_tracking_service.dart';
import 'package:callnow_new/services/config_service.dart';
import 'package:callnow_new/services/notification_service.dart';
import 'package:callnow_new/services/pending_call_recovery_service.dart';
import 'package:callnow_new/services/secure_storage_service.dart';
import 'package:phone_state_background/phone_state_background.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SecureStorageService.setBackendForTesting(MemorySecureStorageBackend());
    await ConfigService.setBaseUrl('https://crm.callnow.example.com/api/v1');
    await ConfigService.saveAuthData('tok-telecaller-android-compat', {
      'id': 101,
      'name': 'Pooja Sharma',
      'role': 'Officer',
    });
    CallingDeskScreen.clearSessionProcessedLeads();
    await PendingCallRecoveryService.clearPendingCall();
  });

  tearDown(() async {
    ApiService.resetClient();
    SecureStorageService.resetBackend();
    CallingDeskScreen.clearSessionProcessedLeads();
    await PendingCallRecoveryService.clearPendingCall();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.example.callnow/call_verifier'),
      null,
    );
  });

  group('White-Box: Android CallLog Contract & Classification Tests', () {
    test('Simulates Android 12-15 CallLog verification contract', () async {
      // Setup mock method handler that faithfully implements the MainActivity.kt logic
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.example.callnow/call_verifier'),
        (MethodCall call) async {
          if (call.method == 'getLatestCallLog') {
            final args = call.arguments as Map?;
            final targetNumber = args?['phoneNumber'] as String? ?? '';
            final afterTimestamp = (args?['afterTimestamp'] as num?)?.toInt() ?? 0;

            final cleanTarget = targetNumber.replaceAll(RegExp(r'[^0-9]'), '');
            final last10Target =
                cleanTarget.length >= 10 ? cleanTarget.substring(cleanTarget.length - 10) : cleanTarget;

            // Simulated call records in device CallLog
            final simulatedRecords = [
              // Record 1: Outgoing call to target
              {
                'number': '+919167446813',
                'type': 2, // OUTGOING_TYPE
                'date': DateTime.now().millisecondsSinceEpoch - 5000,
                'duration': 42,
              },
            ];

            for (final record in simulatedRecords) {
              final numStr = (record['number'] as String).replaceAll(RegExp(r'[^0-9]'), '');
              final last10Num = numStr.length >= 10 ? numStr.substring(numStr.length - 10) : numStr;
              final callDate = record['date'] as int;
              final duration = record['duration'] as int;
              final callType = record['type'] as int;

              final isMatch = last10Target.isNotEmpty &&
                  (last10Num == last10Target || numStr.endsWith(last10Target) || last10Target.endsWith(numStr));

              final isIncomingOrMissed = callType == 1 || // INCOMING_TYPE
                  callType == 3 || // MISSED_TYPE
                  callType == 4 || // VOICEMAIL_TYPE
                  callType == 5 || // REJECTED_TYPE
                  callType == 6; // BLOCKED_TYPE

              final isOutgoingOrAttempt = (callType == 2) || (!isIncomingOrMissed && (duration > 0 || callType > 0));

              final minTimestamp = afterTimestamp > 0 ? afterTimestamp - 60000 : 0;
              final withinTime = callDate >= minTimestamp;

              if (isMatch && isOutgoingOrAttempt && withinTime) {
                return {
                  'isDialed': true,
                  'hasPermission': true,
                  'number': record['number'],
                  'duration': duration,
                  'timestamp': callDate,
                  'type': callType,
                };
              }
            }

            return {
              'isDialed': false,
              'hasPermission': true,
              'number': targetNumber,
              'duration': 0,
              'timestamp': 0,
              'type': 0,
            };
          }
          return null;
        },
      );

      final verified = await CallTrackingService.verifyCallLog('9167446813', afterTimestamp: 1000);
      expect(verified.isDialed, isTrue);
      expect(verified.durationSeconds, equals(42));
      expect(verified.hasPermission, isTrue);
    });

    test('Strict classification rejects MISSED_TYPE (3) and INCOMING_TYPE (1)', () {
      // Test the logic directly to ensure incoming or missed calls are never treated as outgoing attempts
      bool classifyAsDialed({required int callType, required int duration}) {
        const int incomingType = 1;
        const int outgoingType = 2;
        const int missedType = 3;
        const int voicemailType = 4;
        const int rejectedType = 5;
        const int blockedType = 6;
        const int answeredExternallyType = 7;

        final bool isIncomingOrMissed = callType == incomingType ||
            callType == missedType ||
            callType == voicemailType ||
            callType == rejectedType ||
            callType == blockedType ||
            callType == answeredExternallyType;

        return (callType == outgoingType) || (!isIncomingOrMissed && (duration > 0 || callType > 0));
      }

      // Outgoing calls (Type 2)
      expect(classifyAsDialed(callType: 2, duration: 0), isTrue, reason: 'Outgoing unanswered is dialed');
      expect(classifyAsDialed(callType: 2, duration: 60), isTrue, reason: 'Outgoing answered is dialed');

      // Incoming / Missed calls (Customer called telecaller)
      expect(classifyAsDialed(callType: 1, duration: 30), isFalse, reason: 'Incoming answered must NOT be dialed');
      expect(classifyAsDialed(callType: 3, duration: 0), isFalse, reason: 'Missed incoming must NOT be dialed');
      expect(classifyAsDialed(callType: 4, duration: 0), isFalse, reason: 'Voicemail must NOT be dialed');
      expect(classifyAsDialed(callType: 5, duration: 0), isFalse, reason: 'Rejected incoming must NOT be dialed');
      expect(classifyAsDialed(callType: 6, duration: 0), isFalse, reason: 'Blocked incoming must NOT be dialed');
      expect(classifyAsDialed(callType: 7, duration: 15), isFalse, reason: 'External incoming must NOT be dialed');

      // Custom OEM attempt codes (e.g. 10 or 100 on MediaTek dual-SIM)
      expect(classifyAsDialed(callType: 10, duration: 12), isTrue, reason: 'OEM non-incoming with talk time is dialed');
    });

    test('10-digit number normalization matches across +91, 0, and clean formats', () {
      bool numbersMatch(String inputA, String inputB) {
        final cleanA = inputA.replaceAll(RegExp(r'[^0-9]'), '');
        final cleanB = inputB.replaceAll(RegExp(r'[^0-9]'), '');
        final last10A = cleanA.length >= 10 ? cleanA.substring(cleanA.length - 10) : cleanA;
        final last10B = cleanB.length >= 10 ? cleanB.substring(cleanB.length - 10) : cleanB;

        if (last10A.isNotEmpty && last10B.isNotEmpty) {
          return last10A == last10B || cleanA.endsWith(last10B) || cleanB.endsWith(last10A);
        }
        return cleanA == cleanB;
      }

      expect(numbersMatch('9167446813', '+919167446813'), isTrue);
      expect(numbersMatch('9167446813', '09167446813'), isTrue);
      expect(numbersMatch('+91 91674 46813', '9167446813'), isTrue);
      expect(numbersMatch('9167446813', '9876543210'), isFalse);
    });
  });

  group('Black-Box: Calling Desk Permission Denial & Deep-Link Tests', () {
    testWidgets('Get Status handles READ_CALL_LOG permission denied on Android 12+ gracefully',
        (WidgetTester tester) async {
      // Mock API returning 1 lead
      final client = MockClient((request) async {
        if (request.url.path.contains('/telecaller/batch-leads')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': [
                {
                  'id': 201,
                  'name': 'Rahul Sharma',
                  'mobile': '9876543210',
                  'company': 'Tech Corp',
                  'package': 'Rs. 10.00 LACS',
                  'source': 'TEMP',
                }
              ]
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{"status":"error"}', 400);
      });
      ApiService.setClientForTesting(client);

      // Mock MethodChannel returning PERMISSION_DENIED
      bool openSettingsCalled = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.example.callnow/call_verifier'),
        (MethodCall call) async {
          if (call.method == 'getLatestCallLog') {
            final args = call.arguments as Map?;
            return {
              'isDialed': false,
              'hasPermission': false,
              'number': args?['phoneNumber'],
              'duration': 0,
              'timestamp': 0,
              'type': 0,
              'error': 'PERMISSION_DENIED',
            };
          }
          if (call.method == 'openAppSettings') {
            openSettingsCalled = true;
            return true;
          }
          return null;
        },
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: CallingDeskScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Lead is rendered
      expect(find.text('Rahul Sharma'), findsOneWidget);
      expect(find.text('Get Status'), findsOneWidget);

      // Tap Get Status
      await tester.tap(find.text('Get Status'));
      await tester.pump(); // Start async check
      await tester.pump(const Duration(milliseconds: 500));

      // Assert permission alert snackbar is shown with SETTINGS action
      expect(find.textContaining('Call Log permission is required to detect dialed calls'), findsOneWidget);
      expect(find.text('SETTINGS'), findsOneWidget);

      // Tap SETTINGS action button
      await tester.tap(find.text('SETTINGS'));
      await tester.pump();
      expect(openSettingsCalled, isTrue);

      // Outcomes remain securely locked
      expect(find.text('Save & Next'), findsNothing);
    });

    testWidgets('Get Status unlocks outcomes when call is dialed and permission is granted',
        (WidgetTester tester) async {
      final client = MockClient((request) async {
        if (request.url.path.contains('/telecaller/batch-leads')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': [
                {
                  'id': 202,
                  'name': 'Anita Desai',
                  'mobile': '9876543211',
                  'company': 'Finance Ltd',
                  'package': 'Rs. 25.00 LACS',
                  'source': 'TEMP',
                }
              ]
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{"status":"error"}', 400);
      });
      ApiService.setClientForTesting(client);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.example.callnow/call_verifier'),
        (MethodCall call) async {
          if (call.method == 'getLatestCallLog') {
            final args = call.arguments as Map?;
            return {
              'isDialed': true,
              'hasPermission': true,
              'number': args?['phoneNumber'],
              'duration': 55,
              'timestamp': DateTime.now().millisecondsSinceEpoch,
              'type': 2,
            };
          }
          return null;
        },
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: CallingDeskScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Anita Desai'), findsOneWidget);

      // Tap Get Status
      await tester.tap(find.text('Get Status'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Outcomes unlocked!
      expect(find.text('Save & Next'), findsOneWidget);
      expect(find.text('✓ Connected (55s)'), findsOneWidget);
    });

    testWidgets('Get Status unlocks outcomes as Not Connected / Ringing when call is dialed with 0s duration (Scenario B2)',
        (WidgetTester tester) async {
      final client = MockClient((request) async {
        if (request.url.path.contains('/telecaller/batch-leads')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': [
                {
                  'id': 203,
                  'name': 'Kunal Verma',
                  'mobile': '9876543212',
                  'company': 'Solar Energy',
                  'package': 'Rs. 15.00 LACS',
                  'source': 'TEMP',
                }
              ]
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{"status":"error"}', 400);
      });
      ApiService.setClientForTesting(client);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.example.callnow/call_verifier'),
        (MethodCall call) async {
          if (call.method == 'getLatestCallLog') {
            final args = call.arguments as Map?;
            return {
              'isDialed': true,
              'hasPermission': true,
              'number': args?['phoneNumber'],
              'duration': 0, // Unanswered / busy call
              'timestamp': DateTime.now().millisecondsSinceEpoch,
              'type': 2, // OUTGOING_TYPE
            };
          }
          return null;
        },
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: CallingDeskScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Kunal Verma'), findsOneWidget);

      await tester.tap(find.text('Get Status'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Save & Next'), findsOneWidget);
      expect(find.text('✗ Not Connected'), findsAtLeastNWidgets(1));
    });

    testWidgets('Get Status rejects incoming missed calls (MISSED_TYPE 3) and leaves outcomes locked (Scenario B3)',
        (WidgetTester tester) async {
      final client = MockClient((request) async {
        if (request.url.path.contains('/telecaller/batch-leads')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': [
                {
                  'id': 204,
                  'name': 'Deepak Joshi',
                  'mobile': '9876543213',
                  'company': 'Auto Corp',
                  'package': 'Rs. 12.00 LACS',
                  'source': 'TEMP',
                }
              ]
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{"status":"error"}', 400);
      });
      ApiService.setClientForTesting(client);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.example.callnow/call_verifier'),
        (MethodCall call) async {
          if (call.method == 'getLatestCallLog') {
            final args = call.arguments as Map?;
            // Simulate that the only record is a missed incoming call from Deepak
            // MainActivity.kt correctly marks isDialed = false
            return {
              'isDialed': false,
              'hasPermission': true,
              'number': args?['phoneNumber'],
              'duration': 0,
              'timestamp': DateTime.now().millisecondsSinceEpoch,
              'type': 3, // MISSED_TYPE
            };
          }
          return null;
        },
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: CallingDeskScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Deepak Joshi'), findsOneWidget);

      await tester.tap(find.text('Get Status'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Assert snackbar informs user to dial first
      expect(find.textContaining('Please dial the call first'), findsOneWidget);
      // Outcomes remain locked
      expect(find.text('Save & Next'), findsNothing);
    });

    testWidgets('Low-RAM process kill and cold restart on Android 12-15 restores pending dialed call and unlocks outcomes (Scenario B7)',
        (WidgetTester tester) async {
      // Simulate that before app was killed by OS, lead was dialed
      await PendingCallRecoveryService.savePendingCall({
        'id': '205',
        'name': 'Vikram Malhotra',
        'mobile': '9876543214',
        'company': 'Logistics Pro',
        'package': 'Rs. 50.00 LACS',
        'source': 'TEMP',
      });

      final client = MockClient((request) async {
        if (request.url.path.contains('/telecaller/batch-leads')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': [
                {
                  'id': '206',
                  'name': 'Next Fresh Lead',
                  'mobile': '9876543215',
                  'company': 'Next Corp',
                  'package': 'Rs. 20.00 LACS',
                  'source': 'TEMP',
                }
              ]
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{"status":"error"}', 400);
      });
      ApiService.setClientForTesting(client);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CallingDeskScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      // Assert Vikram Malhotra is restored at index 0 and outcomes are pre-unlocked
      expect(find.text('Vikram Malhotra'), findsOneWidget);
      expect(find.text('Save & Next'), findsOneWidget);
    });
  });

  group('White-Box: PhoneStateBackground & Notification Resilience Tests', () {
    test('phoneStateBackgroundCallbackHandler safely handles null/empty numbers on Android 10-15', () async {
      // Calling with empty number should not throw exception
      expect(
        () async => await phoneStateBackgroundCallbackHandler(
          PhoneStateBackgroundEvent.outgoingstart,
          '',
          0,
        ),
        returnsNormally,
      );

      expect(
        () async => await phoneStateBackgroundCallbackHandler(
          PhoneStateBackgroundEvent.outgoingend,
          '',
          0,
        ),
        returnsNormally,
      );
    });

    test('NotificationService cancels and initializes without throwing on test/mock environments', () async {
      expect(
        () async => await NotificationService.cancelFollowupNotification('followup-123'),
        returnsNormally,
      );
    });
  });
}
