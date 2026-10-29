import 'package:flutter_test/flutter_test.dart';
import 'package:callnow_new/model/followup_model.dart';

void main() {
  group('FollowupModel Tests', () {
    test('JSON serialization and deserialization works correctly', () {
      final scheduled = DateTime(2026, 10, 29, 15, 30);
      final created = DateTime(2026, 10, 29, 14, 00);

      final followup = FollowupModel(
        id: 'f_1001',
        leadId: 116825,
        customerName: 'Rohan Sharma',
        phoneNumber: '9876543210',
        company: 'TCS Ltd',
        scheduledTime: scheduled,
        createdAt: created,
        notes: 'Customer asked to call back after lunch',
        status: 'pending',
      );

      final json = followup.toJson();
      expect(json['id'], 'f_1001');
      expect(json['customer_name'], 'Rohan Sharma');
      expect(json['phone_number'], '9876543210');
      expect(json['company'], 'TCS Ltd');
      expect(json['status'], 'pending');

      final deserialized = FollowupModel.fromJson(json);
      expect(deserialized.id, followup.id);
      expect(deserialized.customerName, followup.customerName);
      expect(deserialized.phoneNumber, followup.phoneNumber);
      expect(deserialized.scheduledTime, followup.scheduledTime);
      expect(deserialized.status, 'pending');
    });

    test('isOverdue and isDueNow compute accurately', () {
      final pastTime = DateTime.now().subtract(const Duration(minutes: 10));
      final overdueFollowup = FollowupModel(
        id: 'f_overdue',
        customerName: 'Anita Roy',
        phoneNumber: '9123456789',
        scheduledTime: pastTime,
        createdAt: DateTime.now().subtract(const Duration(hours: 1)),
        notes: 'Busy in meeting',
        status: 'pending',
      );

      expect(overdueFollowup.isOverdue, isTrue);

      final futureTime = DateTime.now().add(const Duration(hours: 2));
      final futureFollowup = FollowupModel(
        id: 'f_future',
        customerName: 'Amit Patel',
        phoneNumber: '9898989898',
        scheduledTime: futureTime,
        createdAt: DateTime.now(),
        notes: 'Call tomorrow',
        status: 'pending',
      );

      expect(futureFollowup.isOverdue, isFalse);
    });

    test('copyWith updates fields without mutating original', () {
      final original = FollowupModel(
        id: 'f_1',
        customerName: 'Vikram',
        phoneNumber: '9000000000',
        scheduledTime: DateTime(2026, 10, 29, 16, 0),
        createdAt: DateTime(2026, 10, 29, 15, 0),
        status: 'pending',
      );

      final updated = original.copyWith(
        status: 'completed',
        notes: 'Followed up successfully',
      );

      expect(updated.id, original.id);
      expect(updated.status, 'completed');
      expect(updated.notes, 'Followed up successfully');
      expect(original.status, 'pending');
    });
  });
}

