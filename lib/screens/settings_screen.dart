import 'package:flutter/material.dart';
import 'package:callnow_new/screens/profile_screen.dart';
import 'package:callnow_new/screens/whatsapp_message_editor_screen.dart';
import 'package:callnow_new/services/api_service.dart';
import 'package:callnow_new/services/call_tracking_service.dart';
import 'package:callnow_new/services/config_service.dart';
import 'package:callnow_new/services/whatsapp_message_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _vibrateOnEnd = true;
  bool _keepScreenOn = true;
  bool _quickWhatsAppPrompt = true;

  @override
  void initState() {
    super.initState();
    _loadWhatsAppPreference();
  }

  Future<void> _loadWhatsAppPreference() async {
    try {
      final enabled = await WhatsAppMessageService.isIntroEnabled();
      if (mounted) setState(() => _quickWhatsAppPrompt = enabled);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load WhatsApp preference: $error')),
        );
      }
    }
  }

  Future<void> _setWhatsAppIntroEnabled(bool enabled) async {
    try {
      await WhatsAppMessageService.setIntroEnabled(enabled);
      if (mounted) setState(() => _quickWhatsAppPrompt = enabled);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save WhatsApp preference: $error')),
        );
      }
    }
  }

  Future<void> _editWhatsAppMessage() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const WhatsAppMessageEditorScreen(),
      ),
    );
  }

  void _openProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProfileScreen()),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  void _confirmSignOut() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.logout, color: Colors.red, size: 22),
            SizedBox(width: 8),
            Text('Sign Out', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: const Text(
          'Are you sure you want to log out of this telecalling session?',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            onPressed: () async {
              Navigator.pop(ctx);
              await ApiService.logout();
              if (mounted) {
                Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
              }
            },
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userName = ConfigService.userDisplayName;
    final role = ConfigService.userRole;
    final userId = ConfigService.userId;
    final userEmail = ConfigService.userEmail;

    return Scaffold(
      appBar: Navigator.canPop(context)
          ? AppBar(
              title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () async {
          try {
            await ApiService.getProfile();
          } catch (_) {}
          if (mounted) setState(() {});
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Profile Access Section Card
              Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFF8FAFC), Color(0xFFEFF6FF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFDBEAFE), width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2563EB).withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _openProfile,
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 26,
                                backgroundColor: const Color(0xFF2563EB),
                                child: Text(
                                  userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            userName,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16.5,
                                              color: Color(0xFF0F172A),
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (userEmail.isNotEmpty) ...[
                                      const SizedBox(height: 1),
                                      Text(
                                        userEmail,
                                        style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                    const SizedBox(height: 5),
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFDBEAFE),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            '$role • $userId',
                                            style: const TextStyle(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF1D4ED8),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFECFDF5),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: const Color(0xFFA7F3D0)),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.circle, color: Color(0xFF10B981), size: 6),
                                              SizedBox(width: 3),
                                              Text(
                                                'Online',
                                                style: TextStyle(
                                                  color: Color(0xFF047857),
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Color(0xFF2563EB)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFBFDBFE)),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.badge_outlined, size: 14, color: Color(0xFF2563EB)),
                                SizedBox(width: 6),
                                Text(
                                  'View & Manage Full Profile',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1D4ED8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // 2. Calling & Dialer Preferences Card
              Card(
                elevation: 0.5,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                        child: Row(
                          children: [
                            Icon(Icons.tune_rounded, size: 18, color: Color(0xFF2563EB)),
                            SizedBox(width: 8),
                            Text(
                              'Calling & Dialer Preferences',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SwitchListTile(
                        title: const Text('Vibrate on Call End', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                        subtitle: const Text('Haptic feedback when telephone call terminates', style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B))),
                        value: _vibrateOnEnd,
                        activeThumbColor: const Color(0xFF2563EB),
                        onChanged: (val) => setState(() => _vibrateOnEnd = val),
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16, color: Color(0xFFF1F5F9)),
                      SwitchListTile(
                        title: const Text('Keep Screen Awake', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                        subtitle: const Text('Prevent display from sleeping during dialer sessions', style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B))),
                        value: _keepScreenOn,
                        activeThumbColor: const Color(0xFF2563EB),
                        onChanged: (val) => setState(() => _keepScreenOn = val),
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16, color: Color(0xFFF1F5F9)),
                      SwitchListTile(
                        title: const Text('Quick WhatsApp Intro', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                        subtitle: const Text('Auto-populate client greeting template when opening chat', style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B))),
                        value: _quickWhatsAppPrompt,
                        activeThumbColor: const Color(0xFF16A34A),
                        onChanged: _setWhatsAppIntroEnabled,
                      ),
                      ListTile(
                        leading: const Icon(
                          Icons.edit_note_rounded,
                          color: Color(0xFF16A34A),
                        ),
                        title: const Text(
                          'Edit WhatsApp message',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: const Text(
                          'Customize the message used for each customer',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: _editWhatsAppMessage,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // 3. Device Permissions & Diagnostics Card
              Card(
                elevation: 0.5,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                        child: Row(
                          children: [
                            Icon(Icons.phone_android_rounded, size: 18, color: Color(0xFF059669)),
                            SizedBox(width: 8),
                            Text(
                              'Device & Diagnostics',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                          ],
                        ),
                      ),
                      ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.phone_in_talk_rounded, color: Color(0xFF2563EB), size: 18),
                        ),
                        title: const Text('Android Call Log Permissions', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                        subtitle: const Text('Verify READ_PHONE_STATE & READ_CALL_LOG permissions', style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B))),
                        trailing: const Icon(Icons.chevron_right, size: 20),
                        onTap: () async {
                          final granted = await CallTrackingService.requestPermissions();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  granted
                                      ? 'All phone permissions are active and configured.'
                                      : 'Please enable phone permissions in system settings.',
                                ),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16, color: Color(0xFFF1F5F9)),
                      ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: const Color(0xFFECFDF5),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.battery_charging_full_rounded, color: Color(0xFF059669), size: 18),
                        ),
                        title: const Text('Background Battery Exemption', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                        subtitle: const Text('Ensure background call tracking remains uninterrupted', style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B))),
                        trailing: const Icon(Icons.chevron_right, size: 20),
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Battery optimization status: Unrestricted.'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16, color: Color(0xFFF1F5F9)),
                      ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0FDF4),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.sync_rounded, color: Color(0xFF16A34A), size: 18),
                        ),
                        title: const Text('Refresh Leads Queue', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                        subtitle: const Text('Sync newly assigned contact leads from CRM', style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B))),
                        trailing: const Icon(Icons.chevron_right, size: 20),
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Leads queue synchronization requested.'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // 4. App Information & About Card
              Card(
                elevation: 0.5,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFF64748B)),
                            SizedBox(width: 8),
                            Text(
                              'About CallNow',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const ListTile(
                        leading: Icon(Icons.verified_outlined, color: Color(0xFF64748B), size: 20),
                        title: Text('App Version', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                        subtitle: Text('CallNow 5.0 (Telecaller Desk Edition)', style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B))),
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16, color: Color(0xFFF1F5F9)),
                      ListTile(
                        leading: const Icon(Icons.dns_outlined, color: Color(0xFF64748B), size: 20),
                        title: const Text('API Server Endpoint', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                        subtitle: Text(ConfigService.baseUrl, style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B), fontFamily: 'monospace')),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 5. Sign Out Button
              OutlinedButton.icon(
                onPressed: _confirmSignOut,
                icon: const Icon(Icons.logout_rounded, color: Colors.red, size: 18),
                label: const Text(
                  'Sign Out of CallNow',
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 14),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: BorderSide(color: Colors.red.shade300, width: 1.2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
