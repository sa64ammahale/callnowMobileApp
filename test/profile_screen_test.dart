import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:callnow_new/screens/profile_screen.dart';
import 'package:callnow_new/services/config_service.dart';
import 'package:callnow_new/services/secure_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SecureStorageService.setBackendForTesting(MemorySecureStorageBackend());
    await ConfigService.saveAuthData('mock-token-xyz', {
      'id': 12,
      'name': 'Sangam Telecaller',
      'username': 'sangam.t',
      'email': 'sangam@callnow.com',
      'mobile': '9876543210',
      'role': 'TELECALLER',
      'company_name': 'InCredit Solutions',
      'team_name': 'Inbound Support',
      'department': 'Direct Telecalling',
    });
  });

  tearDown(() {
    SecureStorageService.resetBackend();
  });

  group('ProfileScreen Widget Tests', () {
    testWidgets('renders profile details and header card', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: ProfileScreen(),
        ),
      );
      await tester.pump();

      // Verify title
      expect(find.text('Agent Profile'), findsOneWidget);

      // Verify cached user details appear
      expect(find.text('Sangam Telecaller'), findsWidgets);
      expect(find.text('sangam@callnow.com'), findsWidgets);
      expect(find.text('9876543210'), findsWidgets);
      expect(find.text('Direct Telecalling'), findsOneWidget);
      expect(find.text('#12'), findsOneWidget);
    });

    testWidgets('edit details dialog displays locked email and mobile fields', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: ProfileScreen(),
        ),
      );
      await tester.pump();

      // Tap Edit Details button
      final editButton = find.widgetWithText(TextButton, 'Edit Details');
      expect(editButton, findsOneWidget);
      await tester.tap(editButton);
      await tester.pumpAndSettle();

      // Modal bottom sheet should be visible
      expect(find.text('Edit Profile Details'), findsOneWidget);
      expect(find.text('Locked • Contact CRM Administrator to change email'), findsOneWidget);
      expect(find.text('Locked • Contact CRM Administrator to change phone'), findsOneWidget);

      // Verify Full Name text field is present
      expect(find.widgetWithText(TextField, 'Full Name'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Company / Organization'), findsOneWidget);
    });

    testWidgets('change password dialog opens with input fields', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: ProfileScreen(),
        ),
      );
      await tester.pump();

      // Scroll down to Security Card
      final changePasswordBtn = find.widgetWithText(FilledButton, 'Change Password');
      await tester.scrollUntilVisible(changePasswordBtn, 300);
      expect(changePasswordBtn, findsOneWidget);
      await tester.tap(changePasswordBtn);
      await tester.pumpAndSettle();

      // Modal bottom sheet should be visible
      expect(find.text('Enter your current password and your new desired password.'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Current Password'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'New Password (Min 6 chars)'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Confirm New Password'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Update Password'), findsOneWidget);
    });

    testWidgets('logout prompt opens confirmation dialog', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: ProfileScreen(),
        ),
      );
      await tester.pump();

      // Scroll down to Sign Out button
      final signOutBtn = find.widgetWithText(OutlinedButton, 'Sign Out');
      await tester.scrollUntilVisible(signOutBtn, 300);
      expect(signOutBtn, findsOneWidget);
      await tester.tap(signOutBtn);
      await tester.pumpAndSettle();

      // AlertDialog should be displayed
      expect(find.text('Are you sure you want to log out of your telecaller session on this device?'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });
  });
}
