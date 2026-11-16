import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:callnow_new/services/api_service.dart';
import 'package:callnow_new/services/config_service.dart';
import 'package:callnow_new/services/secure_storage_service.dart';
import 'package:callnow_new/screens/login_screen.dart';
import 'package:callnow_new/widgets/forgot_password_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SecureStorageService.setBackendForTesting(MemorySecureStorageBackend());
    await ConfigService.init();
  });

  tearDown(() {
    ApiService.resetClient();
    SecureStorageService.resetBackend();
  });

  group('ApiService Password Reset Unit Tests', () {
    test('sendPasswordResetOtp passes company code and unwraps data payload', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, contains('/auth/forgot-password'));
        final body = json.decode(request.body);
        expect(body['email'], 'user@callnow.com');
        expect(body['company_code'], 'incredit');
        expect(request.headers['X-Company-Code'], 'incredit');

        return http.Response(
          json.encode({
            'success': true,
            'data': {
              'success': true,
              'message': 'OTP sent to user@callnow.com',
              'debug_otp': '654321',
            }
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      ApiService.setClientForTesting(mockClient);

      final res = await ApiService.sendPasswordResetOtp(
        'user@callnow.com',
        companyCode: 'incredit',
      );

      expect(res['success'], isTrue);
      expect(res['message'], 'OTP sent to user@callnow.com');
      expect(res['debug_otp'], '654321');
    });

    test('resetPasswordWithOtp sends parameters and unwraps data payload', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, contains('/auth/reset-password'));
        final body = json.decode(request.body);
        expect(body['email'], 'user@callnow.com');
        expect(body['otp'], '654321');
        expect(body['password'], 'NewPass@123');
        expect(body['company_code'], 'incredit');

        return http.Response(
          json.encode({
            'success': true,
            'data': {
              'success': true,
              'message': 'Password reset successfully',
            }
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      ApiService.setClientForTesting(mockClient);

      final res = await ApiService.resetPasswordWithOtp(
        email: 'user@callnow.com',
        otp: '654321',
        newPassword: 'NewPass@123',
        companyCode: 'incredit',
      );

      expect(res['success'], isTrue);
      expect(res['message'], 'Password reset successfully');
    });

    test('resetPasswordWithOtp throws on 400 invalid OTP', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          json.encode({
            'success': false,
            'error': {'code': 400, 'message': 'Invalid or expired verification code'},
          }),
          400,
          headers: {'content-type': 'application/json'},
        );
      });
      ApiService.setClientForTesting(mockClient);

      expect(
        () => ApiService.resetPasswordWithOtp(
          email: 'user@callnow.com',
          otp: '000000',
          newPassword: 'NewPass@123',
        ),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('Invalid or expired verification code'),
        )),
      );
    });
  });

  group('LoginScreen Forgot Password Integration Tests', () {
    testWidgets('LoginScreen displays Forgot Password button and opens ForgotPasswordSheet', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: LoginScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Forgot password?'), findsOneWidget);
      await tester.ensureVisible(find.text('Forgot password?'));

      // Tap Forgot password?
      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();

      // Verify ForgotPasswordSheet modal is visible
      expect(find.text('Reset Password via Email OTP'), findsOneWidget);
      expect(find.text('1. Account Verification'), findsOneWidget);
      expect(find.text('Send Verification OTP'), findsOneWidget);
    });

    testWidgets('Complete OTP request and password reset flow in ForgotPasswordSheet', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/auth/forgot-password') || request.url.path.contains('/auth/send-otp')) {
          return http.Response(
            json.encode({
              'success': true,
              'data': {
                'success': true,
                'message': 'OTP sent to test@callnow.com',
                'debug_otp': '789123',
              }
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path.contains('/auth/reset-password')) {
          return http.Response(
            json.encode({
              'success': true,
              'data': {
                'success': true,
                'message': 'Password reset successfully! You can now sign in with your new password.',
              }
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(json.encode({'success': true}), 200);
      });
      ApiService.setClientForTesting(mockClient);

      String? resetPasswordResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: ElevatedButton(
                  onPressed: () {
                    ForgotPasswordSheet.show(
                      ctx,
                      initialEmail: 'test@callnow.com',
                      initialCompanyCode: 'incredit',
                      onPasswordResetSuccess: (p) => resetPasswordResult = p,
                    );
                  },
                  child: const Text('Open Sheet'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open the sheet
      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      // Verify email field is pre-filled
      expect(find.text('test@callnow.com'), findsOneWidget);

      // Tap Send Verification OTP
      await tester.ensureVisible(find.text('Send Verification OTP'));
      await tester.tap(find.text('Send Verification OTP'));
      await tester.pumpAndSettle();

      // Verify transitioned to Step 2 with debug OTP helper
      expect(find.text('2. Verification Code (OTP)'), findsOneWidget);
      expect(find.text('Test OTP: 789123 (Tap to paste)'), findsOneWidget);

      // Tap the test OTP helper to paste it into the field
      await tester.tap(find.text('Test OTP: 789123 (Tap to paste)'));
      await tester.pumpAndSettle();

      // Enter new password and confirmation
      final passwordFields = find.byType(TextField);
      // TextField 0: Company Code, 1: Email, 2: OTP, 3: New Password, 4: Confirm Password
      await tester.enterText(passwordFields.at(3), 'FreshPass@2026');
      await tester.enterText(passwordFields.at(4), 'FreshPass@2026');
      await tester.pumpAndSettle();

      // Tap Reset Password & Save
      await tester.ensureVisible(find.text('Reset Password & Save'));
      await tester.tap(find.text('Reset Password & Save'));
      await tester.pumpAndSettle();

      // Verify sheet closed and callback received new password
      expect(find.text('Reset Password via Email OTP'), findsNothing);
      expect(resetPasswordResult, 'FreshPass@2026');
    });
  });
}
