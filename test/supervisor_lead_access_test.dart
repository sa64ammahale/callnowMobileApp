import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:callnow_new/services/api_service.dart';
import 'package:callnow_new/services/config_service.dart';
import 'package:callnow_new/services/secure_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SecureStorageService.setBackendForTesting(MemorySecureStorageBackend());
    await ConfigService.setBaseUrl('https://crm.callnow.example.com/api/v1');
  });

  tearDown(() {
    ApiService.resetClient();
    SecureStorageService.resetBackend();
  });

  group('Supervisor Role & Subordinate Access Tests', () {
    test('ConfigService.isSupervisor correctly identifies Supervisor without mistaking for Admin/Manager', () async {
      // Supervisor
      await ConfigService.saveAuthData('tok-sup', {
        'id': 3,
        'name': 'Priya Patel',
        'role': 'Supervisor',
        'team_id': 2,
      });
      expect(ConfigService.isSupervisor, isTrue);
      expect(ConfigService.isAdminOrManager, isFalse);
      expect(ConfigService.isManagementOrSupervisor, isTrue);

      // Super Admin
      await ConfigService.saveAuthData('tok-admin', {
        'id': 1,
        'name': 'System Admin',
        'role': 'Super Admin',
      });
      expect(ConfigService.isSupervisor, isFalse);
      expect(ConfigService.isAdminOrManager, isTrue);
      expect(ConfigService.isManagementOrSupervisor, isTrue);

      // Manager
      await ConfigService.saveAuthData('tok-mgr', {
        'id': 8,
        'name': 'Shekhar Auti',
        'role': 'Manager',
        'team_id': 2,
      });
      expect(ConfigService.isSupervisor, isFalse);
      expect(ConfigService.isAdminOrManager, isTrue);
      expect(ConfigService.isManagementOrSupervisor, isTrue);

      // Officer / Telecaller
      await ConfigService.saveAuthData('tok-officer', {
        'id': 4,
        'name': 'Amit Kumar',
        'role': 'Officer',
        'team_id': 2,
      });
      expect(ConfigService.isSupervisor, isFalse);
      expect(ConfigService.isAdminOrManager, isFalse);
      expect(ConfigService.isManagementOrSupervisor, isFalse);
    });

    test('Supervisor team officers endpoint returns only subordinates and supervisor (excluding Admins and Managers)', () async {
      await ConfigService.saveAuthData('tok-sup', {
        'id': 3,
        'name': 'Priya Patel',
        'role': 'Supervisor',
        'team_id': 2,
      });

      // Mock backend contract for supervisor: only supervisor + subordinates in team/supervisor_id
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/team-officers')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'teams': [
                  {'id': 2, 'name': 'Alpha Telecallers'}
                ],
                'officers': [
                  {'id': 3, 'name': 'Priya Patel (Me)', 'team_id': 2, 'role': 'Supervisor'},
                  {'id': 4, 'name': 'Amit Kumar', 'team_id': 2, 'role': 'Officer'},
                  {'id': 5, 'name': 'Sneha Reddy', 'team_id': 2, 'role': 'Officer'},
                ],
                'can_filter_teams': false,
              }
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{"status":"error"}', 404);
      });

      ApiService.setClientForTesting(mockClient);

      final result = await ApiService.getTeamOfficers();
      final officers = (result['officers'] as List).cast<Map<String, dynamic>>();

      expect(officers.length, 3);
      // Ensure no higher-level roles exist
      for (final off in officers) {
        final role = (off['role'] ?? '').toString().toUpperCase();
        expect(role.contains('ADMIN'), isFalse, reason: 'Admin should never be in supervisor officer list');
        expect(role.contains('MANAGER'), isFalse, reason: 'Manager should never be in supervisor officer list');
      }

      // Check expected members
      final officerNames = officers.map((o) => o['name']).toList();
      expect(officerNames, contains('Priya Patel (Me)'));
      expect(officerNames, contains('Amit Kumar'));
      expect(officerNames, contains('Sneha Reddy'));
    });

    test('Supervisor leads query strictly isolates subordinate and own leads', () async {
      await ConfigService.saveAuthData('tok-sup', {
        'id': 3,
        'name': 'Priya Patel',
        'role': 'Supervisor',
        'team_id': 2,
      });

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/telecaller/leads')) {
          // Backend should only return leads assigned to Priya Patel or her subordinate officers
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'leads': [
                  {
                    'lead_id': 101,
                    'cust_id': 101,
                    'name': 'Subordinate Officer Lead 1',
                    'mobile': '9876543210',
                    'company': 'Tech Corp',
                    'lead_status_new': 'LEAD',
                    'assigned_to': 4,
                    'assigned_user': 'Amit Kumar',
                    'is_own_lead': false,
                  },
                  {
                    'lead_id': 102,
                    'cust_id': 102,
                    'name': 'Supervisor Own Lead',
                    'mobile': '9876543211',
                    'company': 'Innovate Inc',
                    'lead_status_new': 'FOLLOWUP',
                    'assigned_to': 3,
                    'assigned_user': 'Priya Patel',
                    'is_own_lead': true,
                  },
                ],
                'pagination': {'total': 2, 'total_pages': 1, 'page': 1, 'limit': 20}
              }
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{"status":"error"}', 404);
      });

      ApiService.setClientForTesting(mockClient);

      final res = await ApiService.getCreatedLeads(page: 1, limit: 20);
      final rawLeads = res['leads'] as List;

      expect(rawLeads.length, 2);
      final assignedIds = rawLeads.map((l) => l['assigned_to']).toList();
      expect(assignedIds, contains(4)); // Amit Kumar (Officer)
      expect(assignedIds, contains(3)); // Priya Patel (Supervisor)
      expect(assignedIds, isNot(contains(1))); // Super Admin NOT present
      expect(assignedIds, isNot(contains(8))); // Manager NOT present
    });

    test('ApiService.getCreatedLeads defaults to scope=mine ensuring only self leads are requested', () async {
      await ConfigService.saveAuthData('tok-sup', {
        'id': 3,
        'name': 'Priya Patel',
        'role': 'Supervisor',
        'team_id': 2,
      });

      String? requestedScope;
      final mockClient = MockClient((request) async {
        requestedScope = request.url.queryParameters['scope'];
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'leads': [],
              'pagination': {'total': 0, 'total_pages': 1, 'page': 1, 'limit': 20}
            }
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      ApiService.setClientForTesting(mockClient);

      await ApiService.getCreatedLeads(page: 1, limit: 20);
      expect(requestedScope, 'mine', reason: 'Mobile app must request scope=mine by default');
    });
  });
}
