import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'package:callnow_new/widgets/splash_screen.dart';
import 'package:callnow_new/screens/login_screen.dart';
import 'package:callnow_new/screens/home_screen.dart';

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
}

