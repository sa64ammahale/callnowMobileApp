import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:callnow_new/screens/profile_screen.dart';
import 'package:callnow_new/screens/leads_screen.dart';
import 'package:callnow_new/screens/followup_screen.dart';
import 'package:callnow_new/screens/call_reports_screen.dart';
import 'package:callnow_new/services/config_service.dart';
import 'package:callnow_new/services/followup_service.dart';
import 'package:callnow_new/services/secure_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SecureStorageService.setBackendForTesting(MemorySecureStorageBackend());
    await ConfigService.saveAuthData('dummy_mock_jwt_token_for_testing', {
      'id': 101,
      'name': 'Rajesh Kumar',
      'username': 'rajesh.k',
      'email': 'rajesh@increditsolutions.in',
      'mobile': '9876543210',
      'company': 'InCredit Solutions',
      'role': 'Senior Telecaller',
      'team_name': 'Outbound Lending Team',
      'department': 'Retail Loans',
      'join_date': '2023-01-15',
    });
    await FollowupService.init();
  });

  tearDown(() {
    SecureStorageService.resetBackend();
  });

  Widget createHardenedTestApp({
    required Widget child,
    Size viewport = const Size(390, 844),
    double textScale = 1.0,
  }) {
    return MediaQuery(
      data: MediaQueryData(
        size: viewport,
        textScaler: TextScaler.linear(textScale),
      ),
      child: MaterialApp(
        home: child,
      ),
    );
  }

  group('Task 2: UX Hardening Tests', () {
    testWidgets('UX Hardening 1: ProfileScreen layout resilient under 1.5x accessibility text scaling',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createHardenedTestApp(
        child: const ProfileScreen(),
        textScale: 1.5,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Rajesh Kumar'), findsWidgets);
      expect(find.text('SENIOR TELECALLER'), findsOneWidget);
      expect(find.byType(ProfileScreen), findsOneWidget);
    });

    testWidgets('UX Hardening 2: ProfileScreen layout resilient on narrow 320px viewport',
        (tester) async {
      // 320x568 is iPhone SE / compact Android viewport
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createHardenedTestApp(
        child: const ProfileScreen(),
        viewport: const Size(320, 568),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Agent Profile'), findsOneWidget);
      expect(find.text('Edit Details'), findsOneWidget);
    });

    testWidgets('UX Hardening 3: FollowUpScreen renders empty state gracefully without errors',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createHardenedTestApp(
        child: const FollowUpScreen(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Follow-Up Pipeline'), findsOneWidget);
      expect(find.text('Due / Overdue (0)'), findsOneWidget);
      expect(find.text("Today's (0)"), findsOneWidget);
      expect(find.text('Upcoming (0)'), findsOneWidget);
      expect(find.text('Completed (0)'), findsOneWidget);
    });

    testWidgets('UX Hardening 4: FollowUpScreen layout resilient under 1.5x text scaling',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createHardenedTestApp(
        child: const FollowUpScreen(),
        textScale: 1.5,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Follow-Up Pipeline'), findsOneWidget);
      expect(find.byType(FollowUpScreen), findsOneWidget);
    });

    testWidgets('UX Hardening 5: CallReportsScreen renders gracefully with empty logs & zero division check',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createHardenedTestApp(
        child: const CallReportsScreen(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Performance Summary'), findsOneWidget);
      expect(find.text('Dialed Calls List'), findsOneWidget);
    });

    testWidgets('UX Hardening 6: LeadsScreen renders gracefully with search bar & stage filters',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createHardenedTestApp(
        child: const LeadsScreen(),
      ));
      // Pump initial frame then settle network failure
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('All Leads'), findsOneWidget);
      expect(find.text('Add Lead'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget); // Search bar exists
    });
  });
}
