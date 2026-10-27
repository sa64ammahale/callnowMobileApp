// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

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

    expect(find.text('Username / Mobile'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
  });

  testWidgets('Dashboard displays tracker card', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: DashboardPage())),
    );

    expect(find.text('Background Call Tracker'), findsOneWidget);
    expect(find.text('Today\'s Telecalling Stats'), findsOneWidget);
  });

  testWidgets('ClientsPage displays search and client leads', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: ClientsPage()),
    );

    expect(find.text('Rahul Sharma'), findsOneWidget);
    expect(find.text('Call Now'), findsWidgets);
    expect(find.text('WhatsApp'), findsWidgets);
  });
}
