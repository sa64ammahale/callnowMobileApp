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
import 'package:callnow_new/services/pending_call_recovery_service.dart';
import 'package:callnow_new/services/secure_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SecureStorageService.setBackendForTesting(MemorySecureStorageBackend());
    await ConfigService.setBaseUrl('https://crm.callnow.example.com/api/v1');
    await ConfigService.saveAuthData('tok-telecaller', {
      'id': 4,
      'name': 'Amit Kumar',
      'role': 'Officer',
    });
    CallingDeskScreen.clearSessionProcessedLeads();
    await PendingCallRecoveryService.clearPendingCall();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.example.callnow/call_verifier'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'getLatestCallLog') {
          return {
            'isDialed': true,
            'number': methodCall.arguments['phoneNumber'] ?? '9876543210',
            'duration': 0,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
            'type': 2,
          };
        }
        return null;
      },
    );
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

  group('PendingCallRecoveryService Tests', () {
    test('Saves, retrieves, and clears pending dialed call accurately', () async {
      expect(await PendingCallRecoveryService.hasPendingCall(), isFalse);

      final leadData = {
        'id': '101',
        'name': 'Ramesh Verma',
        'mobile': '9876543210',
        'company': 'Verma Traders',
        'package': '500000',
        'source': 'TEMPORARY',
      };

      await PendingCallRecoveryService.savePendingCall(leadData);

      expect(await PendingCallRecoveryService.hasPendingCall(), isTrue);

      final restored = await PendingCallRecoveryService.getPendingCall();
      expect(restored, isNotNull);
      expect(restored!['id'], '101');
      expect(restored['name'], 'Ramesh Verma');
      expect(restored['mobile'], '9876543210');

      await PendingCallRecoveryService.clearPendingCall();
      expect(await PendingCallRecoveryService.hasPendingCall(), isFalse);
      expect(await PendingCallRecoveryService.getPendingCall(), isNull);
    });

    test('Pending call older than maxPendingAge expires and auto-clears', () async {
      final prefs = await SharedPreferences.getInstance();
      final leadData = {
        'id': '102',
        'name': 'Old Contact',
        'mobile': '9876543211',
      };

      // Set timestamp 5 hours in the past
      final fiveHoursAgo = DateTime.now().subtract(const Duration(hours: 5)).millisecondsSinceEpoch;
      await prefs.setString('callnow_pending_dialed_lead', jsonEncode(leadData));
      await prefs.setInt('callnow_pending_dialed_timestamp', fiveHoursAgo);

      final restored = await PendingCallRecoveryService.getPendingCall();
      expect(restored, isNull, reason: 'Pending call older than 4 hours must expire');
      expect(await PendingCallRecoveryService.hasPendingCall(), isFalse);
    });
  });

  group('CallingDesk Low-RAM Cold Start Recovery Tests', () {
    testWidgets('Restores dialed contact as active lead on cold restart and clears on submit', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // 1. Simulate: User dialed Ramesh Verma before Android OS killed the app
      final dialedLead = {
        'id': '101',
        'name': 'Ramesh Verma',
        'mobile': '9876543210',
        'company': 'Verma Traders',
        'package': '500000',
        'source': 'TEMPORARY',
        'last_status': 'Not Called',
      };
      await PendingCallRecoveryService.savePendingCall(dialedLead);

      // Mock server batch response with other new leads
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/telecaller/batch-leads')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': [
                {
                  'id': '201',
                  'name': 'New Lead 1',
                  'mobile': '9876543299',
                  'company': 'New Corp',
                  'package': '300000',
                  'source': 'TEMPORARY',
                },
                {
                  'id': '202',
                  'name': 'New Lead 2',
                  'mobile': '9876543288',
                  'company': 'Another Corp',
                  'package': '400000',
                  'source': 'TEMPORARY',
                },
              ]
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path.contains('/complete')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'message': 'Call logged successfully',
                'call_id': 101,
              }
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{"status":"error"}', 404);
      });

      ApiService.setClientForTesting(mockClient);

      // 2. Cold-start CallingDeskScreen
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CallingDeskScreen(),
          ),
        ),
      );

      // Allow async _loadInitialBatch to complete
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      // 3. Verify Ramesh Verma is restored as Lead 1!
      expect(find.text('Ramesh Verma'), findsOneWidget);
      expect(find.text('9876543210'), findsOneWidget);
      expect(find.text('Verma Traders'), findsOneWidget);

      // Verify the restored call banner is visible
      expect(find.text('Dialed contact restored. Please select call outcome and save.'), findsOneWidget);

      // Verify the next leads from the batch follow after Ramesh Verma
      final state = tester.state<CallingDeskScreenState>(find.byType(CallingDeskScreen));
      expect(state.leads.length, 3); // Ramesh Verma + 2 batch leads
      expect(state.leads[0]['id'], '101');
      expect(state.leads[1]['id'], '201');
      expect(state.isRestoredFromPending, isTrue);

      // 4. Select outcome and submit
      // Set verified call log so Save & Next proceeds
      state.setVerifiedCallLogForTesting(
        VerifiedCallLog(
          isDialed: true,
          number: '9876543210',
          durationSeconds: 0,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          type: 2, // outgoing
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Tap Save & Next
      final saveBtn = find.text('Save & Next');
      expect(saveBtn, findsOneWidget);
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      // 5. Verify pending call was cleared from storage
      expect(await PendingCallRecoveryService.hasPendingCall(), isFalse);
      expect(state.isRestoredFromPending, isFalse);

      // 6. Verify CallingDeskScreen automatically advanced to the next lead (New Lead 1)
      expect(find.text('New Lead 1'), findsOneWidget);
      expect(find.text('Dialed contact restored. Please select call outcome and save.'), findsNothing);
    });

    testWidgets('Skipping a restored contact clears pending call and advances queue', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // 1. Simulate: User dialed Suresh before OS killed app
      final dialedLead = {
        'id': '301',
        'name': 'Suresh Patel',
        'mobile': '9876543222',
        'company': 'Patel Exports',
        'package': '750000',
        'source': 'TEMPORARY',
      };
      await PendingCallRecoveryService.savePendingCall(dialedLead);

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/telecaller/batch-leads')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': [
                {
                  'id': '401',
                  'name': 'Followup Lead 1',
                  'mobile': '9876543233',
                  'company': 'Next Corp',
                  'package': '250000',
                  'source': 'TEMPORARY',
                },
              ]
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{"status":"error"}', 404);
      });

      ApiService.setClientForTesting(mockClient);

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

      // Verify Suresh is restored
      expect(find.text('Suresh Patel'), findsOneWidget);
      expect(await PendingCallRecoveryService.hasPendingCall(), isTrue);

      // Tap Skip Lead button
      final skipBtn = find.text('Skip this lead');
      expect(skipBtn, findsOneWidget);
      await tester.ensureVisible(skipBtn);
      await tester.tap(skipBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // If call was verified as dialed, confirmation dialog opens
      final discardBtn = find.text('Discard & Skip');
      if (discardBtn.evaluate().isNotEmpty) {
        await tester.tap(discardBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      }

      // Verify pending call is cleared immediately upon skip
      expect(await PendingCallRecoveryService.hasPendingCall(), isFalse);

      // Verify queue advanced to Followup Lead 1
      expect(find.text('Followup Lead 1'), findsOneWidget);
    });
  });
}
