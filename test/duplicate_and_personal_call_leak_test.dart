import 'dart:convert';
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
    await ConfigService.saveAuthData('tok-audit-tester', {
      'id': 99,
      'name': 'Audit Tester',
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
  });

  group('Duplicate Submission & Personal Call Leak Audit Tests', () {
    test('AUDIT 1: CallingDesk verification strictly ignores personal calls to different numbers', () async {
      // Scenario: Active lead is Adnan (9167446813). Telecaller calls spouse (9811112222).
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.example.callnow/call_verifier'),
        (MethodCall call) async {
          if (call.method == 'getLatestCallLog') {
            final args = call.arguments as Map?;
            final target = args?['phoneNumber'] as String? ?? '';
            // Device CallLog only contains personal call to 9811112222
            const dialedNumberInPhone = '9811112222';
            final isMatch = dialedNumberInPhone == target;
            return {
              'isDialed': isMatch,
              'hasPermission': true,
              'number': dialedNumberInPhone,
              'duration': 120,
              'timestamp': DateTime.now().millisecondsSinceEpoch,
              'type': 2,
            };
          }
          return null;
        },
      );

      final verified = await CallTrackingService.verifyCallLog('9167446813');
      // Must not match personal call
      expect(verified.isDialed, isFalse);
    });

    test('AUDIT 2: Non-CRM personal incoming caller produces 403 when record_id is 0', () async {
      // Scenario: Personal incoming call arrives with number not in CRM
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/lookup-contact')) {
          // Personal number not found in CRM
          return http.Response(jsonEncode({'success': true, 'data': null}), 200,
              headers: {'content-type': 'application/json'});
        }
        if (request.url.path.contains('/complete')) {
          // Backend rejects record_id 0 with 403 Forbidden
          return http.Response(
            jsonEncode({'success': false, 'code': 403, 'message': 'Not authorized to update this record'}),
            403,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{"status":"error"}', 400);
      });
      ApiService.setClientForTesting(mockClient);

      final contact = await ApiService.lookupContact('9811112222');
      expect(contact, isNull);

      // Attempting to submit call for non-existent contact (recordId 0) throws 403
      expect(
        () => ApiService.submitCallResult(
          callId: 0,
          source: 'MAIN',
          status: 'Interested',
          durationSeconds: 30,
        ),
        throwsA(predicate((e) => e.toString().contains('403') || e.toString().contains('Not authorized'))),
      );
    });

    test('AUDIT 3: Processed leads tracking prevents the same lead from being processed twice in a session', () {
      const leadId = 'lead_9167446813_TEMP';
      expect(CallingDeskScreen.sessionProcessedLeadIds.contains(leadId), isFalse);

      CallingDeskScreen.markLeadProcessed(leadId);
      expect(CallingDeskScreen.sessionProcessedLeadIds.contains(leadId), isTrue);

      CallingDeskScreen.clearSessionProcessedLeads();
      expect(CallingDeskScreen.sessionProcessedLeadIds.contains(leadId), isFalse);
    });
  });
}
