import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:callnow_new/services/followup_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('FollowupService Tests', () {
    test('Initializes with empty list and adds followup', () async {
      await FollowupService.init();
      expect(FollowupService.instance.followups.isEmpty, isTrue);

      final scheduled = DateTime.now().add(const Duration(hours: 1));
      final created = await FollowupService.instance.addFollowup(
        customerName: 'Rahul Verma',
        phoneNumber: '9876543210',
        company: 'Infosys',
        scheduledTime: scheduled,
        notes: 'Call back regarding loan',
        leadId: 101,
      );

      expect(created.customerName, 'Rahul Verma');
      expect(FollowupService.instance.followups.length, 1);
      expect(FollowupService.instance.getPending().length, 1);
      expect(FollowupService.instance.getCompleted().length, 0);
    });

    test('Snooze and Mark Completed update statuses correctly', () async {
      await FollowupService.init();
      final scheduled = DateTime.now().add(const Duration(minutes: 30));
      final item = await FollowupService.instance.addFollowup(
        customerName: 'Meera Sen',
        phoneNumber: '9123456780',
        scheduledTime: scheduled,
        notes: 'Interested',
      );

      // Snooze by 15 mins
      await FollowupService.instance.snoozeFollowup(item.id, duration: const Duration(minutes: 15));
      final snoozed = FollowupService.instance.followups.firstWhere((f) => f.id == item.id);
      expect(snoozed.status, 'snoozed');

      // Mark completed
      await FollowupService.instance.markCompleted(item.id);
      final completed = FollowupService.instance.followups.firstWhere((f) => f.id == item.id);
      expect(completed.status, 'completed');
      expect(FollowupService.instance.getPending().isEmpty, isTrue);
      expect(FollowupService.instance.getCompleted().length, 1);
    });

    test('Follow-up scheduled alerting logic triggers due callback detection at due time', () async {
      await FollowupService.init();

      final dueTime = DateTime.now().subtract(const Duration(seconds: 10));
      final dueFollowup = await FollowupService.instance.addFollowup(
        customerName: 'Anil Sharma',
        phoneNumber: '9888776655',
        company: 'Tata Motors',
        scheduledTime: dueTime,
        notes: 'Urgent callback needed',
        leadId: 505,
      );

      expect(dueFollowup.isOverdue || dueFollowup.isDueNow, isTrue);

      final dueList = FollowupService.instance.getDueNowUnprompted();
      expect(dueList.any((f) => f.id == dueFollowup.id), isTrue);

      FollowupService.instance.markPromptedInSession(dueFollowup.id);
      final afterPrompt = FollowupService.instance.getDueNowUnprompted();
      expect(afterPrompt.any((f) => f.id == dueFollowup.id), isFalse);
    });
  });
}

