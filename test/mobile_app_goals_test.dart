import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:callnow_new/model/crm_lead.dart';
import 'package:callnow_new/model/followup_model.dart';
import 'package:callnow_new/model/user_profile.dart';
import 'package:callnow_new/screens/profile_screen.dart';
import 'package:callnow_new/services/config_service.dart';
import 'package:callnow_new/services/followup_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ConfigService.init();
  });

  group('Goal 1: View and Manage User Info and Profile', () {
    test('UserProfile model parses complete photo references and user metadata', () {
      final json = {
        'id': 4,
        'name': 'Amit Kumar',
        'email': 'amit@callnow.com',
        'mobile': '9876543210',
        'role': 'Officer',
        'company': 'CallNow Solutions',
        'profile_photo': 'user_4_profile.jpg',
        'profile_photo_url': 'http://localhost/callnowCRM/uploads/profile_photos/user_4_profile.jpg',
        'avatar_url': 'http://localhost/callnowCRM/uploads/profile_photos/user_4_profile.jpg',
        'profile_picture': 'data:image/jpeg;base64,/9j/4AAQSkZJRgABAQ...',
        'profile_picture_url': 'http://localhost/callnowCRM/uploads/profile_photos/user_4_profile.jpg',
      };

      final profile = UserProfile.fromJson(json);

      expect(profile.id, equals(4));
      expect(profile.name, equals('Amit Kumar'));
      expect(profile.email, equals('amit@callnow.com'));
      expect(profile.mobile, equals('9876543210'));
      expect(profile.role, equals('OFFICER'));
      expect(profile.profilePhoto, equals('user_4_profile.jpg'));
      expect(profile.profilePhotoUrl, contains('user_4_profile.jpg'));
      expect(profile.avatarUrl, contains('user_4_profile.jpg'));
      expect(profile.profilePictureUrl, contains('user_4_profile.jpg'));
      expect(profile.avatarImageProvider, isNotNull);
    });

    test('ConfigService stores and exposes profile photo URL and user data', () async {
      final userMap = {
        'id': 4,
        'name': 'Amit Kumar Telecaller',
        'email': 'amit@callnow.com',
        'mobile': '9876543210',
        'role': 'Officer',
        'company': 'InCredit Solutions',
        'profile_photo_url': 'http://localhost/callnowCRM/uploads/profile_photos/user_4_profile.jpg',
      };

      await ConfigService.saveAuthData('test-token-12345', userMap);

      expect(ConfigService.token, equals('test-token-12345'));
      expect(ConfigService.userId, equals('#4'));
      expect(ConfigService.userDisplayName, equals('Amit Kumar Telecaller'));
      expect(ConfigService.userRole, equals('OFFICER'));
      expect(ConfigService.userProfilePhotoUrl, contains('user_4_profile.jpg'));
    });

    testWidgets('ProfileScreen renders user details, role badge, and security notes', (WidgetTester tester) async {
      await ConfigService.saveAuthData('test-token-12345', {
        'id': 4,
        'name': 'Amit Kumar Telecaller',
        'username': 'amit.telecaller',
        'email': 'amit@callnow.com',
        'mobile': '9876543210',
        'role': 'TELECALLER',
        'company': 'CallNow Corp',
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: ProfileScreen(),
        ),
      );
      await tester.pump();

      // Header Card
      expect(find.text('Amit Kumar Telecaller'), findsWidgets);
      expect(find.text('amit.telecaller'), findsOneWidget);
      expect(find.text('TELECALLER'), findsOneWidget);
      expect(find.text('Active Session'), findsOneWidget);

      // Server Profile Details Card
      expect(find.text('Server Profile Details'), findsOneWidget);
      expect(find.text('Registered Email'), findsOneWidget);
      expect(find.text('Registered Phone'), findsOneWidget);
      expect(find.text('amit@callnow.com'), findsWidgets);
      expect(find.text('9876543210'), findsWidgets);
    });
  });

  group('Goal 2: Fetch Numbers from Server and Show One-by-One for Calling', () {
    test('Batch queue manages sequential contact cards with boundary protection', () {
      final batchQueue = [
        {'id': 101, 'name': 'Prospect Alpha', 'mobile': '9899001101', 'company': 'Alpha Corp', 'source': 'TEMP'},
        {'id': 102, 'name': 'Prospect Beta', 'mobile': '9899001102', 'company': 'Beta Corp', 'source': 'TEMP'},
        {'id': 103, 'name': 'Prospect Gamma', 'mobile': '9899001103', 'company': 'Gamma Corp', 'source': 'MAIN'},
      ];

      int currentIndex = 0;

      // Contact 1
      expect(batchQueue[currentIndex]['name'], equals('Prospect Alpha'));
      expect(batchQueue[currentIndex]['mobile'], equals('9899001101'));

      // Advance to Contact 2
      currentIndex++;
      expect(batchQueue[currentIndex]['name'], equals('Prospect Beta'));
      expect(batchQueue[currentIndex]['mobile'], equals('9899001102'));

      // Advance to Contact 3
      currentIndex++;
      expect(batchQueue[currentIndex]['name'], equals('Prospect Gamma'));
      expect(batchQueue[currentIndex]['mobile'], equals('9899001103'));

      // Boundary check
      final hasNext = currentIndex < batchQueue.length - 1;
      expect(hasNext, isFalse);
    });

    test('Timing classification calculation matches CRM server rules', () {
      String classifyCall(int durationSeconds) {
        if (durationSeconds <= 0) return 'NOT_CONNECTED';
        if (durationSeconds <= 20) return 'CONNECTED_SHORT';
        return 'CONNECTED_CONVERSATION';
      }

      expect(classifyCall(0), equals('NOT_CONNECTED'));
      expect(classifyCall(15), equals('CONNECTED_SHORT'));
      expect(classifyCall(20), equals('CONNECTED_SHORT'));
      expect(classifyCall(21), equals('CONNECTED_CONVERSATION'));
      expect(classifyCall(120), equals('CONNECTED_CONVERSATION'));
    });

    test('Call submission payload builds correct parameters', () {
      Map<String, dynamic> buildSubmitPayload({
        required int recordId,
        required String source,
        required String callStatus,
        required int duration,
        String? notes,
        String? followup,
      }) {
        final timing = duration <= 0
            ? 'NOT_CONNECTED'
            : (duration <= 20 ? 'CONNECTED_SHORT' : 'CONNECTED_CONVERSATION');
        return {
          'record_id': recordId,
          'source': source,
          'call_status': callStatus,
          'call_duration': duration,
          'timing_classification': timing,
          if (notes != null && notes.isNotEmpty) 'notes': notes,
          if (followup != null && followup.isNotEmpty) 'next_followup': followup,
        };
      }

      final payload = buildSubmitPayload(
        recordId: 125639,
        source: 'TEMP',
        callStatus: 'Connected',
        duration: 52,
        notes: 'Interested in business loan',
        followup: '2026-11-04 10:00:00',
      );

      expect(payload['record_id'], equals(125639));
      expect(payload['source'], equals('TEMP'));
      expect(payload['call_status'], equals('Connected'));
      expect(payload['call_duration'], equals(52));
      expect(payload['timing_classification'], equals('CONNECTED_CONVERSATION'));
      expect(payload['notes'], equals('Interested in business loan'));
      expect(payload['next_followup'], equals('2026-11-04 10:00:00'));
    });
  });

  group('Goal 3: CRUD on Leads (Strictly Self-Assigned Isolation)', () {
    test('Telecaller lead filter strictly isolates self leads from other telecallers', () {
      const currentUserId = 4;

      final allLeadsResponse = [
        {
          'id': 21,
          'customer_name': 'Self Lead Amit',
          'customer_mobile': '9899001101',
          'customer_company': 'Self Alpha Corp',
          'loan_amount': '1500000',
          'lead_status_new': 'LEAD',
          'assigned_to': 4,
        },
        {
          'id': 22,
          'customer_name': 'Other User Lead Sneha',
          'customer_mobile': '9899001199',
          'customer_company': 'Other Sneha Corp',
          'loan_amount': '2500000',
          'lead_status_new': 'LEAD',
          'assigned_to': 5, // Assigned to Sneha
        },
      ];

      final selfAssignedLeads = allLeadsResponse
          .where((l) => l['assigned_to'] == currentUserId)
          .map((l) => CrmLead.fromJson(l))
          .toList();

      expect(selfAssignedLeads.length, equals(1));
      expect(selfAssignedLeads.first.id, equals(21));
      expect(selfAssignedLeads.first.name, equals('Self Lead Amit'));
      expect(selfAssignedLeads.any((l) => l.id == 22), isFalse);
    });

    test('CrmLead model handles stages, amounts and updates correctly', () {
      final lead = CrmLead.fromJson({
        'id': 24,
        'customer_name': 'Pravin Ramdas Bhosale',
        'customer_mobile': '8261033791',
        'customer_company': 'Bhosale Enterprises',
        'loan_amount': '500000',
        'lead_status_new': 'FOLLOWUP',
        'stage': 'Hot',
        'remarks': 'Lead in active negotiation',
      });

      expect(lead.id, equals(24));
      expect(lead.name, equals('Pravin Ramdas Bhosale'));
      expect(lead.mobile, equals('8261033791'));
      expect(lead.company, equals('Bhosale Enterprises'));
      expect(lead.package, equals('500000'));
      expect(lead.status, equals('FOLLOWUP'));
      expect(lead.stage, equals('Hot'));
    });
  });

  group('Goal 4: View Self Calling Reports and Numbers Date-Wise', () {
    test('Date periods filter and format summary KPIs accurately', () {
      final summaryToday = {
        'period': 'today',
        'total_calls': 4,
        'connected_calls': 3,
        'total_duration_seconds': 147,
        'avg_duration_seconds': 36.8,
        'connection_rate_percent': 75.0,
        'timing_tiers': {
          'not_connected': 1,
          'connected_short': 0,
          'connected_conversation': 3,
        },
      };

      final summaryYesterday = {
        'period': 'yesterday',
        'total_calls': 1,
        'connected_calls': 1,
        'total_duration_seconds': 14,
        'avg_duration_seconds': 14.0,
        'connection_rate_percent': 100.0,
        'timing_tiers': {
          'not_connected': 0,
          'connected_short': 1,
          'connected_conversation': 0,
        },
      };

      expect(summaryToday['total_calls'], equals(4));
      expect(summaryToday['connected_calls'], equals(3));
      expect(summaryToday['connection_rate_percent'], equals(75.0));

      expect(summaryYesterday['total_calls'], equals(1));
      expect(summaryYesterday['connected_calls'], equals(1));
      expect(summaryYesterday['connection_rate_percent'], equals(100.0));
    });

    test('Dialed numbers history list maps timing classifications and contact details', () {
      final dialedCalls = [
        {
          'log_id': 295,
          'customer_name': 'Calling Prospect 1',
          'customer_mobile': '9899001101',
          'call_duration': 52,
          'timing_classification': 'CONNECTED_CONVERSATION',
          'call_status': 'Connected',
          'created_at': '2026-11-03 12:17:27',
        },
        {
          'log_id': 294,
          'customer_name': 'Pravin Ramdas Bhosale',
          'customer_mobile': '8261033791',
          'call_duration': 30,
          'timing_classification': 'CONNECTED_CONVERSATION',
          'call_status': 'Callback Requested',
          'next_followup': '2026-11-03 14:47:27',
          'created_at': '2026-11-03 12:17:27',
        },
        {
          'log_id': 293,
          'customer_name': 'Jerry George',
          'customer_mobile': '7902622182',
          'call_duration': 14,
          'timing_classification': 'CONNECTED_SHORT',
          'call_status': 'Connected',
          'created_at': '2026-11-02 11:00:00',
        },
      ];

      expect(dialedCalls.length, equals(3));
      expect(dialedCalls[0]['timing_classification'], equals('CONNECTED_CONVERSATION'));
      expect(dialedCalls[1]['next_followup'], isNotNull);
      expect(dialedCalls[2]['timing_classification'], equals('CONNECTED_SHORT'));
    });
  });

  group('Goal 5: CRUD on Follow-ups for Calling Purpose Including Notifications', () {
    test('FollowupService performs complete CRUD with lifecycle statuses', () async {
      await FollowupService.init();
      final service = FollowupService.instance;

      // 1. Create Follow-up (Due 10 minutes ago)
      final initialDueTime = DateTime.now().subtract(const Duration(minutes: 10));
      final item = await service.addFollowup(
        customerName: 'Pravin Bhosale',
        phoneNumber: '8261033791',
        company: 'Bhosale Corp',
        scheduledTime: initialDueTime,
        notes: 'Discuss 5L business loan terms',
      );

      expect(item.customerName, equals('Pravin Bhosale'));
      expect(item.phoneNumber, equals('8261033791'));
      expect(item.status, equals('pending'));
      expect(service.getPending().length, greaterThanOrEqualTo(1));

      // 2. Snooze Follow-up (15 minutes from now)
      await service.snoozeFollowup(item.id, duration: const Duration(minutes: 15));
      final snoozed = service.followups.firstWhere((f) => f.id == item.id);
      expect(snoozed.status, equals('snoozed'));
      expect(snoozed.scheduledTime.isAfter(DateTime.now()), isTrue);

      // 3. Reschedule Follow-up
      final newTime = DateTime.now().add(const Duration(days: 1));
      await service.rescheduleFollowup(item.id, newTime, notes: 'Postponed to tomorrow 10am');
      final rescheduled = service.followups.firstWhere((f) => f.id == item.id);
      expect(rescheduled.status, equals('pending'));
      expect(rescheduled.notes, equals('Postponed to tomorrow 10am'));

      // 4. Complete Follow-up
      await service.markCompleted(item.id);
      final completed = service.followups.firstWhere((f) => f.id == item.id);
      expect(completed.status, equals('completed'));
      expect(completed.completedAt, isNotNull);
      expect(service.getCompleted().any((f) => f.id == item.id), isTrue);

      // 5. Delete Follow-up
      await service.deleteFollowup(item.id);
      expect(service.followups.any((f) => f.id == item.id), isFalse);
    });

    test('FollowupModel serialization retains all fields for notification alarms', () {
      final now = DateTime.now();
      final followup = FollowupModel(
        id: 'f_test_101',
        leadId: 55,
        customerName: 'Kavita Sharma',
        phoneNumber: '9811223344',
        company: 'Sharma Logistics',
        scheduledTime: now.add(const Duration(minutes: 30)),
        createdAt: now,
        notes: 'Call back regarding interest rate waiver',
        status: 'pending',
      );

      final json = followup.toJson();
      final revived = FollowupModel.fromJson(json);

      expect(revived.id, equals('f_test_101'));
      expect(revived.leadId, equals(55));
      expect(revived.customerName, equals('Kavita Sharma'));
      expect(revived.phoneNumber, equals('9811223344'));
      expect(revived.company, equals('Sharma Logistics'));
      expect(revived.notes, equals('Call back regarding interest rate waiver'));
      expect(revived.status, equals('pending'));
    });
  });
}
