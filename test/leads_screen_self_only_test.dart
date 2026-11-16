import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:callnow_new/screens/leads_screen.dart';
import 'package:callnow_new/services/api_service.dart';
import 'package:callnow_new/services/config_service.dart';
import 'package:callnow_new/services/secure_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SecureStorageService.setBackendForTesting(MemorySecureStorageBackend());
    await ConfigService.setBaseUrl('https://crm.callnow.example.com/api/v1');
    await ConfigService.saveAuthData('tok-admin', {
      'id': 1,
      'name': 'System Administrator',
      'role': 'Super Admin',
      'team_id': 2,
    });
  });

  tearDown(() {
    ApiService.resetClient();
    SecureStorageService.resetBackend();
  });

  testWidgets('LeadsScreen displays date-wise filter but removes other persons officer filter', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    String? capturedScope;
    final mockClient = MockClient((request) async {
      if (request.url.path.contains('/telecaller/leads')) {
        capturedScope = request.url.queryParameters['scope'];
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'leads': [
                {
                  'lead_id': 201,
                  'cust_id': 201,
                  'name': 'My Personal Lead',
                  'mobile': '9876543210',
                  'company': 'Personal Client Co',
                  'lead_status_new': 'LEAD',
                  'assigned_to': 1,
                  'assigned_user': 'System Administrator',
                  'is_own_lead': true,
                  'created_at': '2026-11-16 10:00:00',
                  'package': '500000',
                  'loan_type': 'Personal Loan',
                }
              ],
              'pagination': {'total': 1, 'total_pages': 1, 'page': 1, 'limit': 20}
            }
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{"status":"error"}', 404);
    });

    ApiService.setClientForTesting(mockClient);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LeadsScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 1. Verify scope sent to server is strictly 'mine'
    expect(capturedScope, 'mine', reason: 'Mobile app must request only self leads (scope=mine)');

    // 2. Verify Date-wise Filter is present
    expect(find.byIcon(Icons.calendar_today_outlined), findsOneWidget);
    expect(find.text('This Month'), findsOneWidget);

    // 3. Verify Officer Filter Pill is completely REMOVED
    expect(find.text('Officer'), findsNothing);
    expect(find.text('Filter by Officer / User'), findsNothing);
    expect(find.byIcon(Icons.badge_outlined), findsNothing);

    // 4. Verify lead card renders self lead
    expect(find.text('My Personal Lead'), findsOneWidget);
  });
}
