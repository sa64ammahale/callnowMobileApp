import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:callnow_new/services/api_service.dart';
import 'package:callnow_new/services/config_service.dart';

class ServerSettingsScreen extends StatefulWidget {
  final bool isFromLogin;

  const ServerSettingsScreen({
    super.key,
    this.isFromLogin = false,
  });

  @override
  State<ServerSettingsScreen> createState() => _ServerSettingsScreenState();
}

class _ServerSettingsScreenState extends State<ServerSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _urlController;

  bool _isTesting = false;
  bool _isSaving = false;
  Map<String, dynamic>? _testResult;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: ConfigService.baseUrl);
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;
    final candidate = ConfigService.resolveServerUrl(_urlController.text);
    if (_urlController.text.trim() != candidate) {
      _urlController.text = candidate;
    }

    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    final res = await ApiService.testConnection(candidate);

    if (mounted) {
      setState(() {
        _isTesting = false;
        _testResult = res;
      });
    }
  }

  Future<void> _resetToDefault() async {
    final defaultUrl = ConfigService.defaultBaseUrl;
    setState(() {
      _urlController.text = defaultUrl;
      _testResult = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Reset field to default server URL. Tap "Save & Apply" to persist.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.trim().isNotEmpty) {
      setState(() {
        _urlController.text = data.text!.trim();
        _testResult = null;
      });
    }
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;
    final newUrl = ConfigService.resolveServerUrl(_urlController.text);

    // If changing server while logged in, prompt confirmation that it logs out
    if (ConfigService.isLoggedIn && newUrl != ConfigService.baseUrl) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 24),
              SizedBox(width: 8),
              Text('Switch Server?'),
            ],
          ),
          content: const Text(
            'Switching to a different server endpoint will clear your existing login session to prevent authentication token conflicts on the new server.\n\nDo you want to proceed and return to sign in?',
            style: TextStyle(fontSize: 13.5, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
              ),
              child: const Text('Switch & Sign Out'),
            ),
          ],
        ),
      );

      if (confirm != true) return;

      setState(() => _isSaving = true);
      await ConfigService.setBaseUrl(newUrl);
      await ConfigService.clearAuthData();
      if (!mounted) return;

      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Server endpoint updated to $newUrl. Please sign in.'),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    await ConfigService.setBaseUrl(newUrl);
    setState(() => _isSaving = false);

    if (!mounted) return;
    Navigator.of(context).pop(true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Base API URL updated to $newUrl'),
        backgroundColor: const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUrl = ConfigService.baseUrl;
    final isDefault = ConfigService.isUsingDefault;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Server Configuration',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: const Color(0xFFE2E8F0), height: 1),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header card with active server indicator
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: isDefault
                                      ? const Color(0xFFECFDF5)
                                      : const Color(0xFFF5F3FF),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  Icons.dns_rounded,
                                  color: isDefault
                                      ? const Color(0xFF10B981)
                                      : const Color(0xFF7C3AED),
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      isDefault ? 'Default Cloud Server' : 'Custom Server Active',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: isDefault
                                            ? const Color(0xFF047857)
                                            : const Color(0xFF6D28D9),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      currentUrl,
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        fontFamily: 'monospace',
                                        color: Color(0xFF64748B),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isDefault
                                      ? const Color(0xFFD1FAE5)
                                      : const Color(0xFFEDE9FE),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  isDefault ? 'Production' : 'Custom',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                    color: isDefault
                                        ? const Color(0xFF065F46)
                                        : const Color(0xFF5B21B6),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Main configuration card
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.link_rounded, size: 18, color: Color(0xFF2563EB)),
                              SizedBox(width: 8),
                              Text(
                                'Base API Address',
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Enter your Company Code (e.g. zenith) or the full server URL prefix (e.g. https://zenith.increditsolutions.in/api/v1).',
                            style: TextStyle(fontSize: 12, color: Color(0xFF64748B), height: 1.4),
                          ),
                          const SizedBox(height: 14),

                          // Text input field
                          TextFormField(
                            controller: _urlController,
                            keyboardType: TextInputType.url,
                            autocorrect: false,
                            enableSuggestions: false,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w500,
                            ),
                            decoration: InputDecoration(
                              hintText: 'zenith or https://zenith.increditsolutions.in/api/v1',
                              hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                              prefixIcon: const Icon(Icons.public_rounded, size: 20),
                              suffixIcon: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.paste_rounded, size: 18),
                                    tooltip: 'Paste from clipboard',
                                    onPressed: _pasteFromClipboard,
                                  ),
                                  if (_urlController.text.isNotEmpty)
                                    IconButton(
                                      icon: const Icon(Icons.clear_rounded, size: 18),
                                      tooltip: 'Clear',
                                      onPressed: () {
                                        setState(() {
                                          _urlController.clear();
                                          _testResult = null;
                                        });
                                      },
                                    ),
                                ],
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
                              ),
                            ),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) {
                                return 'Please enter Company Code or Server URL';
                              }
                              final resolved = ConfigService.resolveServerUrl(val);
                              final uri = Uri.tryParse(resolved);
                              if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https')) || uri.host.isEmpty) {
                                return 'Enter a valid company code or server URL';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),

                          // Test Connection button & result pill
                          Row(
                            children: [
                              OutlinedButton.icon(
                                onPressed: _isTesting ? null : _testConnection,
                                icon: _isTesting
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.network_check_rounded, size: 16),
                                label: Text(_isTesting ? 'Testing...' : 'Test Connection'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: _resetToDefault,
                                child: const Text(
                                  'Reset to Default',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),

                          // Diagnostic test feedback badge
                          if (_testResult != null) ...[
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: _testResult!['success'] == true
                                    ? const Color(0xFFECFDF5)
                                    : const Color(0xFFFEF2F2),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: _testResult!['success'] == true
                                      ? const Color(0xFFA7F3D0)
                                      : const Color(0xFFFECACA),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    _testResult!['success'] == true
                                        ? Icons.check_circle_rounded
                                        : Icons.error_rounded,
                                    size: 18,
                                    color: _testResult!['success'] == true
                                        ? const Color(0xFF059669)
                                        : const Color(0xFFDC2626),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _testResult!['success'] == true
                                              ? 'Connection Successful'
                                              : 'Connection Unsuccessful',
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.bold,
                                            color: _testResult!['success'] == true
                                                ? const Color(0xFF065F46)
                                                : const Color(0xFF991B1B),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _testResult!['message']?.toString() ?? '',
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            color: _testResult!['success'] == true
                                                ? const Color(0xFF047857)
                                                : const Color(0xFFB91C1C),
                                            height: 1.3,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Formatting tips & examples card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.lightbulb_outline_rounded, size: 16, color: Color(0xFF475569)),
                              SizedBox(width: 6),
                              Text(
                                'Common Server Formats:',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF334155),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _buildExampleRow('Company Code', 'zenith (resolves to: https://zenith.increditsolutions.in/api/v1)'),
                          const SizedBox(height: 4),
                          _buildExampleRow('Cloud Production', ConfigService.defaultBaseUrl),
                          const SizedBox(height: 4),
                          _buildExampleRow('Custom Domain', 'https://crm.yourcompany.com/api/v1'),
                          const SizedBox(height: 4),
                          _buildExampleRow('Local / LAN IP', 'http://192.168.1.100/callnowCRM/api/v1'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Save & Apply button
                    SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _handleSave,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Text(
                                'Save & Apply Server Address',
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExampleRow(String label, String exampleUrl) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '• $label: ',
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
        ),
        Expanded(
          child: Text(
            exampleUrl,
            style: const TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              color: Color(0xFF2563EB),
            ),
          ),
        ),
      ],
    );
  }
}

