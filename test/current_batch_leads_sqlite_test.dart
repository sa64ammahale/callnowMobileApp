import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:callnow_new/services/api_service.dart';
import 'package:callnow_new/services/config_service.dart';
import 'package:callnow_new/services/secure_storage_service.dart';
import 'package:callnow_new/services/today_dialed_history_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MemoryTodayDialedHistoryBackend memoryBackend;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SecureStorageService.setBackendForTesting(MemorySecureStorageBackend());
    memoryBackend = MemoryTodayDialedHistoryBackend();
    TodayDialedHistoryService.setBackendForTesting(memoryBackend);
    await ConfigService.setBaseUrl('https://crm.callnow.example.com/api/v1');
    await ConfigService.saveAuthData('tok-batch-test', {
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

  group('15-Number SQLite Batch Queue Tests', () {
    test('Stores 15 batch leads from server into SQLite with 15-min expiry', () async {
      final mock15Leads = List.generate(15, (i) => {
        'id': 100 + i,
        'record_id': 100 + i,
        'name': 'Lead Customer $i',
        'mobile': '98000000${i.toString().padLeft(2, '0')}',
        'company': 'Company $i',
        'source': 'BATCH',
      });

      final expiry = DateTime.now().add(const Duration(minutes: 15));
      await TodayDialedHistoryService.instance.saveBatchLeads(mock15Leads, expiresAt: expiry);

      // Verify uncalled count is exactly 15
      final uncalledCount = await TodayDialedHistoryService.instance.getUncalledBatchLeadsCount();
      expect(uncalledCount, equals(15));

      // Verify leads can be retrieved in sort order with full server data
      final activeLeads = await TodayDialedHistoryService.instance.getActiveBatchLeads();
      expect(activeLeads.length, equals(15));
      expect(activeLeads.first['name'], equals('Lead Customer 0'));
      expect(activeLeads.first['mobile'], equals('9800000000'));
      expect(activeLeads.first['local_batch_status'], equals('PENDING'));
      expect(activeLeads.last['name'], equals('Lead Customer 14'));
      expect(activeLeads.last['mobile'], equals('9800000014'));
    });

    test('Tracks call lifecycle in SQLite: PENDING -> DIALED -> STATUS UPDATED -> COMPLETED', () async {
      final initialLeads = [
        {
          'id': 201,
          'name': 'Adnan Ansari',
          'mobile': '9167446813',
          'company': 'Tech Corp',
        },
        {
          'id': 202,
          'name': 'Suresh Raina',
          'mobile': '9876543210',
          'company': 'Sports Ltd',
        },
      ];

      final expiry = DateTime.now().add(const Duration(minutes: 15));
      await TodayDialedHistoryService.instance.saveBatchLeads(initialLeads, expiresAt: expiry);

      // Step 1: Check initial PENDING status
      var lead = await TodayDialedHistoryService.instance.getBatchLead('9167446813');
      expect(lead, isNotNull);
      expect(lead!['local_batch_status'], equals('PENDING'));
      expect(lead['local_call_duration'], equals(0));

      // Step 2: Telecaller taps Call -> marks DIALED
      await TodayDialedHistoryService.instance.updateBatchLeadStatus(
        '9167446813',
        status: 'DIALED',
      );
      lead = await TodayDialedHistoryService.instance.getBatchLead('9167446813');
      expect(lead!['local_batch_status'], equals('DIALED'));

      // Step 3: Call finishes, telecaller taps "Get Status" -> updates duration and outcome
      await TodayDialedHistoryService.instance.updateBatchLeadStatus(
        '9167446813',
        status: 'DIALED',
        duration: 48,
        callStatus: 'Interested',
      );
      lead = await TodayDialedHistoryService.instance.getBatchLead('9167446813');
      expect(lead!['local_batch_status'], equals('DIALED'));
      expect(lead['local_call_duration'], equals(48));
      expect(lead['local_call_status'], equals('Interested'));

      // Step 4: Telecaller taps Save & Next -> server confirms -> marks COMPLETED
      await TodayDialedHistoryService.instance.updateBatchLeadStatus(
        '9167446813',
        status: 'COMPLETED',
        duration: 48,
        callStatus: 'Interested',
      );
      // Also moves into TodayDialedHistory table for callback matching & XP
      await TodayDialedHistoryService.instance.recordDialedCall(
        recordId: 201,
        name: 'Adnan Ansari',
        phoneNumber: '9167446813',
        duration: 48,
        status: 'Interested',
      );

      // Verify active uncompleted queue now has 1 lead remaining (Suresh Raina)
      final remainingActive = await TodayDialedHistoryService.instance.getActiveBatchLeads();
      expect(remainingActive.length, equals(1));
      expect(remainingActive.first['name'], equals('Suresh Raina'));

      // Verify today's dialed history captured Adnan Ansari
      expect(await TodayDialedHistoryService.instance.wasDialedToday('9167446813'), isTrue);
    });

    test('Auto-fill dynamic top-up: 3 remaining uncalled + 12 fetched = exactly 15 total uncalled', () async {
      // Telecaller has 3 uncalled leads currently in batch (1 active preserved + 2 upcoming)
      final existing3Leads = [
        {'id': 301, 'name': 'Active Preserved Lead', 'mobile': '9811111111'},
        {'id': 302, 'name': 'Upcoming Lead 1', 'mobile': '9822222222'},
        {'id': 303, 'name': 'Upcoming Lead 2', 'mobile': '9833333333'},
      ];

      final initialExpiry = DateTime.now().add(const Duration(minutes: 2)); // near expiry!
      await TodayDialedHistoryService.instance.saveBatchLeads(existing3Leads, expiresAt: initialExpiry);

      final currentUncalled = await TodayDialedHistoryService.instance.getUncalledBatchLeadsCount();
      expect(currentUncalled, equals(3));

      // Calculate needed top-up
      final needed = 15 - currentUncalled; // 15 - 3 = 12
      expect(needed, equals(12));

      // Simulate fetching 12 new leads from server
      final fresh12Leads = List.generate(12, (i) => {
        'id': 400 + i,
        'name': 'Top-Up Lead $i',
        'mobile': '99000000${i.toString().padLeft(2, '0')}',
        'company': 'TopUp Co $i',
      });

      final renewedExpiry = DateTime.now().add(const Duration(minutes: 15));
      await TodayDialedHistoryService.instance.appendBatchLeads(fresh12Leads, expiresAt: renewedExpiry);

      // Total uncalled must now equal EXACTLY 15 ("not low not more")
      final totalUncalledAfterTopUp = await TodayDialedHistoryService.instance.getUncalledBatchLeadsCount();
      expect(totalUncalledAfterTopUp, equals(15));

      // First lead is still Active Preserved Lead
      final allActive = await TodayDialedHistoryService.instance.getActiveBatchLeads();
      expect(allActive.length, equals(15));
      expect(allActive.first['name'], equals('Active Preserved Lead'));
      expect(allActive.last['name'], equals('Top-Up Lead 11'));
    });

    test('Wipes batch queue on logout alongside today dialed history', () async {
      await TodayDialedHistoryService.instance.saveBatchLeads([
        {'id': 501, 'name': 'Logout Test Lead', 'mobile': '9167446813'},
      ], expiresAt: DateTime.now().add(const Duration(minutes: 15)));

      expect(await TodayDialedHistoryService.instance.getUncalledBatchLeadsCount(), equals(1));

      // User logs out
      await ConfigService.clearAuthData();

      // SQLite current_batch_leads is completely cleared
      expect(await TodayDialedHistoryService.instance.getUncalledBatchLeadsCount(), equals(0));
      expect(await TodayDialedHistoryService.instance.getActiveBatchLeads(), isEmpty);
    });
  });
}
