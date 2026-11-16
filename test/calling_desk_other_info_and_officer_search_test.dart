import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:callnow_new/screens/calling_desk_screen.dart';
import 'package:callnow_new/model/client_data_model.dart';
import 'package:callnow_new/services/api_service.dart';
import 'package:callnow_new/services/config_service.dart';
import 'package:callnow_new/services/secure_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SecureStorageService.setBackendForTesting(MemorySecureStorageBackend());
    await ConfigService.init();
    CallingDeskScreen.clearSessionProcessedLeads();
    ConfigService.clearLogoutCallbacks();
  });

  tearDown(() {
    ApiService.resetClient();
    SecureStorageService.resetBackend();
    CallingDeskScreen.clearSessionProcessedLeads();
    ConfigService.clearLogoutCallbacks();
  });

  group('CallingDesk Other Info Tests', () {
    test('ClientDataModel parses other_info correctly from any key variation', () {
      final json1 = {
        'ID': '101',
        'NAME': 'Test Contact',
        'MOBILE': '9876543210',
        'COMPANY': 'Acme Corp',
        'PACKAGE': '500000',
        'STATUS': 'Not Called',
        'UPLOAD_DATE': '2026-11-16',
        'CALL_BY': 'Admin',
        'CALL_TIME': '2026-11-16T10:00:00.000',
        'other_info': 'Wants 5 Lakh PL at lowest ROI',
      };
      final model1 = ClientDataModel.fromJson(json1);
      expect(model1.otherInfo, 'Wants 5 Lakh PL at lowest ROI');

      final json2 = {
        'ID': '102',
        'NAME': 'Test Contact 2',
        'MOBILE': '9876543211',
        'COMPANY': 'Beta Ltd',
        'PACKAGE': '200000',
        'STATUS': 'Not Called',
        'UPLOAD_DATE': '2026-11-16',
        'CALL_BY': 'Admin',
        'CALL_TIME': '2026-11-16T10:00:00.000',
        'CUST_OTHER_INFO': 'CIBIL 780, salaried person',
      };
      final model2 = ClientDataModel.fromJson(json2);
      expect(model2.otherInfo, 'CIBIL 780, salaried person');
    });

    testWidgets('CallingDeskScreen displays Other Info section when present on active contact', (tester) async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/batch-leads')) {
          return http.Response(
            json.encode({
              'success': true,
              'data': {
                'leads': [
                  {
                    'id': '501',
                    'name': 'Ramesh Pawar',
                    'mobile': '9876543210',
                    'company': 'Pawar Industries',
                    'package': '1500000',
                    'other_info': 'Previous lead enquiry - needs quick approval',
                    'call_count': 0,
                    'last_status': 'Not Called',
                  }
                ]
              }
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(json.encode({'success': true, 'data': {}}), 200);
      });
      ApiService.setClientForTesting(mockClient);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CallingDeskScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ramesh Pawar'), findsOneWidget);
      expect(find.text('Other Info'), findsOneWidget);
      expect(find.text('Previous lead enquiry - needs quick approval'), findsOneWidget);
    });

    testWidgets('CallingDeskScreen hides Other Info section when other_info is empty', (tester) async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/batch-leads')) {
          return http.Response(
            json.encode({
              'success': true,
              'data': {
                'leads': [
                  {
                    'id': '502',
                    'name': 'Suresh Shinde',
                    'mobile': '9876543212',
                    'company': 'Individual',
                    'package': '500000',
                    'other_info': '',
                    'call_count': 0,
                    'last_status': 'Not Called',
                  }
                ]
              }
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(json.encode({'success': true, 'data': {}}), 200);
      });
      ApiService.setClientForTesting(mockClient);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CallingDeskScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Suresh Shinde'), findsOneWidget);
      expect(find.text('Other Info'), findsNothing);
    });
  });
}
