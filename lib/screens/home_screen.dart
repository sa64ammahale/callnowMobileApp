import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:callnow_new/model/followup_model.dart';
import 'package:callnow_new/services/api_service.dart';
import 'package:callnow_new/services/call_tracking_service.dart';
import 'package:callnow_new/services/config_service.dart';
import 'package:callnow_new/services/followup_service.dart';
import 'package:callnow_new/services/notification_service.dart';
import 'package:callnow_new/widgets/callback_alert_dialog.dart';
import 'package:callnow_new/screens/calling_desk_screen.dart';
import 'package:callnow_new/screens/call_reports_screen.dart';
import 'package:callnow_new/screens/leads_screen.dart';
import 'package:callnow_new/screens/followup_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  Timer? _callbackWatchdogTimer;
  StreamSubscription<String?>? _notificationSub;

  @override
  void initState() {
    super.initState();
    _initCallTracker();
    _initCallbackWatchdog();
  }

  void _initCallbackWatchdog() {
    // Check every 25 seconds for callbacks due now
    _callbackWatchdogTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      _checkDueCallbacks();
    });

    // Listen to push notification clicks
    _notificationSub = NotificationService.onNotificationTap.listen((payload) {
      if (payload != null && mounted) {
        _handleNotificationTap(payload);
      }
    });

    // Initial check after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkDueCallbacks();
    });
  }

  void _checkDueCallbacks() {
    if (!mounted) return;
    final dueList = FollowupService.instance.getDueNowUnprompted();
    if (dueList.isNotEmpty) {
      final first = dueList.first;
      CallbackAlertDialog.show(context, first);
    }
  }

  void _handleNotificationTap(String payload) {
    try {
      final data = jsonDecode(payload);
      final id = data['id']?.toString();
      if (id != null) {
        final followup = FollowupService.instance.followups.firstWhere(
          (f) => f.id == id,
          orElse: () => FollowupModel.fromJson(data),
        );
        CallbackAlertDialog.show(context, followup);
      }
    } catch (_) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const FollowUpScreen()),
      );
    }
  }

  @override
  void dispose() {
    _callbackWatchdogTimer?.cancel();
    _notificationSub?.cancel();
    super.dispose();
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

  int _reportsInitialTab = 0;
  String? _reportsInitialStatus;
  String? _reportsInitialTimingTier;
  String? _reportsInitialPeriod;
  final GlobalKey<CallReportsScreenState> _reportsKey = GlobalKey<CallReportsScreenState>();

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void _openReportsWithFilter({
    int tabIndex = 1,
    String? status,
    String? timingTier,
    String? period,
  }) {
    setState(() {
      _reportsInitialTab = tabIndex;
      _reportsInitialStatus = status;
      _reportsInitialTimingTier = timingTier;
      _reportsInitialPeriod = period ?? 'today';
      _selectedIndex = 3;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reportsKey.currentState?.applyExternalFilter(
        tabIndex: tabIndex,
        status: status,
        timingTier: timingTier,
        period: period ?? 'today',
      );
    });
  }

  String get _currentTitle {
    switch (_selectedIndex) {
      case 0:
        return 'CallNow - Dashboard';
      case 1:
        return 'CallNow - Leads Queue';
      case 2:
        return 'CallNow - Calling Desk';
      case 3:
        return 'CallNow - Call Reports';
      case 4:
        return 'CallNow - Profile';
      default:
        return 'CallNow';
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      DashboardPage(
        onStartCalling: () => _onItemTapped(2),
        onOpenLeads: () => _onItemTapped(1),
        onOpenReports: () => _onItemTapped(3),
        onOpenReportsFiltered: _openReportsWithFilter,
        onOpenProfile: () => _onItemTapped(4),
      ),
      LeadsScreen(
        onOpenCallingDesk: () => _onItemTapped(2),
      ),
      const CallingDeskScreen(),
      CallReportsScreen(
        key: _reportsKey,
        initialTabIndex: _reportsInitialTab,
        initialStatus: _reportsInitialStatus,
        initialTimingTier: _reportsInitialTimingTier,
        initialPeriod: _reportsInitialPeriod,
      ),
      const ProfilePage(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.phone_in_talk, size: 22),
            const SizedBox(width: 8),
            Text(
              _currentTitle,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        actions: [
          ListenableBuilder(
            listenable: FollowupService.instance,
            builder: (context, _) {
              final pendingCount = FollowupService.instance.getPending().length;
              return IconButton(
                icon: Badge(
                  isLabelVisible: pendingCount > 0,
                  label: Text('$pendingCount'),
                  backgroundColor: Colors.amber.shade900,
                  child: const Icon(Icons.alarm_on_outlined),
                ),
                tooltip: 'Client Follow-ups ($pendingCount)',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const FollowUpScreen()),
                  );
                },
              );
            },
          ),
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
            icon: Icon(Icons.contact_phone_outlined),
            selectedIcon: Icon(Icons.contact_phone),
            label: 'Leads',
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
  final VoidCallback? onOpenLeads;
  final VoidCallback onOpenReports;
  final Function({int tabIndex, String? status, String? timingTier, String? period})? onOpenReportsFiltered;
  final VoidCallback onOpenProfile;

  const DashboardPage({
    super.key,
    required this.onStartCalling,
    this.onOpenLeads,
    required this.onOpenReports,
    this.onOpenReportsFiltered,
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

    final rawStatusBreakdown = _summary?['status_breakdown'];
    final Map<String, dynamic> statusBreakdown = rawStatusBreakdown is Map
        ? Map<String, dynamic>.from(rawStatusBreakdown)
        : {};
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
                  onPressed: () {
                    if (widget.onOpenReportsFiltered != null) {
                      widget.onOpenReportsFiltered!(tabIndex: 0, period: 'today');
                    } else {
                      widget.onOpenReports();
                    }
                  },
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
                    onTap: () {
                      if (widget.onOpenReportsFiltered != null) {
                        widget.onOpenReportsFiltered!(tabIndex: 1, status: 'all', period: 'today');
                      } else {
                        widget.onOpenReports();
                      }
                    },
                  ),
                  _buildStatCard(
                    context,
                    title: 'Connected Calls',
                    value: connectedCalls.toString(),
                    subtitle: '$connectionRate% picked up',
                    icon: Icons.phone_in_talk,
                    color: Colors.green,
                    onTap: () {
                      if (widget.onOpenReportsFiltered != null) {
                        widget.onOpenReportsFiltered!(tabIndex: 1, timingTier: 'conversation', period: 'today');
                      } else {
                        widget.onOpenReports();
                      }
                    },
                  ),
                  _buildStatCard(
                    context,
                    title: "Today's Talk Time",
                    value: talkTimeFormatted,
                    subtitle: 'Cumulative spoken time',
                    icon: Icons.timer,
                    color: Colors.purple,
                    onTap: () {
                      if (widget.onOpenReportsFiltered != null) {
                        widget.onOpenReportsFiltered!(tabIndex: 1, timingTier: 'conversation', period: 'today');
                      } else {
                        widget.onOpenReports();
                      }
                    },
                  ),
                  ListenableBuilder(
                    listenable: FollowupService.instance,
                    builder: (context, _) {
                      final localPending = FollowupService.instance.getPending().length;
                      final displayCount = localPending > 0 ? localPending : followupsCount;
                      return _buildStatCard(
                        context,
                        title: 'Follow-ups Pending',
                        value: displayCount.toString(),
                        subtitle: 'Scheduled callbacks',
                        icon: Icons.event_repeat,
                        color: Colors.amber.shade900,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const FollowUpScreen()),
                          );
                        },
                      );
                    },
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
                    if (widget.onOpenLeads != null) ...[
                      ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.indigo.withValues(alpha: 0.1),
                          child: const Icon(Icons.contact_phone, color: Colors.indigo, size: 20),
                        ),
                        title: const Text('Browse Assigned Leads', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        subtitle: const Text('View and search upcoming contacts in queue', style: TextStyle(fontSize: 12)),
                        trailing: const Icon(Icons.chevron_right, size: 20),
                        contentPadding: EdgeInsets.zero,
                        onTap: widget.onOpenLeads,
                      ),
                      const Divider(height: 1),
                    ],
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
                        backgroundColor: Colors.amber.withValues(alpha: 0.1),
                        child: const Icon(Icons.alarm_on, color: Colors.amber, size: 20),
                      ),
                      title: const Text('Client Follow-Up Pipeline', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      subtitle: const Text('Manage scheduled callbacks, snoozed and overdue calls', style: TextStyle(fontSize: 12)),
                      trailing: const Icon(Icons.chevron_right, size: 20),
                      contentPadding: EdgeInsets.zero,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const FollowUpScreen()),
                        );
                      },
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
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _vibrateOnEnd = true;
  bool _keepScreenOn = true;
  bool _quickWhatsAppPrompt = true;

  Future<void> _refreshProfile() async {
    try {
      await ApiService.getProfile();
    } catch (_) {}
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final displayName = ConfigService.userDisplayName;
    final email = ConfigService.userEmail.isNotEmpty ? ConfigService.userEmail : 'Active Agent Session';
    final role = ConfigService.userRole;
    final userId = ConfigService.userId;

    return RefreshIndicator(
      onRefresh: _refreshProfile,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const SizedBox(height: 12),
            CircleAvatar(
              radius: 38,
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
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
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
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, color: Colors.green, size: 8),
                      SizedBox(width: 4),
                      Text(
                        'Online',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Calling Preferences
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Calling Preferences',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              elevation: 1.5,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Vibrate on Call End', style: TextStyle(fontSize: 14)),
                    subtitle: const Text('Haptic feedback when phone call disconnects', style: TextStyle(fontSize: 12)),
                    value: _vibrateOnEnd,
                    onChanged: (val) => setState(() => _vibrateOnEnd = val),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: const Text('Keep Screen Awake', style: TextStyle(fontSize: 14)),
                    subtitle: const Text('Prevent display sleep during calling desk session', style: TextStyle(fontSize: 12)),
                    value: _keepScreenOn,
                    onChanged: (val) => setState(() => _keepScreenOn = val),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: const Text('Quick WhatsApp Intro', style: TextStyle(fontSize: 14)),
                    subtitle: const Text('Pre-fill greeting when launching WhatsApp chat', style: TextStyle(fontSize: 12)),
                    value: _quickWhatsAppPrompt,
                    onChanged: (val) => setState(() => _quickWhatsAppPrompt = val),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Device & System Settings
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'System & Permissions',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.phone_android),
                    title: const Text('Call Tracking Permissions'),
                    subtitle: const Text('Verify READ_PHONE_STATE & READ_CALL_LOG'),
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
                    title: const Text('Sign Out', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
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
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
