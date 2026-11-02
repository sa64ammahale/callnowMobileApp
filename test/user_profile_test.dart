import 'package:flutter_test/flutter_test.dart';
import 'package:callnow_new/model/user_profile.dart';

void main() {
  group('UserProfile Model Tests', () {
    test('parses full json payload with standard keys', () {
      final json = {
        'id': 42,
        'name': 'Sangam Mahale',
        'username': 'sangam',
        'email': 'sangam@example.com',
        'mobile': '9876543210',
        'role': 'TELECALLER',
        'company_name': 'InCredit Solutions',
        'team_name': 'Sales Alpha',
        'department': 'Direct Sales',
        'join_date': '2026-01-15',
        'profile_photo_url': 'https://callnow.example.com/avatar.png',
      };

      final profile = UserProfile.fromJson(json);

      expect(profile.id, 42);
      expect(profile.name, 'Sangam Mahale');
      expect(profile.username, 'sangam');
      expect(profile.email, 'sangam@example.com');
      expect(profile.mobile, '9876543210');
      expect(profile.role, 'TELECALLER');
      expect(profile.companyName, 'InCredit Solutions');
      expect(profile.teamName, 'Sales Alpha');
      expect(profile.department, 'Direct Sales');
      expect(profile.joinDate, '2026-01-15');
      expect(profile.profilePhotoUrl, 'https://callnow.example.com/avatar.png');
      expect(profile.displayEmail, 'sangam@example.com');
      expect(profile.displayMobile, '9876543210');
      expect(profile.displayId, '#42');
    });

    test('parses nested user object and resolves alternate alias keys', () {
      final json = {
        'user': {
          'id': '7',
          'full_name': 'Rahul Sharma',
          'login_id': 'rahul@callnow.com',
          'phone': '9123456789',
          'company': 'CallNow HQ',
          'team': 'Operations',
          'created_at': '2025-11-20 10:00:00',
        }
      };

      final profile = UserProfile.fromJson(json);

      expect(profile.id, 7);
      expect(profile.name, 'Rahul Sharma');
      expect(profile.username, 'rahul@callnow.com');
      expect(profile.mobile, '9123456789');
      expect(profile.companyName, 'CallNow HQ');
      expect(profile.teamName, 'Operations');
      expect(profile.joinDate, '2025-11-20 10:00:00');
    });

    test('handles null, missing, or empty array department without producing [] string', () {
      final json = {
        'id': 1,
        'name': 'Telecaller',
        'login_id': 'telecaller',
        'department': [],
        'team': 'Telecalling Desk',
      };

      final profile = UserProfile.fromJson(json);

      expect(profile.department, isNot('[]'));
      expect(profile.displayDepartment, isNot('[]'));
      expect(profile.email, isEmpty);
      expect(profile.displayEmail, 'Not provided on server');
      expect(profile.mobile, isEmpty);
      expect(profile.displayMobile, 'Not provided on server');
    });

    test('toJson serializes correctly', () {
      final profile = UserProfile(
        id: 99,
        name: 'Test Agent',
        username: 'testagent',
        email: 'test@example.com',
        mobile: '1234567890',
        role: 'SUPERVISOR',
        companyName: 'Test Co',
        teamName: 'Support',
        department: 'Customer Care',
        joinDate: '2026-02-01',
      );

      final map = profile.toJson();
      expect(map['id'], 99);
      expect(map['name'], 'Test Agent');
      expect(map['role'], 'SUPERVISOR');
      expect(map['email'], 'test@example.com');
    });
  });
}

