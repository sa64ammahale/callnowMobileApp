import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'package:callnow_new/widgets/splash_screen.dart';
import 'package:callnow_new/screens/login_screen.dart';
import 'package:callnow_new/screens/home_screen.dart';
import 'package:callnow_new/screens/leads_screen.dart';
import 'package:callnow_new/screens/call_reports_screen.dart';

void main() {
  testWidgets('Splash screen displays branding', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: SplashScreen()),
    );

    expect(find.text('CallNow'), findsOneWidget);
  });

  testWidgets('Login screen displays form fields', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: LoginScreen()),
    );

    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
  });

  testWidgets('Dashboard displays hero CTA and quick shortcuts', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DashboardPage(
            onStartCalling: () {},
            onOpenReports: () {},
            onOpenProfile: () {},
          ),
        ),
      ),
    );

    expect(find.text('Calling Desk'), findsOneWidget);
    expect(find.text('Start Calling Session'), findsOneWidget);
    expect(find.text('Quick Shortcuts'), findsOneWidget);
  });

  testWidgets('Leads screen displays search bar, add lead button and lead filters', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LeadsScreen(),
      ),
    );

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Add Lead'), findsOneWidget);
    expect(find.byIcon(Icons.person_add_alt_1), findsWidgets);
  });

  testWidgets('Call reports screen displays tabs for Performance Summary and Dialed Calls List', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: CallReportsScreen(),
      ),
    );

    expect(find.text('Performance Summary'), findsOneWidget);
    expect(find.text('Dialed Calls List'), findsOneWidget);
  });

  testWidgets('Dashboard stat card triggers filtered reports navigation', (WidgetTester tester) async {
    int requestedTab = -1;
    String? requestedStatus;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DashboardPage(
            onStartCalling: () {},
            onOpenReports: () {},
            onOpenReportsFiltered: ({int tabIndex = 1, String? status, String? timingTier, String? period}) {
              requestedTab = tabIndex;
              requestedStatus = status;
            },
            onOpenProfile: () {},
          ),
        ),
      ),
    );

    // Tap on Calls Dialed card
    await tester.tap(find.text('Calls Dialed'));
    await tester.pump();

    expect(requestedTab, 1);
    expect(requestedStatus, 'all');
  });

  testWidgets('Home screen navigation contains 5 destinations', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: HomeScreen(),
      ),
    );

    expect(find.widgetWithText(NavigationDestination, 'Dashboard'), findsOneWidget);
    expect(find.widgetWithText(NavigationDestination, 'Leads'), findsOneWidget);
    expect(find.widgetWithText(NavigationDestination, 'Calling Desk'), findsOneWidget);
    expect(find.widgetWithText(NavigationDestination, 'Reports'), findsOneWidget);
    expect(find.widgetWithText(NavigationDestination, 'Profile'), findsOneWidget);
  });
}


