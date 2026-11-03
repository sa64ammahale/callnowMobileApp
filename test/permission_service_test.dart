import 'package:flutter_test/flutter_test.dart';
import 'package:callnow_new/services/permission_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    PermissionService.mockReport = null;
  });

  group('PermissionService Tests', () {
    test('reports allGranted true when all 4 permissions are active', () async {
      PermissionService.mockReport = const PermissionStatusReport(
        phoneState: true,
        callLog: true,
        callPhone: true,
        notifications: true,
      );

      final report = await PermissionService.checkAllPermissions();
      expect(report.allGranted, isTrue);
      expect(report.grantedCount, equals(4));
      expect(await PermissionService.hasAllPermissions(), isTrue);
    });

    test('reports allGranted false when any permission is missing', () async {
      PermissionService.mockReport = const PermissionStatusReport(
        phoneState: true,
        callLog: false, // missing
        callPhone: true,
        notifications: true,
      );

      final report = await PermissionService.checkAllPermissions();
      expect(report.allGranted, isFalse);
      expect(report.grantedCount, equals(3));
      expect(await PermissionService.hasAllPermissions(), isFalse);
    });

    test('counts granted permissions accurately across partial combinations', () {
      const partial = PermissionStatusReport(
        phoneState: true,
        callLog: false,
        callPhone: true,
        notifications: false,
      );
      expect(partial.grantedCount, equals(2));
      expect(partial.totalCount, equals(4));
      expect(partial.allGranted, isFalse);
    });
  });
}

