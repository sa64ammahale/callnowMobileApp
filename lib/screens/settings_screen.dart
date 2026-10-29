import 'package:flutter/material.dart';
import 'package:callnow_new/services/config_service.dart';
import 'package:callnow_new/services/call_tracking_service.dart';
import 'package:callnow_new/services/api_service.dart';

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
  Widget build(BuildContext context) {
    final userName = ConfigService.userDisplayName;
    final role = ConfigService.userRole;
    final userId = ConfigService.userId;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() {});
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Agent Card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                      child: Text(
                        userName.toString().isNotEmpty ? userName.toString()[0].toUpperCase() : 'U',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            userName.toString(),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Role: $role • ID: $userId',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                'Connected & Ready',
                                style: TextStyle(
                                  color: Colors.green,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Calling Preferences
            const Text(
              'Calling Preferences',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Card(
              elevation: 1.5,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Vibrate on Call End', style: TextStyle(fontSize: 14)),
                    subtitle: const Text('Provide haptic feedback when call terminates', style: TextStyle(fontSize: 12)),
                    value: _vibrateOnEnd,
                    onChanged: (val) => setState(() => _vibrateOnEnd = val),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: const Text('Keep Screen Awake', style: TextStyle(fontSize: 14)),
                    subtitle: const Text('Keep display active during call sessions', style: TextStyle(fontSize: 12)),
                    value: _keepScreenOn,
                    onChanged: (val) => setState(() => _keepScreenOn = val),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: const Text('Quick WhatsApp Intro', style: TextStyle(fontSize: 14)),
                    subtitle: const Text('Pre-fill personalized message for client WhatsApp chat', style: TextStyle(fontSize: 12)),
                    value: _quickWhatsAppPrompt,
                    onChanged: (val) => setState(() => _quickWhatsAppPrompt = val),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Call Setup & Permissions
            const Text(
              'Device Setup',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Card(
              elevation: 1.5,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.phone_in_talk, color: Colors.blue),
                    title: const Text('Phone Permissions', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                    subtitle: const Text('Check and grant system phone state permissions', style: TextStyle(fontSize: 12)),
                    trailing: const Icon(Icons.chevron_right),
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
                          ),
                        );
                      }
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.refresh, color: Colors.teal),
                    title: const Text('Refresh Assigned Leads', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                    subtitle: const Text('Check for newly assigned client leads on server', style: TextStyle(fontSize: 12)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Leads queue refreshed.')),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // App Information
            const Text(
              'About CallNow',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Card(
              elevation: 1.5,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: Column(
                children: [
                  const ListTile(
                    leading: Icon(Icons.info_outline),
                    title: Text('App Version', style: TextStyle(fontSize: 14)),
                    subtitle: Text('CallNow 5.0 (Telecaller Desk)', style: TextStyle(fontSize: 12)),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.logout, color: Colors.red),
                    title: const Text('Sign Out', style: TextStyle(fontSize: 14, color: Colors.red, fontWeight: FontWeight.bold)),
                    subtitle: const Text('Log out of this telecalling session', style: TextStyle(fontSize: 12)),
                    onTap: () async {
                      await ApiService.logout();
                      if (context.mounted) {
                        Navigator.pushReplacementNamed(context, '/login');
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
      ),
    );
  }
}