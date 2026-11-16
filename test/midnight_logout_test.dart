import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:callnow_new/services/config_service.dart';
import 'package:callnow_new/services/secure_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SecureStorageService.setBackendForTesting(MemorySecureStorageBackend());
    ConfigService.resetForTesting();
  });

  tearDown(() {
    SecureStorageService.resetBackend();
  });

  group('Midnight Auto-Logout — Last Login Date Tracking', () {
    test('saveAuthData persists last login date', () async {
      await ConfigService.saveAuthData(
        'test-token-123',
        {'name': 'Sangam'},
      );

      expect(ConfigService.lastLoginDate, isNotNull);
      expect(ConfigService.lastLoginDate!.day, DateTime.now().day);
      expect(ConfigService.lastLoginDate!.month, DateTime.now().month);
      expect(ConfigService.lastLoginDate!.year, DateTime.now().year);
    });

    test('clearAuthData clears last login date', () async {
      await ConfigService.saveAuthData('test-token-123', {'name': 'Sangam'});
      expect(ConfigService.lastLoginDate, isNotNull);

      await ConfigService.clearAuthData();
      expect(ConfigService.lastLoginDate, isNull);
    });

    test('init clears auth when last login was a previous day', () async {
      // Simulate a login from yesterday
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_login_date', yesterday.toIso8601String());
      await prefs.setString('user_data', '{"name": "Sangam"}');

      // Simulate a stored token
      SecureStorageService.instance.writeToken('old-token');

      await ConfigService.init();

      // Auth should be cleared because last login was yesterday
      expect(ConfigService.isLoggedIn, isFalse);
      expect(ConfigService.token, isNull);
      expect(ConfigService.userData, isNull);
      expect(ConfigService.lastLoginDate, isNull);
    });

    test('init keeps auth when last login was today', () async {
      // Simulate a login from today
      final today = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_login_date', today.toIso8601String());
      await prefs.setString('user_data', '{"name": "Sangam"}');
      SecureStorageService.instance.writeToken('valid-token');

      await ConfigService.init();

      // Auth should be preserved because last login was today
      expect(ConfigService.isLoggedIn, isTrue);
      expect(ConfigService.token, 'valid-token');
    });

    test('init keeps auth when no last login date exists', () async {
      // Fresh install, no last login date
      SecureStorageService.instance.writeToken('valid-token');

      await ConfigService.init();

      expect(ConfigService.isLoggedIn, isTrue);
    });

    test('init clears auth when last login was two days ago', () async {
      final twoDaysAgo = DateTime.now().subtract(const Duration(days: 2));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_login_date', twoDaysAgo.toIso8601String());
      await prefs.setString('user_data', '{"name": "Sangam"}');
      SecureStorageService.instance.writeToken('old-token');

      await ConfigService.init();

      expect(ConfigService.isLoggedIn, isFalse);
      expect(ConfigService.token, isNull);
    });

    test('init clears auth across month boundary', () async {
      // Simulate login on last day of previous month
      final now = DateTime.now();
      final firstOfMonth = DateTime(now.year, now.month, 1);
      final lastDayPrevMonth = firstOfMonth.subtract(const Duration(days: 1));

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_login_date', lastDayPrevMonth.toIso8601String());
      await prefs.setString('user_data', '{"name": "Sangam"}');
      SecureStorageService.instance.writeToken('old-token');

      await ConfigService.init();

      expect(ConfigService.isLoggedIn, isFalse);
      expect(ConfigService.token, isNull);
    });

    test('init clears auth across year boundary', () async {
      // Simulate login on Dec 31 of previous year
      final now = DateTime.now();
      final dec31PrevYear = DateTime(now.year - 1, 12, 31);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_login_date', dec31PrevYear.toIso8601String());
      await prefs.setString('user_data', '{"name": "Sangam"}');
      SecureStorageService.instance.writeToken('old-token');

      await ConfigService.init();

      expect(ConfigService.isLoggedIn, isFalse);
      expect(ConfigService.token, isNull);
    });
  });
}
