import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:callnow_new/model/telecaller_engagement.dart';
import 'package:callnow_new/services/engagement_service.dart';
import 'package:callnow_new/services/api_service.dart';
import 'package:callnow_new/services/config_service.dart';
import 'package:callnow_new/services/secure_storage_service.dart';
import 'package:callnow_new/services/call_tracking_service.dart';
import 'package:callnow_new/screens/calling_desk_screen.dart';
import 'package:callnow_new/screens/home_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SecureStorageService.setBackendForTesting(MemorySecureStorageBackend());
    await ConfigService.init();
    await EngagementService.instance.init();
    CallingDeskScreen.clearSessionProcessedLeads();
    ConfigService.clearLogoutCallbacks();
  });

  tearDown(() {
    ApiService.resetClient();
    SecureStorageService.resetBackend();
    CallingDeskScreen.clearSessionProcessedLeads();
    ConfigService.clearLogoutCallbacks();
  });

  group('TelecallerEngagement Model Tests', () {
    test('Default constructor values', () {
      final eng = TelecallerEngagement();
      expect(eng.xpEarned, 0);
      expect(eng.callXp, 0);
      expect(eng.targetBonusXp, 0);
      expect(eng.totalXp, 0);
      expect(eng.level, 1);
      expect(eng.levelTitle, 'Bronze Caller 🥉');
      expect(eng.badgeTheme, 'dark');
      expect(eng.streakDays, 0);
      expect(eng.connectedToday, 0);
      expect(eng.targetToday, 30);
      expect(eng.targetMet, false);
      expect(eng.targetProgress, 0.0);
    });

    test('fromJson parses full payload correctly with string or int values', () {
      final json = {
        'xp_earned': '50',
        'call_xp': 50,
        'target_bonus_xp': '100',
        'total_xp': 750,
        'level': 2,
        'level_title': 'Silver Dial Master 🥈',
        'badge_theme': 'silver',
        'streak_days': '5',
        'connected_today': 15,
        'target_today': 30,
        'target_met': 'true',
      };
      final eng = TelecallerEngagement.fromJson(json);
      expect(eng.xpEarned, 50);
      expect(eng.callXp, 50);
      expect(eng.targetBonusXp, 100);
      expect(eng.totalXp, 750);
      expect(eng.level, 2);
      expect(eng.levelTitle, 'Silver Dial Master 🥈');
      expect(eng.streakDays, 5);
      expect(eng.connectedToday, 15);
      expect(eng.targetToday, 30);
      expect(eng.targetMet, isTrue);
      expect(eng.targetProgress, 0.5);
    });

    test('targetProgress clamps correctly', () {
      final zeroTarget = TelecallerEngagement(connectedToday: 5, targetToday: 0);
      expect(zeroTarget.targetProgress, 0.0);

      final overTarget = TelecallerEngagement(connectedToday: 45, targetToday: 30);
      expect(overTarget.targetProgress, 1.0);
    });
  });

  group('EngagementService Tests', () {
    test('updateFromApiResponse updates state, notifies listeners, and persists', () async {
      final service = EngagementService.instance;
      bool notified = false;
      void listener() => notified = true;
      service.addListener(listener);

      await service.updateFromApiResponse({
        'total_xp': 350,
        'level': 2,
        'level_title': 'Silver Dial Master 🥈',
        'streak_days': 4,
        'connected_today': 20,
        'target_today': 30,
        'target_met': false,
      });

      expect(notified, isTrue);
      expect(service.state.totalXp, 350);
      expect(service.state.level, 2);
      expect(service.state.levelTitle, 'Silver Dial Master 🥈');
      expect(service.state.streakDays, 4);
      expect(service.state.connectedToday, 20);

      service.removeListener(listener);

      // Verify persistence by re-initializing
      final freshService = EngagementService.instance;
      await freshService.init();
      expect(freshService.state.totalXp, 350);
      expect(freshService.state.levelTitle, 'Silver Dial Master 🥈');
    });
  });

  group('Dashboard Motivation Hub Widget Tests', () {
    testWidgets('Dashboard renders Motivation Hub with level title, total XP, streak, and goal', (tester) async {
      EngagementService.instance.setStateForTesting(
        TelecallerEngagement(
          totalXp: 450,
          level: 2,
          levelTitle: 'Silver Dial Master 🥈',
          streakDays: 3,
          connectedToday: 18,
          targetToday: 30,
          targetMet: false,
        ),
      );

      final mockClient = MockClient((request) async {
        return http.Response(
          json.encode({
            'success': true,
            'data': {
              'calls_dialed': 25,
              'connected_count': 18,
              'unique_clients': 20,
            }
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      ApiService.setClientForTesting(mockClient);

      await tester.pumpWidget(
        const MaterialApp(
          home: HomeScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Silver Dial Master 🥈'), findsOneWidget);
      expect(find.text('450 XP'), findsOneWidget);
      expect(find.text('3d Streak'), findsOneWidget);
      expect(find.text("Today's Goal: 18 / 30 Connected"), findsOneWidget);
    });
  });

  group('Real-Time Call Feedback Overlay Tests', () {
    testWidgets('CallingDesk displays floating XP SnackBar when call completes with XP', (tester) async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/batch-leads')) {
          return http.Response(
            json.encode({
              'success': true,
              'data': {
                'leads': [
                  {
                    'id': '77',
                    'name': 'Karan Verma',
                    'mobile': '9876543210',
                    'company': 'Verma Traders',
                    'package': '500000',
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
        if (request.url.path.contains('/submit') || request.url.path.contains('/calls')) {
          return http.Response(
            json.encode({
              'success': true,
              'data': {
                'engagement': {
                  'xp_earned': 25,
                  'target_bonus_xp': 0,
                  'total_xp': 475,
                }
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

      expect(find.text('Karan Verma'), findsOneWidget);

      final state = tester.state<CallingDeskScreenState>(find.byType(CallingDeskScreen));
      state.setVerifiedCallLogForTesting(
        VerifiedCallLog(
          isDialed: false,
          number: '9876543210',
          durationSeconds: 0,
          timestamp: 0,
          type: 2,
        ),
      );
      await tester.pumpAndSettle();

      // Tap an unconnected option to avoid requiring device talk time
      await tester.ensureVisible(find.text('Switch OFF'));
      await tester.tap(find.text('Switch OFF'));
      await tester.pump();

      // Tap Save & Next
      await tester.ensureVisible(find.text('Save & Next'));
      await tester.tap(find.text('Save & Next'));
      await tester.pumpAndSettle();

      // Verify Floating deep purple SnackBar with XP
      expect(find.text('+25 XP Earned!'), findsOneWidget);
    });

    testWidgets('CallingDesk displays Target Hit SnackBar when target_bonus_xp > 0', (tester) async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/batch-leads')) {
          return http.Response(
            json.encode({
              'success': true,
              'data': {
                'leads': [
                  {
                    'id': '78',
                    'name': 'Pooja Patil',
                    'mobile': '9876543211',
                    'company': 'Patil Enterprises',
                    'package': '1000000',
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
        if (request.url.path.contains('/submit') || request.url.path.contains('/calls')) {
          return http.Response(
            json.encode({
              'success': true,
              'data': {
                'engagement': {
                  'xp_earned': 125,
                  'target_bonus_xp': 100,
                  'total_xp': 600,
                }
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

      final state = tester.state<CallingDeskScreenState>(find.byType(CallingDeskScreen));
      state.setVerifiedCallLogForTesting(
        VerifiedCallLog(
          isDialed: false,
          number: '9876543211',
          durationSeconds: 0,
          timestamp: 0,
          type: 2,
        ),
      );
      await tester.pumpAndSettle();

      // Tap Ringing
      await tester.ensureVisible(find.text('Ringing'));
      await tester.tap(find.text('Ringing'));
      await tester.pump();

      // Tap Save & Next
      await tester.ensureVisible(find.text('Save & Next'));
      await tester.tap(find.text('Save & Next'));
      await tester.pumpAndSettle();

      // Verify Target Hit SnackBar
      expect(find.text('🎯 Target Hit! +125 XP (Bonus included!)'), findsOneWidget);
    });
  });
}
