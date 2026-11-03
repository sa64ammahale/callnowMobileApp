import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:callnow_new/services/config_service.dart';
import 'package:callnow_new/services/secure_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SecureStorageService.setBackendForTesting(MemorySecureStorageBackend());
  });

  tearDown(() {
    SecureStorageService.resetBackend();
  });

  group('ConfigService Tests', () {
    test('baseUrl removes trailing slashes consistently', () async {
      await ConfigService.setBaseUrl('https://example.com/api/v1///');
      expect(ConfigService.baseUrl, 'https://example.com/api/v1');
    });

    test('saveAuthData caches and restores correctly', () async {
      final user = {
        'id': 10,
        'name': 'Sangam',
        'email': 'sangam@callnow.com',
        'mobile': '9876543210',
        'role': 'ADMIN',
      };

      await ConfigService.saveAuthData('test-token-123', user);

      expect(ConfigService.token, 'test-token-123');
      expect(ConfigService.isLoggedIn, isTrue);
      expect(ConfigService.userDisplayName, 'Sangam');
      expect(ConfigService.userEmail, 'sangam@callnow.com');
      expect(ConfigService.userPhone, '9876543210');
      expect(ConfigService.userRole, 'ADMIN');
      expect(ConfigService.userId, '#10');
      expect(ConfigService.userProfile.name, 'Sangam');
    });

    test('clearAuthData resets cached state', () async {
      await ConfigService.saveAuthData('test-token-123', {'name': 'Sangam'});
      expect(ConfigService.isLoggedIn, isTrue);

      await ConfigService.clearAuthData();
      expect(ConfigService.token, isNull);
      expect(ConfigService.isLoggedIn, isFalse);
      expect(ConfigService.userData, isNull);
    });
  });
}

