import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:callnow_new/screens/settings_screen.dart';
import 'package:callnow_new/screens/calling_desk_screen.dart';
import 'package:callnow_new/services/api_service.dart';
import 'package:callnow_new/services/calling_preferences_service.dart';
import 'package:callnow_new/services/config_service.dart';
import 'package:callnow_new/services/secure_storage_service.dart';
import 'package:callnow_new/services/whatsapp_message_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SecureStorageService.setBackendForTesting(MemorySecureStorageBackend());
    await ConfigService.init();
    CallingDeskScreen.clearSessionProcessedLeads();
  });

  tearDown(() {
    ApiService.resetClient();
    SecureStorageService.resetBackend();
    CallingDeskScreen.clearSessionProcessedLeads();
  });

  group('CallingPreferencesService Unit Tests', () {
    test('Default values are correct', () async {
      expect(await CallingPreferencesService.isVibrateOnCallEndEnabled(), isTrue);
      expect(await CallingPreferencesService.isKeepScreenAwakeEnabled(), isTrue);
      expect(await CallingPreferencesService.isAutoCopyNumberEnabled(), isFalse);
      expect(await CallingPreferencesService.getPreferredDialer(), CallingPreferencesService.dialerSystem);
    });

    test('Values persist across reads and writes', () async {
      await CallingPreferencesService.setVibrateOnCallEnd(false);
      await CallingPreferencesService.setKeepScreenAwake(false);
      await CallingPreferencesService.setAutoCopyNumber(true);
      await CallingPreferencesService.setPreferredDialer(CallingPreferencesService.dialerDirect);

      expect(await CallingPreferencesService.isVibrateOnCallEndEnabled(), isFalse);
      expect(await CallingPreferencesService.isKeepScreenAwakeEnabled(), isFalse);
      expect(await CallingPreferencesService.isAutoCopyNumberEnabled(), isTrue);
      expect(await CallingPreferencesService.getPreferredDialer(), CallingPreferencesService.dialerDirect);
    });
  });

  group('SettingsScreen Widget & Options Tests', () {
    testWidgets('SettingsScreen loads persisted preferences and updates upon toggle', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await CallingPreferencesService.setVibrateOnCallEnd(true);
      await CallingPreferencesService.setAutoCopyNumber(false);
      await WhatsAppMessageService.setIntroEnabled(true);

      await tester.pumpWidget(
        const MaterialApp(
          home: SettingsScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Verify headings
      expect(find.text('Calling & Dialer Preferences'), findsOneWidget);
      expect(find.text('Device & Diagnostics'), findsOneWidget);
      expect(find.text('About CallNow'), findsOneWidget);

      // Verify Vibrate on Call End switch
      expect(find.text('Vibrate on Call End'), findsOneWidget);
      final vibrateFinder = find.widgetWithText(SwitchListTile, 'Vibrate on Call End');
      expect(tester.widget<SwitchListTile>(vibrateFinder).value, isTrue);

      // Toggle Vibrate on Call End
      await tester.tap(vibrateFinder);
      await tester.pumpAndSettle();
      expect(await CallingPreferencesService.isVibrateOnCallEndEnabled(), isFalse);

      // Verify and toggle Auto-Copy Number on Dial
      final autoCopyFinder = find.widgetWithText(SwitchListTile, 'Auto-Copy Number on Dial');
      expect(tester.widget<SwitchListTile>(autoCopyFinder).value, isFalse);
      await tester.tap(autoCopyFinder);
      await tester.pumpAndSettle();
      expect(await CallingPreferencesService.isAutoCopyNumberEnabled(), isTrue);

      // Test Preferred Calling Method Dialog
      final dialerTile = find.text('Preferred Calling Method');
      await tester.tap(dialerTile);
      await tester.pumpAndSettle();

      expect(find.text('Select Preferred Calling Method'), findsOneWidget);
      expect(find.text('Direct Action / Prompt'), findsOneWidget);

      // Select Direct Action
      await tester.tap(find.text('Direct Action / Prompt'));
      await tester.pumpAndSettle();

      expect(await CallingPreferencesService.getPreferredDialer(), CallingPreferencesService.dialerDirect);
      expect(find.text('Direct Action / Prompt'), findsOneWidget);
    });

    testWidgets('Refresh Leads Queue clears session queue and fetches fresh leads', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Mark a lead as processed
      CallingDeskScreen.markLeadProcessed('lead_123');
      expect(CallingDeskScreen.sessionProcessedLeadIds.contains('lead_123'), isTrue);

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/batch-leads')) {
          return http.Response(
            json.encode({
              'success': true,
              'data': {
                'leads': [
                  {'id': '101', 'name': 'Lead 101', 'mobile': '9876543210'},
                  {'id': '102', 'name': 'Lead 102', 'mobile': '9876543211'},
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
          home: SettingsScreen(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Refresh Leads Queue'));
      await tester.tap(find.text('Refresh Leads Queue'));
      await tester.pumpAndSettle();

      // Session processed leads queue should be reset
      expect(CallingDeskScreen.sessionProcessedLeadIds.isEmpty, isTrue);
      // SnackBar with count should be displayed
      expect(find.text('Leads queue synced successfully! (2 leads ready in desk queue)'), findsOneWidget);
    });
  });
}
