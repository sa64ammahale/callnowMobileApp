import 'package:flutter/material.dart';
import 'package:callnow_new/services/api_service.dart';
import 'package:callnow_new/services/call_tracking_service.dart';
import 'package:callnow_new/services/config_service.dart';
import 'package:callnow_new/screens/calling_desk_screen.dart';
import 'package:callnow_new/screens/call_reports_screen.dart';
import 'package:callnow_new/screens/settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _initCallTracker();
  }

  Future<void> _initCallTracker() async {
    final success = await CallTrackingService.initialize();
    if (mounted && !success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Phone call permissions needed to automatically record call timing.',
          ),
          action: SnackBarAction(
            label: 'Enable',
            onPressed: () => CallTrackingService.initialize(),
          ),
        ),
      );
    }
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      DashboardPage(
        onStartCalling: () => _onItemTapped(1),
        onOpenReports: () => _onItemTapped(2),
        onOpenProfile: () => _onItemTapped(3),
      ),
      const CallingDeskScreen(),
      const CallReportsScreen(),
      const ProfilePage(),
      const SettingsScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.phone_in_talk, size: 22),
            SizedBox(width: 8),
            Text('CallNow', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () async {
              await ApiService.logout();
              if (context.mounted) {
                Navigator.pushReplacementNamed(context, '/login');
              }
            },
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onItemTapped,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.phone_in_talk_outlined),
            selectedIcon: Icon(Icons.phone_in_talk),
            label: 'Calling Desk',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: 'Reports',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// TELECALLER DASHBOARD TAB (Logged-In User Focused)
// -----------------------------------------------------------------------------
class DashboardPage extends StatefulWidget {
  final VoidCallback onStartCalling;
  final VoidCallback onOpenReports;
  final VoidCallback onOpenProfile;

  const DashboardPage({
    super.key,
    required this.onStartCalling,
    required this.onOpenReports,
    required this.onOpenProfile,
  });

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool _isLoading = true;
  Map<String, dynamic>? _stats;
  Map<String, dynamic>? _summary;

  @override
  void initState() {
    super.initState();
    _loadLiveStats();
  }

