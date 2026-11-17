import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:callnow_new/services/api_service.dart';
import 'package:callnow_new/services/call_tracking_service.dart';
import 'package:callnow_new/services/config_service.dart';
import 'package:callnow_new/services/secure_storage_service.dart';
import 'package:callnow_new/services/today_dialed_history_service.dart';
import 'package:phone_state_background/phone_state_background.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MemoryTodayDialedHistoryBackend memoryBackend;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SecureStorageService.setBackendForTesting(MemorySecureStorageBackend());
    memoryBackend = MemoryTodayDialedHistoryBackend();
    TodayDialedHistoryService.setBackendForTesting(memoryBackend);
    await ConfigService.setBaseUrl('https://crm.callnow.example.com/api/v1');
    await ConfigService.saveAuthData('tok-today-test', {
      'id': 10,
      'name': 'Test Telecaller',
      'role': 'Officer',
    });
  });

  tearDown(() async {
    await TodayDialedHistoryService.instance.clearAll();
    TodayDialedHistoryService.resetBackend();
    SecureStorageService.resetBackend();
    ApiService.resetClient();
  });

  group('TodayDialedHistoryService CRUD & Number Matching Tests', () {
    test('Records dialed call and accurately finds by last 10 digits', () async {
      await TodayDialedHistoryService.instance.recordDialedCall(
        recordId: 501,
        leadId: 101,
        name: 'Adnan Ansari',
        phoneNumber: '9167446813',
        company: 'Blue Star Ltd',
        status: 'Interested',
        duration: 45,
      );

      // Verify matching across multiple dialing formats
      final foundClean = await TodayDialedHistoryService.instance.findDialedCall('9167446813');
      expect(foundClean, isNotNull);
      expect(foundClean!['name'], equals('Adnan Ansari'));
      expect(foundClean['record_id'], equals(501));

      final foundWithCountryCode = await TodayDialedHistoryService.instance.findDialedCall('+919167446813');
      expect(foundWithCountryCode, isNotNull);
      expect(foundWithCountryCode!['name'], equals('Adnan Ansari'));

      final foundWithLeadingZero = await TodayDialedHistoryService.instance.findDialedCall('09167446813');
      expect(foundWithLeadingZero, isNotNull);

      // Verify that non-dialed number returns null
      final notFound = await TodayDialedHistoryService.instance.findDialedCall('9876543210');
      expect(notFound, isNull);
    });

    test('wasDialedToday returns true only for calls placed today', () async {
      await TodayDialedHistoryService.instance.recordDialedCall(
        recordId: 502,
        name: 'Kavita Singh',
        phoneNumber: '+91 98200 12345',
        duration: 20,
      );

      expect(await TodayDialedHistoryService.instance.wasDialedToday('9820012345'), isTrue);
      expect(await TodayDialedHistoryService.instance.wasDialedToday('+919820012345'), isTrue);

      // Personal call number
      expect(await TodayDialedHistoryService.instance.wasDialedToday('9988776655'), isFalse);
    });

    test('getTodayCallsCount and getTodayTotalDuration sum metrics accurately', () async {
      await TodayDialedHistoryService.instance.recordDialedCall(
        phoneNumber: '9167446813',
        duration: 50,
      );
      await TodayDialedHistoryService.instance.recordDialedCall(
        phoneNumber: '9820012345',
        duration: 70,
      );

      expect(await TodayDialedHistoryService.instance.getTodayCallsCount(), equals(2));
      expect(await TodayDialedHistoryService.instance.getTodayTotalDuration(), equals(120));
    });
  });

  group('Personal Call Filtering & Customer Callback Verification', () {
    test('Personal incoming call (wife/family) is strictly ignored when not in Today\'s Dialed History', () async {
      const wifePhoneNumber = '9876500000';

      // 1. Assert wife number is NOT in today's dialed history
      expect(await TodayDialedHistoryService.instance.wasDialedToday(wifePhoneNumber), isFalse);

      // 2. Simulate incoming call connected from wife
      await phoneStateBackgroundCallbackHandler(
        PhoneStateBackgroundEvent.incomingend,
        wifePhoneNumber,
        180, // 3 min call with wife
      );

      // 3. Verify that pending_post_call_number was NOT saved!
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('pending_post_call_number'), isNull);
    });

    test('Customer callback is recognized when present in Today\'s Dialed History', () async {
      const customerNumber = '9167446813';

      // 1. Telecaller dialed customer earlier today
      await TodayDialedHistoryService.instance.recordDialedCall(
        recordId: 301,
        name: 'Rajesh Khanna',
        phoneNumber: customerNumber,
        company: 'Khanna Textiles',
      );

      // 2. Customer calls back
      await phoneStateBackgroundCallbackHandler(
        PhoneStateBackgroundEvent.incomingend,
        customerNumber,
        60,
      );

      // 3. Verify callback is saved as pending post call for HomeScreen prompt
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('pending_post_call_number'), equals(customerNumber));
      expect(prefs.getInt('pending_post_call_duration'), equals(60));
    });
  });

  group('Server Synchronization & Logout Lifecycle Tests', () {
    test('syncWithServer fetches today\'s dialed calls and populates local database', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/telecaller/calls') && request.url.queryParameters['period'] == 'today') {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'calls': [
                  {
                    'id': 1001,
                    'record_id': 201,
                    'name': 'Pooja Hegde',
                    'phone_number': '9812345678',
                    'company': 'Media Corp',
                    'call_status': 'Interested',
                    'call_duration': 65,
                    'timing_classification': 'CONNECTED_CONVERSATION',
                  },
                  {
                    'id': 1002,
                    'record_id': 202,
                    'name': 'Vikram Rathore',
                    'phone_number': '9876543210',
                    'company': 'Security Ltd',
                    'call_status': 'Ringing',
                    'call_duration': 0,
                    'timing_classification': 'NOT_CONNECTED',
                  },
                ],
                'pagination': {'total': 2, 'total_pages': 1}
              }
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{"status":"error"}', 400);
      });
      ApiService.setClientForTesting(mockClient);

      final syncedCount = await TodayDialedHistoryService.instance.syncWithServer();
      expect(syncedCount, equals(2));

      expect(await TodayDialedHistoryService.instance.wasDialedToday('9812345678'), isTrue);
      expect(await TodayDialedHistoryService.instance.wasDialedToday('9876543210'), isTrue);

      final callPooja = await TodayDialedHistoryService.instance.findDialedCall('9812345678');
      expect(callPooja!['name'], equals('Pooja Hegde'));
      expect(callPooja['duration'], equals(65));
    });

    test('clearAll wipes Today\'s Dialed History on user logout', () async {
      await TodayDialedHistoryService.instance.recordDialedCall(
        phoneNumber: '9167446813',
        name: 'Adnan Ansari',
      );
      expect(await TodayDialedHistoryService.instance.getTodayCallsCount(), equals(1));

      // Simulate logout
      await ConfigService.clearAuthData();

      expect(await TodayDialedHistoryService.instance.getTodayCallsCount(), equals(0));
      expect(await TodayDialedHistoryService.instance.wasDialedToday('9167446813'), isFalse);
    });
  });
}
