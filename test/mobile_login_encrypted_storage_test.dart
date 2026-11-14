import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:callnow_new/services/api_service.dart';
import 'package:callnow_new/services/config_service.dart';
import 'package:callnow_new/services/secure_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MemorySecureStorageBackend memoryStorage;
  late List<http.Request> capturedRequests;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    memoryStorage = MemorySecureStorageBackend();
    SecureStorageService.setBackendForTesting(memoryStorage);
    ConfigService.resetForTesting();
    capturedRequests = [];
  });

  tearDown(() {
    SecureStorageService.resetBackend();
    ApiService.resetClient();
    ConfigService.resetForTesting();
  });

  MockClient createMockClient(
    Future<http.Response> Function(http.Request request) handler,
  ) {
    return MockClient((request) async {
      capturedRequests.add(request);
      return handler(request);
    });
  }

  group('Group 1: Login & Credential Verification (MOB-001 - MOB-004)', () {
    test('MOB-001: Valid login persists session, token, and company code in encrypted storage', () async {
      ApiService.setClientForTesting(
        createMockClient((request) async {
          if (request.url.path.endsWith('/auth/login')) {
            return http.Response(
              json.encode({
                'success': true,
                'data': {
                  'token': 'valid-bearer-token-incredit-001',
                  'company_code': 'incredit',
                  'user': {
                    'id': 101,
                    'name': 'Officer InCredit',
                    'email': 'officer@incredit.com',
                    'mobile': '9876543210',
                    'role': 'OFFICER',
                  },
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('Not Found', 404);
        }),
      );

      final result = await ApiService.login(
        email: 'officer@incredit.com',
        password: 'ValidPassword123!',
        companyCode: 'INCREDIT',
      );

      expect(result['success'], isTrue);
      expect(ConfigService.isLoggedIn, isTrue);
      expect(ConfigService.token, equals('valid-bearer-token-incredit-001'));
      expect(ConfigService.companyCode, equals('incredit'));
      expect(ConfigService.userDisplayName, equals('Officer InCredit'));

      // Verify token and PII in encrypted storage
      final storedToken = await memoryStorage.read(key: 'callnow_auth_token');
      expect(storedToken, equals('valid-bearer-token-incredit-001'));

      final storedEmail = await memoryStorage.read(key: 'callnow_user_email');
      expect(storedEmail, equals('officer@incredit.com'));

      final storedName = await memoryStorage.read(key: 'callnow_user_name');
      expect(storedName, equals('Officer InCredit'));

      // Verify company code persisted in shared_preferences
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('company_code'), equals('incredit'));

      // Sensitive token must NOT be in shared_preferences
      expect(prefs.getString('callnow_auth_token'), isNull);
    });

    test('MOB-002: Unknown company code throws error and persists no token', () async {
      ApiService.setClientForTesting(
        createMockClient((request) async {
          return http.Response(
            json.encode({
              'success': false,
              'message': 'Company not found or invalid tenant identifier',
            }),
            404,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await expectLater(
        () => ApiService.login(
          email: 'officer@unknown.com',
          password: 'SecretPassword!',
          companyCode: 'UNKNOWN_TENANT',
        ),
        throwsA(isA<Exception>()),
      );

      expect(ConfigService.isLoggedIn, isFalse);
      expect(ConfigService.token, isNull);
      expect(await memoryStorage.read(key: 'callnow_auth_token'), isNull);
    });

    test('MOB-003: Suspended company account is rejected with access denied', () async {
      ApiService.setClientForTesting(
        createMockClient((request) async {
          return http.Response(
            json.encode({
              'success': false,
              'message': 'Company account suspended. Please contact administrator.',
            }),
            403,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await expectLater(
        () => ApiService.login(
          email: 'officer@suspended.com',
          password: 'Password123!',
          companyCode: 'SUSPENDED_CORP',
        ),
        throwsA(isA<Exception>()),
      );

      expect(ConfigService.isLoggedIn, isFalse);
      expect(ConfigService.token, isNull);
      expect(await memoryStorage.read(key: 'callnow_auth_token'), isNull);
    });

    test('MOB-004: Wrong credentials rejects login without storing auth token', () async {
      ApiService.setClientForTesting(
        createMockClient((request) async {
          return http.Response(
            json.encode({
              'success': false,
              'error': {'message': 'Invalid email or password'},
            }),
            401,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await expectLater(
        () => ApiService.login(
          email: 'officer@incredit.com',
          password: 'WrongPassword!',
          companyCode: 'incredit',
        ),
        throwsA(isA<Exception>()),
      );

      expect(ConfigService.isLoggedIn, isFalse);
      expect(ConfigService.token, isNull);
      expect(await memoryStorage.read(key: 'callnow_auth_token'), isNull);
    });
  });

  group('Group 2: Multi-Tenant Isolation & Header Security (MOB-005 - MOB-008, MOB-017)', () {
    test('MOB-005: Tenant header injection prevention enforces active company code', () async {
      await ConfigService.saveAuthData(
        'bizcopilot-token-555',
        {'id': 202, 'name': 'BizCopilot Agent'},
        companyCode: 'BIZCOPILOT',
      );

      ApiService.setClientForTesting(
        createMockClient((request) async {
          return http.Response(
            json.encode({
              'success': true,
              'data': {'company_code': 'bizcopilot'},
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await ApiService.getAdminSettings();

      expect(capturedRequests, isNotEmpty);
      final request = capturedRequests.last;

      // X-Company-Code header must strictly match BIZCOPILOT in lowercase
      expect(request.headers['X-Company-Code'], equals('bizcopilot'));
      expect(request.headers['Authorization'], equals('Bearer bizcopilot-token-555'));

      // Outgoing request header cannot be spoofed or overridden to INCREDIT
      expect(request.headers['X-Company-Code'], isNot(equals('incredit')));
    });

    test('MOB-006: Header persistence across simulated app actions and queries', () async {
      await ConfigService.saveAuthData(
        'session-token-999',
        {'id': 105, 'name': 'Persistent Agent'},
        companyCode: 'bizcopilot',
      );

      ApiService.setClientForTesting(
        createMockClient((request) async {
          return http.Response(
            json.encode({
              'success': true,
              'data': {
                'id': 105,
                'name': 'Persistent Agent',
                'company_code': 'bizcopilot',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      // Request 1: profile
      await ApiService.getProfile();
      expect(capturedRequests.last.headers['X-Company-Code'], equals('bizcopilot'));

      // Request 2: followups query
      await ApiService.fetchServerFollowups(status: 'OPEN');
      expect(capturedRequests.last.headers['X-Company-Code'], equals('bizcopilot'));

      // Request 3: admin settings
      await ApiService.getAdminSettings();
      expect(capturedRequests.last.headers['X-Company-Code'], equals('bizcopilot'));

      expect(ConfigService.companyCode, equals('bizcopilot'));
    });

    test('MOB-007: Tenant switch replaces Company A session with Company B cleanly', () async {
      // 1. Session in Company A (INCREDIT)
      await ConfigService.saveAuthData(
        'token-company-a',
        {'id': 1, 'name': 'Agent A'},
        companyCode: 'INCREDIT',
      );

      ApiService.setClientForTesting(
        createMockClient((request) async {
          return http.Response(
            json.encode({
              'success': true,
              'data': {'id': 1, 'name': 'Agent A'},
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await ApiService.getAdminSettings();
      expect(capturedRequests.last.headers['X-Company-Code'], equals('incredit'));
      expect(capturedRequests.last.headers['Authorization'], equals('Bearer token-company-a'));

      // 2. Full Logout
      await ConfigService.clearAuthData(clearCompanyCode: true);
      expect(ConfigService.isLoggedIn, isFalse);
      expect(ConfigService.companyCode, isNull);

      // 3. Login to Company B (BIZCOPILOT)
      await ConfigService.saveAuthData(
        'token-company-b',
        {'id': 2, 'name': 'Agent B'},
        companyCode: 'BIZCOPILOT',
      );

      await ApiService.getAdminSettings();
      expect(capturedRequests.last.headers['X-Company-Code'], equals('bizcopilot'));
      expect(capturedRequests.last.headers['Authorization'], equals('Bearer token-company-b'));
    });

    test('MOB-008: Old token with mismatched tenant header is rejected with 401', () async {
      await ConfigService.saveAuthData(
        'old-token-company-a',
        {'id': 1},
        companyCode: 'BIZCOPILOT',
      );

      ApiService.setClientForTesting(
        createMockClient((request) async {
          // Server detects token belongs to Company A while header claims BIZCOPILOT
          return http.Response(
            json.encode({
              'success': false,
              'message': 'Token not authorized for tenant BIZCOPILOT',
            }),
            401,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await expectLater(
        () => ApiService.getAdminSettings(),
        throwsA(isA<Exception>()),
      );

      // 401 response must trigger session invalidation
      expect(ConfigService.isLoggedIn, isFalse);
      expect(ConfigService.token, isNull);
    });

    test('MOB-017: Concurrent requests consistently maintain identical tenant headers', () async {
      await ConfigService.saveAuthData(
        'token-concurrent-123',
        {'id': 55},
        companyCode: 'BIZCOPILOT',
      );

      ApiService.setClientForTesting(
        createMockClient((request) async {
          return http.Response(
            json.encode({
              'success': true,
              'data': {'status': 'ok'},
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      // Fire 5 concurrent requests simultaneously
      final futures = List.generate(5, (_) => ApiService.getAdminSettings());
      await Future.wait(futures);

      expect(capturedRequests.length, equals(5));
      for (final req in capturedRequests) {
        expect(req.headers['X-Company-Code'], equals('bizcopilot'));
        expect(req.headers['Authorization'], equals('Bearer token-concurrent-123'));
      }
    });
  });

  group('Group 3: Encrypted Storage & Session Lifecycle (MOB-009 - MOB-013, MOB-015, MOB-016)', () {
    test('MOB-009: Encrypted storage stores auth token and sensitive PII securely', () async {
      await ConfigService.saveAuthData(
        'super-secret-token-777',
        {
          'id': 42,
          'name': 'Pooja Sharma',
          'email': 'pooja@callnow.com',
          'mobile': '9812345678',
          'role': 'OFFICER',
        },
        companyCode: 'INCREDIT',
      );

      // Check encrypted store contains secrets
      expect(await memoryStorage.read(key: 'callnow_auth_token'), equals('super-secret-token-777'));
      expect(await memoryStorage.read(key: 'callnow_user_email'), equals('pooja@callnow.com'));
      expect(await memoryStorage.read(key: 'callnow_user_phone'), equals('9812345678'));
      expect(await memoryStorage.read(key: 'callnow_user_name'), equals('Pooja Sharma'));
      expect(await memoryStorage.read(key: 'callnow_user_id'), equals('42'));

      // Check shared_preferences does NOT contain token or password
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('callnow_auth_token'), isNull);
      expect(prefs.getString('password'), isNull);
      expect(prefs.getString('auth_password'), isNull);
    });

    test('MOB-010: Logout cleanup purges all keys from encrypted secure storage', () async {
      await ConfigService.saveAuthData(
        'token-to-delete',
        {
          'id': 99,
          'name': 'Temporary User',
          'email': 'temp@example.com',
          'mobile': '9000000000',
        },
        companyCode: 'INCREDIT',
      );

      expect(ConfigService.isLoggedIn, isTrue);

      // Full logout
      await ConfigService.clearAuthData(clearCompanyCode: true);

      expect(ConfigService.isLoggedIn, isFalse);
      expect(ConfigService.token, isNull);
      expect(ConfigService.userData, isNull);
      expect(ConfigService.companyCode, isNull);

      // Secure storage must be empty
      expect(await memoryStorage.read(key: 'callnow_auth_token'), isNull);
      expect(await memoryStorage.read(key: 'callnow_user_email'), isNull);
      expect(await memoryStorage.read(key: 'callnow_user_phone'), isNull);
      expect(await memoryStorage.read(key: 'callnow_user_name'), isNull);
      expect(await memoryStorage.read(key: 'callnow_user_id'), isNull);
      expect(await memoryStorage.read(key: 'callnow_company_code'), isNull);
    });

    test('MOB-011: Expired token on API call triggers auto-logout and invalidation', () async {
      await ConfigService.saveAuthData(
        'expired-token-401',
        {'id': 10, 'name': 'Session User'},
        companyCode: 'INCREDIT',
      );

      ApiService.setClientForTesting(
        createMockClient((request) async {
          return http.Response(
            json.encode({
              'success': false,
              'message': 'Session expired or token invalid',
            }),
            401,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await expectLater(
        () => ApiService.getProfile(),
        throwsA(isA<Exception>()),
      );

      expect(ConfigService.isLoggedIn, isFalse);
      expect(ConfigService.token, isNull);
      expect(await memoryStorage.read(key: 'callnow_auth_token'), isNull);
    });

    test('MOB-012: Device restart restores valid session from secure storage', () async {
      // 1. Establish session
      await ConfigService.saveAuthData(
        'restored-token-321',
        {'id': 88, 'name': 'Restart User'},
        companyCode: 'INCREDIT',
      );

      // 2. Simulate complete app restart by clearing memory cache
      ConfigService.resetForTesting();
      expect(ConfigService.isLoggedIn, isFalse);

      // 3. App initializes on reboot
      await ConfigService.init();

      expect(ConfigService.isLoggedIn, isTrue);
      expect(ConfigService.token, equals('restored-token-321'));
      expect(ConfigService.companyCode, equals('incredit'));
    });

    test('MOB-013: App data clearing leaves app in clean state with no credential reuse', () async {
      await ConfigService.saveAuthData(
        'token-to-wipe',
        {'id': 77, 'name': 'Wipe User'},
        companyCode: 'INCREDIT',
      );

      // Simulate Android "Clear App Data"
      await memoryStorage.deleteAll();
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      ConfigService.resetForTesting();

      // App starts up
      await ConfigService.init();

      expect(ConfigService.isLoggedIn, isFalse);
      expect(ConfigService.token, isNull);
      expect(ConfigService.companyCode, isNull);
      expect(ConfigService.userData, isNull);
    });

    test('MOB-015: Offline mode operates without leaking plaintext secrets to insecure storage', () async {
      await ConfigService.saveAuthData(
        'offline-token-111',
        {'id': 33, 'name': 'Offline User', 'email': 'offline@example.com'},
        companyCode: 'INCREDIT',
      );

      // Mock offline network failure (ClientException / SocketException)
      ApiService.setClientForTesting(
        createMockClient((request) async {
          throw http.ClientException('Network unreachable');
        }),
      );

      await expectLater(
        () => ApiService.getAdminSettings(),
        throwsA(isA<http.ClientException>()),
      );

      // Session remains safely intact in encrypted storage
      expect(ConfigService.isLoggedIn, isTrue);
      expect(await memoryStorage.read(key: 'callnow_auth_token'), equals('offline-token-111'));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('callnow_auth_token'), isNull);
    });

    test('MOB-016: Network switching keeps token and company code resilient and unchanged', () async {
      await ConfigService.saveAuthData(
        'resilient-token-444',
        {'id': 44, 'name': 'Mobile User'},
        companyCode: 'INCREDIT',
      );

      int requestCount = 0;
      ApiService.setClientForTesting(
        createMockClient((request) async {
          requestCount++;
          if (requestCount == 1) {
            // Wi-Fi dropped mid-request
            throw http.ClientException('Connection reset by peer');
          }
          // Cell network reconnected
          return http.Response(
            json.encode({'success': true, 'data': {'status': 'healthy'}}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      // First try fails due to switch
      await expectLater(
        () => ApiService.getAdminSettings(),
        throwsA(isA<http.ClientException>()),
      );

      // Second try succeeds on new network
      final res = await ApiService.getAdminSettings();
      expect(res['status'], equals('healthy'));

      expect(ConfigService.token, equals('resilient-token-444'));
      expect(ConfigService.companyCode, equals('incredit'));
    });
  });

  group('Group 4: Access Control & Mid-Session Revocation (MOB-014, MOB-018 - MOB-020)', () {
    test('MOB-014: Officer role attempting Admin endpoint receives 403 Forbidden', () async {
      await ConfigService.saveAuthData(
        'officer-token-014',
        {'id': 14, 'role': 'OFFICER'},
        companyCode: 'INCREDIT',
      );

      ApiService.setClientForTesting(
        createMockClient((request) async {
          return http.Response(
            json.encode({
              'success': false,
              'message': 'Access forbidden: Administrator privileges required',
            }),
            403,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await expectLater(
        () => ApiService.getAdminSettings(),
        throwsA(isA<Exception>()),
      );
    });

    test('MOB-018: Other company resource/document lookup returns 403 Forbidden', () async {
      await ConfigService.saveAuthData(
        'officer-token-018',
        {'id': 18, 'role': 'OFFICER'},
        companyCode: 'INCREDIT',
      );

      ApiService.setClientForTesting(
        createMockClient((request) async {
          // Attempting to access resource owned by another tenant
          return http.Response(
            json.encode({
              'success': false,
              'message': 'Access denied: document belongs to another company tenant',
            }),
            403,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await expectLater(
        () => ApiService.fetchServerFollowups(userId: 99999),
        throwsA(isA<Exception>()),
      );
    });

    test('MOB-019: Mid-session tenant suspension invalidates active session on next call', () async {
      await ConfigService.saveAuthData(
        'token-mid-session-019',
        {'id': 19},
        companyCode: 'INCREDIT',
      );

      int callIndex = 0;
      ApiService.setClientForTesting(
        createMockClient((request) async {
          callIndex++;
          if (callIndex == 1) {
            return http.Response(
              json.encode({
                'success': true,
                'data': {'id': 19, 'name': 'Active'},
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          // Admin suspended company mid-session
          return http.Response(
            json.encode({
              'success': false,
              'message': 'Tenant company has been suspended',
            }),
            401,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      // Call 1 succeeds
      final profile = await ApiService.getProfile();
      expect(profile, isNotEmpty);
      expect(ConfigService.isLoggedIn, isTrue);

      // Call 2 encounters suspension
      await expectLater(
        () => ApiService.getProfile(),
        throwsA(isA<Exception>()),
      );

      // Session cleared automatically
      expect(ConfigService.isLoggedIn, isFalse);
      expect(ConfigService.token, isNull);
    });

    test('MOB-020: User account deactivated mid-session triggers session termination', () async {
      await ConfigService.saveAuthData(
        'token-deactivated-020',
        {'id': 20},
        companyCode: 'INCREDIT',
      );

      ApiService.setClientForTesting(
        createMockClient((request) async {
          return http.Response(
            json.encode({
              'success': false,
              'message': 'User account has been deactivated',
            }),
            401,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await expectLater(
        () => ApiService.getAdminSettings(),
        throwsA(isA<Exception>()),
      );

      expect(ConfigService.isLoggedIn, isFalse);
      expect(ConfigService.token, isNull);
    });
  });

  group('Group 5: Additional Mobile Security & Sanity Checks', () {
    test('Check A: No company database credentials are stored in secure storage or prefs', () async {
      await ConfigService.saveAuthData(
        'token-security-check',
        {'id': 100, 'name': 'Security Officer'},
        companyCode: 'INCREDIT',
      );

      final prefs = await SharedPreferences.getInstance();
      const forbiddenDbKeys = [
        'db_user',
        'db_pass',
        'db_password',
        'database_url',
        'mysql_password',
        'db_connection',
        'company_db_cred',
      ];

      for (final key in forbiddenDbKeys) {
        expect(await memoryStorage.read(key: key), isNull);
        expect(prefs.getString(key), isNull);
      }
    });

    test('Check B: Protected API endpoints require token and reject unauthenticated requests', () async {
      // No token set
      expect(ConfigService.isLoggedIn, isFalse);
      expect(ConfigService.token, isNull);

      ApiService.setClientForTesting(
        createMockClient((request) async {
          if (!request.headers.containsKey('Authorization')) {
            return http.Response(
              json.encode({'success': false, 'message': 'Authentication required'}),
              401,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('OK', 200);
        }),
      );

      await expectLater(
        () => ApiService.getAdminSettings(),
        throwsA(isA<Exception>()),
      );
    });

    test('Check C: Every authenticated API request carries X-Company-Code header', () async {
      await ConfigService.saveAuthData(
        'token-header-check',
        {'id': 50},
        companyCode: 'BIZCOPILOT',
      );

      ApiService.setClientForTesting(
        createMockClient((request) async {
          return http.Response(
            json.encode({'success': true, 'data': {}}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await ApiService.getAdminSettings();

      expect(capturedRequests, isNotEmpty);
      expect(capturedRequests.last.headers['X-Company-Code'], equals('bizcopilot'));
      expect(capturedRequests.last.headers['Authorization'], equals('Bearer token-header-check'));
    });

    test('Check D: lib/ codebase contains no hardcoded print/debugPrint of passwords or auth tokens', () {
      final libDir = Directory('lib');
      expect(libDir.existsSync(), isTrue);

      final files = libDir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

      final secretLogPattern = RegExp(
        r'''(print|debugPrint)\s*\(\s*['"].*?(password|bearer\s*token|client_secret).*?['"]''',
        caseSensitive: false,
      );

      for (final file in files) {
        final content = file.readAsStringSync();
        final matches = secretLogPattern.allMatches(content);
        expect(
          matches.isEmpty,
          isTrue,
          reason: 'Found potential secret print in ${file.path}',
        );
      }
    });
  });
}