  Future<void> _loadLiveStats() async {
    setState(() => _isLoading = true);
    try {
      if (ConfigService.userData == null || ConfigService.userDisplayName == 'Telecaller') {
        try {
          await ApiService.getProfile();
        } catch (_) {}
      }

      final results = await Future.wait([
        ApiService.getDashboardStats().catchError((_) => <String, dynamic>{}),
        ApiService.getCallReportSummary(period: 'today').catchError((_) => <String, dynamic>{}),
      ]);

      if (mounted) {
        setState(() {
          _stats = results[0];
          _summary = results[1];
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatDuration(dynamic rawSeconds) {
    final totalSeconds = rawSeconds is int ? rawSeconds : (int.tryParse(rawSeconds?.toString() ?? '') ?? 0);
    if (totalSeconds <= 0) return '0s';
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    if (minutes == 0) return '${seconds}s';
    if (seconds == 0) return '${minutes}m';
    return '${minutes}m ${seconds}s';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final userName = ConfigService.userDisplayName;
    final userRole = ConfigService.userRole;

    final callsLogged = _stats?['today_calls'] ?? _summary?['total_calls'] ?? 0;
    final connectedCalls = _stats?['today_connected'] ?? _summary?['connected_calls'] ?? 0;
    final talkSeconds = _stats?['today_talk_time'] ?? _summary?['total_duration_seconds'] ?? 0;
    final talkTimeFormatted = _formatDuration(talkSeconds);

    final statusBreakdown = _summary?['status_breakdown'] as Map<String, dynamic>? ?? {};
    int followupsCount = 0;
    statusBreakdown.forEach((k, v) {
      final keyLower = k.toLowerCase();
      if (keyLower.contains('follow') || keyLower.contains('callback')) {
        followupsCount += (v is int ? v : (int.tryParse(v.toString()) ?? 0));
      }
    });

    final connectionRate = callsLogged > 0
        ? ((connectedCalls / callsLogged) * 100).toStringAsFixed(0)
        : '0';

    return RefreshIndicator(
      onRefresh: _loadLiveStats,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // User Greeting Header with Real User Identity
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: colorScheme.primaryContainer,
                  child: Text(
                    userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Welcome, $userName',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '$userRole • Telecalling Desk',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadLiveStats,
                  tooltip: 'Refresh Stats',
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Hero CTA Card: Start Calling Session (Fully Clickable)
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: widget.onStartCalling,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1E3C72), Color(0xFF2A5298)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Calling Desk',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'READY',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Start calling from here to connect with your assigned clients and record call outcomes.',
                        style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.3),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: widget.onStartCalling,
                          icon: const Icon(Icons.phone_in_talk, size: 20),
                          label: const Text(
                            'Start Calling Session',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF1E3C72),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Live Personal Telecaller Stats Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Today's Personal Performance",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                TextButton(
                  onPressed: widget.onOpenReports,
                  child: const Text('View All', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 24.0),
                  child: CircularProgressIndicator(),
                ),
              )
            else
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.4,
                children: [
                  _buildStatCard(
                    context,
                    title: 'Calls Dialed',
                    value: callsLogged.toString(),
                    subtitle: "Today's dialed calls",
                    icon: Icons.phone_forwarded,
                    color: Colors.blue,
                    onTap: widget.onOpenReports,
                  ),
                  _buildStatCard(
                    context,
                    title: 'Connected Calls',
                    value: connectedCalls.toString(),
                    subtitle: '$connectionRate% picked up',
                    icon: Icons.phone_in_talk,
                    color: Colors.green,
                    onTap: widget.onOpenReports,
                  ),
                  _buildStatCard(
                    context,
                    title: "Today's Talk Time",
                    value: talkTimeFormatted,
                    subtitle: 'Cumulative spoken time',
                    icon: Icons.timer,
                    color: Colors.purple,
                    onTap: widget.onOpenReports,
                  ),
                  _buildStatCard(
                    context,
                    title: 'Follow-ups Pending',
                    value: followupsCount.toString(),
                    subtitle: 'Scheduled callbacks',
                    icon: Icons.event_repeat,
                    color: Colors.amber.shade900,
                    onTap: widget.onOpenReports,
                  ),
                ],
              ),
            const SizedBox(height: 20),

            // Quick Shortcuts Card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Quick Shortcuts',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.blue.withValues(alpha: 0.1),
                        child: const Icon(Icons.phone_in_talk, color: Colors.blue, size: 20),
                      ),
                      title: const Text('Open Calling Desk', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      subtitle: const Text('Access next client lead and start calls', style: TextStyle(fontSize: 12)),
                      trailing: const Icon(Icons.chevron_right, size: 20),
                      contentPadding: EdgeInsets.zero,
                      onTap: widget.onStartCalling,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.teal.withValues(alpha: 0.1),
                        child: const Icon(Icons.bar_chart, color: Colors.teal, size: 20),
                      ),
                      title: const Text('Detailed Call Reports', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      subtitle: const Text('Review talk times, outcomes and dialed history', style: TextStyle(fontSize: 12)),
                      trailing: const Icon(Icons.chevron_right, size: 20),
                      contentPadding: EdgeInsets.zero,
                      onTap: widget.onOpenReports,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.purple.withValues(alpha: 0.1),
                        child: const Icon(Icons.person_outline, color: Colors.purple, size: 20),
                      ),
                      title: const Text('Agent Profile & Status', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      subtitle: const Text('View your telecaller ID and system permissions', style: TextStyle(fontSize: 12)),
                      trailing: const Icon(Icons.chevron_right, size: 20),
                      contentPadding: EdgeInsets.zero,
                      onTap: widget.onOpenProfile,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(
    BuildContext context, {
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500),
                  ),
                  Icon(icon, size: 20, color: color),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// PROFILE TAB (Logged-In User Credentials & Device Status)
// -----------------------------------------------------------------------------
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final displayName = ConfigService.userDisplayName;
    final email = ConfigService.userEmail.isNotEmpty ? ConfigService.userEmail : 'Active Agent Session';
    final role = ConfigService.userRole;
    final userId = ConfigService.userId;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          const SizedBox(height: 20),
          CircleAvatar(
            radius: 40,
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: Text(
              displayName.toString().isNotEmpty ? displayName.toString()[0].toUpperCase() : 'T',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            displayName.toString(),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            email.toString(),
            style: const TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Role: $role • ID: $userId',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.phone_android),
                  title: const Text('Call Permissions Status'),
                  subtitle: const Text('Ensure call logging permissions are active'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final granted = await CallTrackingService.requestPermissions();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            granted
                                ? 'All call tracking permissions are active!'
                                : 'Permissions need to be granted in system settings.',
                          ),
                        ),
                      );
                    }
                  },
                ),
                const Divider(height: 1),
                const ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('App Version'),
                  subtitle: Text('CallNow 5.0 (Telecaller Desk Edition)'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: const Text('Sign Out', style: TextStyle(color: Colors.red)),
                  subtitle: const Text('Log out of this telecalling session'),
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
        ],
      ),
    );
  }
}
