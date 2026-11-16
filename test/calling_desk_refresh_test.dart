import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:callnow_new/screens/calling_desk_screen.dart';
import 'package:callnow_new/screens/call_reports_screen.dart';
import 'package:callnow_new/services/api_service.dart';
import 'package:callnow_new/services/call_tracking_service.dart';
import 'package:callnow_new/services/config_service.dart';
import 'package:callnow_new/services/secure_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SecureStorageService.setBackendForTesting(MemorySecureStorageBackend());
    await ConfigService.init();
    CallingDeskScreen.clearSessionProcessedLeads();
    ConfigService.clearLogoutCallbacks();
  });

  tearDown(() {
    ApiService.resetClient();
    SecureStorageService.resetBackend();
    CallingDeskScreen.clearSessionProcessedLeads();
    ConfigService.clearLogoutCallbacks();
  });

  group('Calling Desk Session Tracking & Identifier Tests', () {
    test('getLeadIdentifier extracts id, lead_id, or mobile fallback', () {
      expect(CallingDeskScreen.getLeadIdentifier({'id': '101', 'mobile': '9876543210'}), '101');
      expect(CallingDeskScreen.getLeadIdentifier({'id': 102, 'mobile': '9876543210'}), '102');
      expect(CallingDeskScreen.getLeadIdentifier({'id': '0', 'lead_id': '201', 'mobile': '9876543210'}), '201');
      expect(CallingDeskScreen.getLeadIdentifier({'lead_id': '202'}), '202');
      expect(CallingDeskScreen.getLeadIdentifier({'mobile': '9988776655'}), '9988776655');
      expect(CallingDeskScreen.getLeadIdentifier({}), '');
    });

    test('markLeadProcessed tracks processed leads and clearSessionProcessedLeads wipes them', () {
      CallingDeskScreen.markLeadProcessed('101');
      CallingDeskScreen.markLeadProcessed('102');
      expect(CallingDeskScreen.sessionProcessedLeadIds.contains('101'), isTrue);
      expect(CallingDeskScreen.sessionProcessedLeadIds.contains('102'), isTrue);
      expect(CallingDeskScreen.sessionProcessedLeadIds.contains('103'), isFalse);

      CallingDeskScreen.clearSessionProcessedLeads();
      expect(CallingDeskScreen.sessionProcessedLeadIds.isEmpty, isTrue);
    });

    test('ConfigService.clearAuthData triggers CallingDeskScreen.clearSessionProcessedLeads', () async {
      ConfigService.registerLogoutCallback(CallingDeskScreen.clearSessionProcessedLeads);
      CallingDeskScreen.markLeadProcessed('999');
      expect(CallingDeskScreen.sessionProcessedLeadIds.contains('999'), isTrue);

      await ConfigService.clearAuthData();
      expect(CallingDeskScreen.sessionProcessedLeadIds.isEmpty, isTrue);
    });
  });

  group('CallingDeskScreen Refresh & Preservation Widget Tests', () {
    testWidgets('Preserve active lead and block refresh when calls uncompleted', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      int apiCallCount = 0;
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/telecaller/batch-leads')) {
          apiCallCount++;
          if (apiCallCount == 1) {
            // First batch: Lead 1 and Lead 2
            return http.Response(
              json.encode({
                'success': true,
                'data': {
                  'leads': [
                    {'id': '1', 'name': 'Alice Smith', 'mobile': '9876543210', 'company': 'Acme Corp'},
                    {'id': '2', 'name': 'Bob Jones', 'mobile': '9876543211', 'company': 'Beta Inc'},
                  ]
                }
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          } else {
            // Refresh batch: Lead 1 (duplicate from server), Lead 3 (new)
            return http.Response(
              json.encode({
                'success': true,
                'data': {
                  'leads': [
                    {'id': '1', 'name': 'Alice Smith', 'mobile': '9876543210'},
                    {'id': '3', 'name': 'Charlie Brown', 'mobile': '9876543212'},
                  ]
                }
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
        }
        return http.Response(json.encode({'success': true, 'data': {}}), 200);
      });

      ApiService.setClientForTesting(mockClient);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CallingDeskScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify Alice Smith is displayed
      expect(find.text('Alice Smith'), findsOneWidget);

      final state = tester.state<CallingDeskScreenState>(find.byType(CallingDeskScreen));
      expect(state.currentIndex, equals(0));
      expect(state.leads.length, equals(2));

      // Enter notes directly on controller
      state.notesController.text = 'Discussed product pricing and discount';
      await tester.pump();
      expect(state.notesController.text, equals('Discussed product pricing and discount'));

      // Trigger refresh while Alice (current lead) is still uncompleted
      // Bucket hasn't expired (just filled), so refresh should be BLOCKED
      await state.refreshBatchForTesting();
      await tester.pumpAndSettle();

      // Verify Alice Smith is still displayed and notes are preserved!
      expect(find.text('Alice Smith'), findsOneWidget);
      expect(state.currentIndex, equals(0));
      expect(state.notesController.text, equals('Discussed product pricing and discount'));

      // Verify queue was NOT appended — still 2 leads, no Charlie
      expect(state.leads.length, equals(2));
      expect(state.leads[0]['id'], equals('1'));
      expect(state.leads[1]['id'], equals('2'));

      // Verify SnackBar notified the user that refresh is blocked
      expect(find.textContaining('Complete your current calls before refreshing'), findsOneWidget);

      // Verify API was NOT called again (refresh was blocked)
      expect(apiCallCount, equals(1));
    });

    testWidgets('Skipping with notes prompts confirmation dialog and marks lead processed', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/telecaller/batch-leads')) {
          return http.Response(
            json.encode({
              'success': true,
              'data': {
                'leads': [
                  {'id': '10', 'name': 'David Miller', 'mobile': '9123456780'},
                  {'id': '11', 'name': 'Eva Green', 'mobile': '9123456781'},
                ]
              }
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(json.encode({'success': true, 'data': {}}), 200);
      });

      ApiService.setClientForTesting(mockClient);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CallingDeskScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('David Miller'), findsOneWidget);

      final state = tester.state<CallingDeskScreenState>(find.byType(CallingDeskScreen));

      // Set outcomes visible and enter notes
      state.setVerifiedCallLogForTesting(
        VerifiedCallLog(
          isDialed: false,
          number: '9123456780',
          durationSeconds: 0,
          timestamp: 0,
          type: 0,
        ),
      );
      state.notesController.text = 'Important inquiry details';
      await tester.pumpAndSettle();

      // Tap "Skip this lead"
      final skipBtn = find.text('Skip this lead');
      await tester.ensureVisible(skipBtn);
      await tester.tap(skipBtn);
      await tester.pumpAndSettle();

      // Expect Discard Dialog
      expect(find.text('Discard Call Details?'), findsOneWidget);
      expect(find.text('Discard & Skip'), findsOneWidget);

      // Cancel first
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Still on David Miller
      expect(find.text('David Miller'), findsOneWidget);
      expect(CallingDeskScreen.sessionProcessedLeadIds.contains('10'), isFalse);

      // Tap Skip again and confirm
      await tester.tap(skipBtn);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard & Skip'));
      await tester.pumpAndSettle();

      // Now on Eva Green
      expect(find.text('Eva Green'), findsOneWidget);
      expect(CallingDeskScreen.sessionProcessedLeadIds.contains('10'), isTrue);
    });

    testWidgets('Skipping after dialing call prompts confirmation dialog with duration', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/telecaller/batch-leads')) {
          return http.Response(
            json.encode({
              'success': true,
              'data': {
                'leads': [
                  {'id': '20', 'name': 'Frank Castle', 'mobile': '9111222333'},
                  {'id': '21', 'name': 'Grace Hopper', 'mobile': '9111222334'},
                ]
              }
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(json.encode({'success': true, 'data': {}}), 200);
      });

      ApiService.setClientForTesting(mockClient);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CallingDeskScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final state = tester.state<CallingDeskScreenState>(find.byType(CallingDeskScreen));
      state.setVerifiedCallLogForTesting(
        VerifiedCallLog(
          isDialed: true,
          number: '9111222333',
          durationSeconds: 45,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          type: 2,
        ),
      );
      await tester.pumpAndSettle();

      // Tap "Skip this lead"
      final skipBtn = find.text('Skip this lead');
      await tester.ensureVisible(skipBtn);
      await tester.tap(skipBtn);
      await tester.pumpAndSettle();

      // Check dialog mentions the call placed
      expect(find.text('Discard Call Details?'), findsOneWidget);
      expect(find.textContaining('You placed a call (45s) to this contact'), findsOneWidget);

      await tester.tap(find.text('Discard & Skip'));
      await tester.pumpAndSettle();

      // Discarded and advanced to Grace Hopper
      expect(find.text('Grace Hopper'), findsOneWidget);
      expect(CallingDeskScreen.sessionProcessedLeadIds.contains('20'), isTrue);
    });

    testWidgets('Empty queue refresh loads fresh batch and filters session processed leads', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      int callCount = 0;
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/telecaller/batch-leads')) {
          callCount++;
          if (callCount == 1) {
            // First batch is empty
            return http.Response(
              json.encode({
                'success': true,
                'data': {'leads': []}
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          } else {
            // Second batch: Lead 50 (already processed) and Lead 51 (fresh)
            return http.Response(
              json.encode({
                'success': true,
                'data': {
                  'leads': [
                    {'id': '50', 'name': 'Old Lead', 'mobile': '9000000050'},
                    {'id': '51', 'name': 'Fresh Lead', 'mobile': '9000000051'},
                  ]
                }
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
        }
        return http.Response(json.encode({'success': true, 'data': {}}), 200);
      });

      ApiService.setClientForTesting(mockClient);

      // Mark Lead 50 as already processed in this session
      CallingDeskScreen.markLeadProcessed('50');

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CallingDeskScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Empty batch leads to "All Calls Completed!" UI
      expect(find.text('All Calls Completed!'), findsOneWidget);

      // Tap "Fetch Next Contacts Batch"
      final fetchNextBtn = find.text('Fetch Next Contacts Batch');
      await tester.tap(fetchNextBtn);
      await tester.pumpAndSettle();

      // Fresh Lead 51 should be shown; Old Lead 50 should be filtered out
      expect(find.text('Fresh Lead'), findsOneWidget);
      expect(find.text('Old Lead'), findsNothing);
    });
  });

  group('IVR / Voicemail Tracking & Outcome Selection Tests', () {
    test('timingTierLabel maps VOICEMAIL to IVR / Voicemail', () {
      final session = CallSessionEvent(
        number: '9876543210',
        durationSeconds: 12,
        timingClassification: 'VOICEMAIL',
        startTime: DateTime.now().subtract(const Duration(seconds: 12)),
        endTime: DateTime.now(),
      );
      expect(session.timingTierLabel, 'IVR / Voicemail');
      expect(session.durationFormatted, '12s');
    });

    test('VerifiedCallLog isVoicemailLikely detects calls between 1s and 18s', () {
      final log0 = VerifiedCallLog(isDialed: true, number: '123', durationSeconds: 0, timestamp: 0, type: 2);
      final log12 = VerifiedCallLog(isDialed: true, number: '123', durationSeconds: 12, timestamp: 0, type: 2);
      final log18 = VerifiedCallLog(isDialed: true, number: '123', durationSeconds: 18, timestamp: 0, type: 2);
      final log35 = VerifiedCallLog(isDialed: true, number: '123', durationSeconds: 35, timestamp: 0, type: 2);

      expect(log0.isVoicemailLikely, isFalse);
      expect(log12.isVoicemailLikely, isTrue);
      expect(log18.isVoicemailLikely, isTrue);
      expect(log35.isVoicemailLikely, isFalse);
    });

    testWidgets('Short calls (1-18s) require explicit selection; submitting IVR/Voicemail sends timing_classification VOICEMAIL', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      Map<String, dynamic>? submittedBody;
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/telecaller/batch-leads')) {
          return http.Response(
            json.encode({
              'success': true,
              'data': {
                'leads': [
                  {'id': '77', 'name': 'Voicemail Test Lead', 'mobile': '9898989898', 'source': 'MAIN'},
                ]
              }
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path.contains('/telecaller/calls/77/complete')) {
          submittedBody = json.decode(request.body) as Map<String, dynamic>;
          return http.Response(
            json.encode({
              'success': true,
              'data': {'id': 77, 'status': 'completed'},
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(json.encode({'success': true, 'data': {}}), 200);
      });

      ApiService.setClientForTesting(mockClient);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CallingDeskScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final state = tester.state<CallingDeskScreenState>(find.byType(CallingDeskScreen));

      // 1. Simulate verified short call (8s - likely voicemail greeting)
      state.setVerifiedCallLogForTesting(
        VerifiedCallLog(
          isDialed: true,
          number: '9898989898',
          durationSeconds: 8,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          type: 2,
        ),
      );
      await tester.pumpAndSettle();

      // Ensure no disposition is auto-selected
      expect(state.selectedDisposition, isEmpty);
      expect(find.text('📞 Short Call (8s) • Choose Outcome'), findsOneWidget);
      expect(find.text('IVR / Voicemail'), findsOneWidget);

      // 2. Try to save without selecting an outcome -> validation snackbar triggers
      final saveBtn = find.text('Save & Next');
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(find.text('Please select a call outcome before saving.'), findsOneWidget);
      expect(submittedBody, isNull); // Blocked from submitting

      // 3. Select 'IVR / Voicemail'
      final vmRadio = find.text('IVR / Voicemail');
      await tester.ensureVisible(vmRadio);
      await tester.tap(vmRadio);
      await tester.pumpAndSettle();

      expect(state.selectedDisposition, 'IVR_VOICEMAIL');
      expect(find.text('✗ Not Connected (Voicemail)'), findsOneWidget);

      // 4. Submit with IVR / Voicemail
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      // Verify payload sent to backend
      expect(submittedBody, isNotNull);
      expect(submittedBody!['call_status'], 'IVR / Voicemail');
      expect(submittedBody!['timing_classification'], 'VOICEMAIL');
      expect(submittedBody!['call_duration'], 8);
    });

    testWidgets('CallReportsScreen displays Voicemail badge for calls with timing_classification VOICEMAIL', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/telecaller/reports/summary')) {
          return http.Response(
            json.encode({
              'success': true,
              'data': {
                'total_calls': 1,
                'connected_calls': 0,
                'timing_tiers': {
                  'voicemail': 1,
                  'not_connected': 0,
                  'connected_short': 0,
                  'connected_conversation': 0,
                },
              }
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path.contains('/telecaller/calls')) {
          return http.Response(
            json.encode({
              'success': true,
              'data': {
                'calls': [
                  {
                    'id': 101,
                    'customer_name': 'Voicemail User',
                    'customer_mobile': '9876543210',
                    'call_status': 'IVR / Voicemail',
                    'call_duration': 14,
                    'timing_classification': 'VOICEMAIL',
                    'source': 'MAIN',
                  }
                ],
                'pagination': {'total': 1, 'pages': 1, 'current_page': 1}
              }
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(json.encode({'success': true, 'data': {}}), 200);
      });

      ApiService.setClientForTesting(mockClient);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CallReportsScreen(initialTabIndex: 1),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Voicemail User'), findsOneWidget);
      expect(find.text('IVR / Voicemail'), findsOneWidget);
      expect(find.text('14s • Voicemail'), findsOneWidget);
    });
  });
}
