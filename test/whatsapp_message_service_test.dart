import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:callnow_new/services/config_service.dart';
import 'package:callnow_new/services/whatsapp_message_service.dart';
import 'package:callnow_new/services/secure_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SecureStorageService.setBackendForTesting(MemorySecureStorageBackend());
    await ConfigService.saveAuthData('test-token', {
      'name': 'Taylor Agent',
      'role': 'Telecaller',
      'company': 'CallNow Finance',
      'mobile': '9876543210',
    });
  });

  tearDown(() {
    SecureStorageService.resetBackend();
  });

  test('uses the default template until a custom one is saved', () async {
    expect(
      await WhatsAppMessageService.loadTemplate(),
      WhatsAppMessageService.defaultTemplate,
    );

    await WhatsAppMessageService.saveTemplate('Custom greeting for [Name]');

    expect(
      await WhatsAppMessageService.loadTemplate(),
      'Custom greeting for [Name]',
    );
  });

  test('personalizes known details and keeps offer placeholders editable', () {
    final message = WhatsAppMessageService.personalize(
      'Dear [Name] from [Company Name], call [Phone Number]. '
          'Offer: [Amount]. Signed, [Your Name/Title].',
      'Morgan Client',
    );

    expect(message, contains('Dear Morgan Client from CallNow Finance'));
    expect(message, contains('call 9876543210'));
    expect(message, contains('Offer: [Amount]'));
    expect(message, contains('Taylor Agent / TELECALLER'));
  });

  test(
    'quick WhatsApp intro defaults on and can be changed persistently',
    () async {
      expect(await WhatsAppMessageService.isIntroEnabled(), isTrue);

      await WhatsAppMessageService.setIntroEnabled(false);

      expect(await WhatsAppMessageService.isIntroEnabled(), isFalse);
    },
  );
}
