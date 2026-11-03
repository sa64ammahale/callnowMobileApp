import 'package:shared_preferences/shared_preferences.dart';
import 'package:callnow_new/services/config_service.dart';

class WhatsAppMessageService {
  static const String templateStorageKey = 'whatsapp_message_template_v1';
  static const String enabledStorageKey = 'whatsapp_intro_enabled_v1';

  static const String defaultTemplate = '''Dear [Name],
Looking to fund a major purchase, manage expenses, or consolidate debt? *[Company Name]* has an exclusive pre-approved loan offer tailored just for you.
*Why choose us?*

- *Loan Amount:* Up to ₹[Amount]
- *Attractive Interest Rates:* Starting from [Percentage]% p.a.
- *Flexible Tenure:* Choose from [Min Months] to [Max Months] months.
- *100% Digital Process:* Paperless application with instant approval.
Click the link below to claim your offer and check your customized repayment schedule:
👉 *[Apply Online Now Link]*
If you have any questions, feel free to reply to this email or call our support team at [Phone Number].
Best regards,
*[Your Name/Title]*
[Company Name]
_Disclaimer: Loans are disbursed at the sole discretion of the lender. T&C Apply._''';

  static Future<String> loadTemplate() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(templateStorageKey) ?? defaultTemplate;
  }

  static Future<void> saveTemplate(String template) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(templateStorageKey, template);
  }

  static Future<bool> isIntroEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(enabledStorageKey) ?? true;
  }

  static Future<void> setIntroEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(enabledStorageKey, enabled);
  }

  static String personalize(String template, String customerName) {
    final userData = ConfigService.userData ?? const <String, dynamic>{};
    final companyName = userData['company']?.toString().trim() ?? '';
    final phoneNumber = ConfigService.userPhone;
    final userName = ConfigService.userDisplayName;
    final role = ConfigService.userRole;

    final replacements = <String, String>{
      '[Name]': customerName,
      '[Company Name]': companyName,
      '[Phone Number]': phoneNumber,
      '[Your Name/Title]': role.isNotEmpty ? '$userName / $role' : userName,
    };

    return template.replaceAllMapped(RegExp(r'\[[^\]]+\]'), (match) {
      final placeholder = match.group(0)!;
      final value = replacements[placeholder]?.trim();
      return value == null || value.isEmpty ? placeholder : value;
    });
  }
}
