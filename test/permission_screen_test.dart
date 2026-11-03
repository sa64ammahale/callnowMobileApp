import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:callnow_new/screens/permission_screen.dart';
import 'package:callnow_new/services/permission_service.dart';
import 'package:callnow_new/services/config_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ConfigService.init();
    await ConfigService.clearAuthData();
  });

  tearDown(() {
    PermissionService.mockReport = null;
  });

  group('PermissionScreen Widget Tests', () {
    testWidgets('renders all 4 permission cards and progress counter when permissions are missing',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Set mock report with only notifications granted
      PermissionService.mockReport = const PermissionStatusReport(
        phoneState: false,
        callLog: false,
        callPhone: false,
        notifications: true,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: PermissionScreen(),
        ),
      );

      // Settle async checkPermissions
      await tester.pumpAndSettle();

      // Verify Header & Progress pill
      expect(find.text('Permissions Setup'), findsOneWidget);
      expect(find.text('1 of 4 Permissions Granted'), findsOneWidget);

      // Verify all 4 permission titles
      expect(find.text('Phone Call Detection'), findsOneWidget);
      expect(find.text('Call Log & Talk Time'), findsOneWidget);
      expect(find.text('One-Tap Direct Calling'), findsOneWidget);
      expect(find.text('Callback Notifications'), findsOneWidget);

      // Verify status badges: 3 Required, 1 Granted
      expect(find.text('Required'), findsNWidgets(3));
      expect(find.text('Granted'), findsOneWidget);

      // Verify primary action button is present
      expect(find.text('Grant All Permissions'), findsOneWidget);
    });

    testWidgets('shows warning and device settings button after permissions are requested but still denied',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      PermissionService.mockReport = const PermissionStatusReport(
        phoneState: false,
        callLog: false,
        callPhone: false,
        notifications: false,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: PermissionScreen(),
        ),
      );

      await tester.pumpAndSettle();

      // Tap Grant All Permissions
      final grantButton = find.text('Grant All Permissions');
      expect(grantButton, findsOneWidget);
      await tester.ensureVisible(grantButton);
      await tester.tap(grantButton);
      await tester.pumpAndSettle();

      // Now warning card & Open Device Settings button should appear
      expect(find.text('Permissions need enabling in Settings'), findsOneWidget);
      final settingsButton = find.text('Open Device Settings');
      expect(settingsButton, findsOneWidget);
      await tester.ensureVisible(settingsButton);
    });

    testWidgets('shows all 4 granted badges and navigates to login when unauthenticated',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await ConfigService.clearAuthData();

      PermissionService.mockReport = const PermissionStatusReport(
        phoneState: true,
        callLog: true,
        callPhone: true,
        notifications: true,
      );

      // Provide routes for navigation
      await tester.pumpWidget(
        MaterialApp(
          initialRoute: '/permissions',
          routes: {
            '/permissions': (context) => const PermissionScreen(),
            '/login': (context) => const Scaffold(body: Text('Login Screen Mock')),
            '/home': (context) => const Scaffold(body: Text('Home Screen Mock')),
          },
        ),
      );

      await tester.pumpAndSettle();

      // Because all granted and unauthenticated, it navigates to login
      expect(find.text('Login Screen Mock'), findsOneWidget);
    });

    testWidgets('navigates directly to home when all permissions are granted and already authenticated',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await ConfigService.saveAuthData('mock_token', {'id': 1, 'name': 'Agent Smith'});

      PermissionService.mockReport = const PermissionStatusReport(
        phoneState: true,
        callLog: true,
        callPhone: true,
        notifications: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          initialRoute: '/permissions',
          routes: {
            '/permissions': (context) => const PermissionScreen(),
            '/login': (context) => const Scaffold(body: Text('Login Screen Mock')),
            '/home': (context) => const Scaffold(body: Text('Home Screen Mock')),
          },
        ),
      );

      await tester.pumpAndSettle();

      // Because all granted and authenticated, it navigates directly to home
      expect(find.text('Home Screen Mock'), findsOneWidget);
    });
  });
}
