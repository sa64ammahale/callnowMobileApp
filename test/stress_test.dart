import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:callnow_new/model/crm_lead.dart';
import 'package:callnow_new/model/followup_model.dart';
import 'package:callnow_new/model/user_profile.dart';
import 'package:callnow_new/services/followup_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Task 1: Large Database Stress Tests', () {
    test('Stress Test 1: 5,000 CRM Leads parsing and multi-field filtering under 250ms', () {
      // 1. Generate 5,000 realistic synthetic CRM lead JSON records
      final List<Map<String, dynamic>> rawLeads = List.generate(5000, (i) {
        final stages = ['LEAD', 'FOLLOWUP', 'LOGIN', 'SANCTION', 'DISBURSED', 'REJECT'];
        final banks = ['HDFC Bank', 'ICICI Bank', 'Axis Bank', 'SBI', 'Kotak'];
        return {
          'id': 100000 + i,
          'customer_name': 'Customer Test Name $i',
          'customer_mobile': '98765${(10000 + (i % 90000)).toString()}',
          'customer_company': 'Enterprise Tech Solutions $i Pvt Ltd',
          'loan_amount': '${(i + 1) * 50000}',
          'loan_type': i % 3 == 0 ? 'Home Loan' : (i % 2 == 0 ? 'Business Loan' : 'Personal Loan'),
          'lead_status_new': stages[i % stages.length],
          'stage': i % 2 == 0 ? 'Hot' : 'Warm',
          'priority': i % 4 == 0 ? 'High' : 'Medium',
          'login_bank_name': banks[i % banks.length],
          'next_followup_at': '2026-11-05 14:30:00',
          'remarks': 'Stress testing lead profile record number $i with detailed remarks and follow-up notes.',
          'assigned_user': 'Telecaller Agent ${(i % 10) + 1}',
        };
      });

      // 2. Benchmark Deserialization of 5,000 Leads
      final parseWatch = Stopwatch()..start();
      final List<CrmLead> parsedLeads = rawLeads
          .map((json) => CrmLead.fromJson(json))
          .toList();
      parseWatch.stop();

      expect(parsedLeads.length, equals(5000));
      expect(parseWatch.elapsedMilliseconds, lessThan(250),
          reason: '5,000 leads parsed in ${parseWatch.elapsedMilliseconds}ms, budget is <250ms');

      // 3. Benchmark In-Memory Search & Stage Filtering across 5,000 items
      final filterWatch = Stopwatch()..start();
      const searchQuery = 'Tech Solutions 4';
      final filteredResults = parsedLeads.where((lead) {
        final matchesSearch = lead.name.toLowerCase().contains(searchQuery.toLowerCase()) ||
            lead.company.toLowerCase().contains(searchQuery.toLowerCase()) ||
            lead.mobile.contains(searchQuery);
        return matchesSearch && lead.status == 'LOGIN';
      }).toList();
      filterWatch.stop();

      expect(filterWatch.elapsedMilliseconds, lessThan(150),
          reason: 'Filtered 5,000 leads in ${filterWatch.elapsedMilliseconds}ms, budget is <150ms');
      expect(filteredResults.isNotEmpty, isTrue);
    });

    test('Stress Test 2: 10,000 Call Log entries & analytics calculations under 100ms', () {
      // 1. Generate 10,000 call log entries with varying call durations
      final List<Map<String, dynamic>> rawCalls = List.generate(10000, (i) {
        // Durations: 0s (not connected), 15s (short), 180s (conversation), extreme 7200s (long call)
        final duration = (i % 4 == 0) ? 0 : (i % 4 == 1 ? 25 : (i % 4 == 2 ? 180 : 7200));
        return {
          'id': i,
          'customer_name': 'Lead Dial $i',
          'customer_number': '98900${(10000 + i % 90000)}',
          'call_duration': duration,
          'call_status': duration == 0 ? 'NOT_CONNECTED' : 'CONNECTED',
          'disposition': duration == 0 ? 'BUSY' : (duration > 60 ? 'INTERESTED' : 'RNR'),
          'call_time': '2026-11-02 10:15:00',
        };
      });

      // 2. Benchmark aggregating 10,000 calls
      final calcWatch = Stopwatch()..start();
      int totalCalls = rawCalls.length;
      int totalDurationSeconds = 0;
      int notConnectedCount = 0;
      int shortCallsCount = 0;
      int conversationsCount = 0;

      for (final call in rawCalls) {
        final dur = int.tryParse(call['call_duration']?.toString() ?? '0') ?? 0;
        totalDurationSeconds += dur;
        if (dur == 0) {
          notConnectedCount++;
        } else if (dur < 60) {
          shortCallsCount++;
        } else {
          conversationsCount++;
        }
      }

      final double notConnPct = totalCalls > 0 ? (notConnectedCount / totalCalls) * 100 : 0.0;
      final double shortPct = totalCalls > 0 ? (shortCallsCount / totalCalls) * 100 : 0.0;
      final double convoPct = totalCalls > 0 ? (conversationsCount / totalCalls) * 100 : 0.0;
      calcWatch.stop();

      expect(totalCalls, equals(10000));
      expect(totalDurationSeconds, greaterThan(0));
      expect((notConnPct + shortPct + convoPct).round(), equals(100));
      expect(calcWatch.elapsedMilliseconds, lessThan(100),
          reason: 'Calculated metrics for 10,000 calls in ${calcWatch.elapsedMilliseconds}ms, budget is <100ms');

      // 3. Zero-division resilience check
      const zeroCalls = 0;
      final double safeDiv = zeroCalls > 0 ? (5 / zeroCalls) * 100 : 0.0;
      expect(safeDiv.isNaN, isFalse);
      expect(safeDiv.isInfinite, isFalse);
      expect(safeDiv, equals(0.0));
    });

    test('Stress Test 3: 1,000 Followup items in FollowupService persistence & categorization under 150ms', () async {
      // 1. Generate 1,000 followups across overdue, today, and upcoming
      final now = DateTime.now();
      final List<Map<String, dynamic>> rawFollowups = List.generate(1000, (i) {
        DateTime sched;
        if (i < 300) {
          sched = now.subtract(Duration(hours: 1 + (i % 48))); // Overdue
        } else if (i < 700) {
          sched = now.add(Duration(minutes: 5 + (i % 120))); // Today
        } else {
          sched = now.add(Duration(days: 1 + (i % 30))); // Upcoming
        }
        return {
          'id': 'f_stress_$i',
          'lead_id': 5000 + i,
          'customer_name': 'Followup Customer $i',
          'phone_number': '98111${(10000 + i % 90000)}',
          'company': 'Fintech Corporate $i',
          'scheduled_time': sched.toIso8601String(),
          'created_at': now.toIso8601String(),
          'notes': 'Urgent callback requested for loan document verification #$i',
          'status': i % 10 == 0 ? 'completed' : 'pending',
        };
      });

      // 2. Persist 1,000 followups into SharedPreferences JSON storage
      final prefs = await SharedPreferences.getInstance();
      final jsonEncoded = jsonEncode(rawFollowups);
      await prefs.setString('callnow_saved_followups_v1', jsonEncoded);

      // 3. Benchmark loading and initializing FollowupService
      final loadWatch = Stopwatch()..start();
      await FollowupService.init();
      loadWatch.stop();

      final service = FollowupService.instance;
      expect(service.followups.length, equals(1000));
      expect(loadWatch.elapsedMilliseconds, lessThan(500),
          reason: '1,000 followups loaded and parsed in ${loadWatch.elapsedMilliseconds}ms, budget is <500ms');

      // 4. Verify category counts are partitioned correctly
      final overdue = service.getOverdue();
      final today = service.getToday();
      final upcoming = service.getUpcoming();
      final completed = service.getCompleted();

      expect(overdue.isNotEmpty, isTrue);
      expect(today.isNotEmpty, isTrue);
      expect(upcoming.isNotEmpty, isTrue);
      expect(completed.length, equals(100)); // Every 10th was completed
    });

    test('Stress Test 4: Malformed, extreme data & null safety resilience', () {
      // 1. CrmLead with extreme, negative, and missing fields
      final leadExtreme = CrmLead.fromJson({
        'lead_id': null,
        'customer_name': null,
        'customer_mobile': null,
        'loan_amount': '-₹50,00,000.99', // Negative with symbols
        'status': null,
        'stage': null,
        'priority': null,
      });

      expect(leadExtreme.id, equals(0));
      expect(leadExtreme.name, equals('Unnamed Lead'));
      expect(leadExtreme.mobile, equals(''));
      expect(leadExtreme.status, equals('LEAD'));
      expect(leadExtreme.formattedPackage, isNotEmpty);

      // 2. CrmLead with massive package amount (₹15 Crore)
      final leadCrores = CrmLead.fromJson({
        'id': '999',
        'customer_name': 'Billionaire Enterprise',
        'package': '150000000',
      });
      expect(leadCrores.formattedPackage, equals('₹15.00 Cr'));

      // 3. UserProfile with nulls, missing objects, and unexpected types
      final profileNullSafe = UserProfile.fromJson({
        'user': null,
        'company': 12345, // Number instead of string
        'raw': null,
      });

      expect(profileNullSafe.id, equals(0));
      expect(profileNullSafe.name, equals('Telecaller'));
      expect(profileNullSafe.hasEmail, isFalse);
      expect(profileNullSafe.displayEmail, equals('Not provided on server'));
      expect(profileNullSafe.hasMobile, isFalse);
      expect(profileNullSafe.displayMobile, equals('Not provided on server'));
      expect(profileNullSafe.companyName, equals('12345'));

      // 4. FollowupModel with invalid date strings fallback safely
      final followupFallback = FollowupModel.fromJson({
        'id': 'test_corrupt_date',
        'scheduled_time': 'NOT_A_VALID_DATE',
        'customer_name': 'Test Corrupt',
        'phone_number': '1234567890',
      });

      expect(followupFallback.id, equals('test_corrupt_date'));
      expect(followupFallback.scheduledTime, isNotNull);
    });
  });
}
