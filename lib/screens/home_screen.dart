import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:callnow_new/model/followup_model.dart';
import 'package:callnow_new/services/api_service.dart';
import 'package:callnow_new/services/call_tracking_service.dart';
import 'package:callnow_new/services/config_service.dart';
import 'package:callnow_new/services/followup_service.dart';
import 'package:callnow_new/services/notification_service.dart';
import 'package:callnow_new/services/permission_service.dart';
import 'package:callnow_new/services/engagement_service.dart';
import 'package:callnow_new/services/pending_call_recovery_service.dart';
import 'package:callnow_new/widgets/callback_alert_dialog.dart';
import 'package:callnow_new/widgets/incoming_call_action_dialog.dart';
import 'package:callnow_new/screens/calling_desk_screen.dart';
import 'package:callnow_new/screens/call_reports_screen.dart';
import 'package:callnow_new/screens/leads_screen.dart';
import 'package:callnow_new/screens/followup_screen.dart';
import 'package:callnow_new/screens/settings_screen.dart';
import 'package:callnow_new/screens/profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  StreamSubscription<String?>? _notificationSub;

  /// Timer that fires exactly at 00:00 to auto-logout the user.
  Timer? _midnightLogoutTimer;

  /// The calendar date when the session started. Used to detect day-change on resume.
  late DateTime _sessionStartDate;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sessionStartDate = DateTime.now();
    _initCallTracker();
    _scheduleMidnightLogout();
    // Listen to push notification clicks
    _notificationSub = NotificationService.onNotificationTap.listen((payload) {
      if (payload != null && mounted) {
        _handleNotificationTap(payload);
      }
    });
    // Initial due-callback check after first frame (event-driven, no polling)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkDueCallbacks();
      _checkPendingPostCallPrompt();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissionsOnResume();
      _checkDueCallbacks();
      _checkDateChangeLogout();
      _checkPendingPostCallPrompt();
    }
  }

  bool _isCheckingPostCall = false;

  Future<void> _checkPendingPostCallPrompt() async {
    if (_isCheckingPostCall || !mounted) return;
    _isCheckingPostCall = true;

    try {
      // 1. Check if a pending post call was stored by background phone state listener
      Map<String, dynamic>? pending = await CallTrackingService.getPendingPostCall();

      // 2. If no background pending, inspect native Android call logs for any recent connected incoming call (within last 15 min)
      if (pending == null) {
        final fifteenMinsAgo = DateTime.now().millisecondsSinceEpoch - (15 * 60 * 1000);
        final recentLogs = await CallTrackingService.getRecentCallLogs(limit: 5, afterTimestamp: fifteenMinsAgo);
        for (final log in recentLogs) {
          final isIncoming = log['isIncoming'] == true || log['type'] == 1;
          final duration = (log['duration'] as num?)?.toInt() ?? 0;
          final timestamp = (log['timestamp'] as num?)?.toInt() ?? 0;
          final number = (log['number'] ?? log['cleanNumber'] ?? '').toString();

          if (isIncoming && duration > 0 && number.isNotEmpty) {
            final key = '${number}_$timestamp';
            final alreadyProcessed = await CallTrackingService.isCallProcessed(key);
            if (!alreadyProcessed) {
              await CallTrackingService.markCallProcessed(key);
              pending = {
                'number': number,
                'duration': duration,
                'direction': 'INCOMING',
                'timestamp': timestamp,
              };
              break;
            }
          }
        }
      }

      if (pending != null && mounted) {
        final number = pending['number']?.toString() ?? '';
        final duration = (pending['duration'] as num?)?.toInt() ?? 0;
        final direction = pending['direction']?.toString() ?? 'INCOMING';

        if (number.isNotEmpty) {
          // Lookup contact info from CRM
          final contactData = await ApiService.lookupContact(number);
          if (mounted) {
            await IncomingCallActionDialog.show(
              context,
              phoneNumber: number,
              durationSeconds: duration,
              direction: direction,
              contactData: contactData,
            );
          }
        }
      }
    } catch (e) {
      debugPrint('[HomeScreen] _checkPendingPostCallPrompt error: $e');
    } finally {
      _isCheckingPostCall = false;
    }
  }

  Future<void> _checkPermissionsOnResume() async {
    final hasPerms = await PermissionService.hasAllPermissions();
    if (!hasPerms && mounted) {
      Navigator.pushReplacementNamed(context, '/permissions');
    }
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
    WidgetsBinding.instance.removeObserver(this);
    _notificationSub?.cancel();
    _midnightLogoutTimer?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Midnight auto-logout
  // ---------------------------------------------------------------------------

  /// Schedules a one-shot [Timer] that fires at the next 00:00:00 local time.
  /// When it fires the user is silently logged out and sent to /login.
  void _scheduleMidnightLogout() {
    _midnightLogoutTimer?.cancel();
    final now = DateTime.now();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1); // 00:00 tomorrow
    final delay = nextMidnight.difference(now);
    _midnightLogoutTimer = Timer(delay, _performMidnightLogout);
    debugPrint('[HomeScreen] Midnight logout scheduled in ${delay.inMinutes} min '
        '(at $nextMidnight)');
  }

  /// Called either by the timer (exact midnight) or on app-resume if the date
  /// has already rolled over (phone left overnight).
  Future<void> _performMidnightLogout() async {
    if (!mounted) return;
    debugPrint('[HomeScreen] Midnight reached — auto-logging out.');
    await ApiService.logout();
    if (mounted) {
      // Show a brief banner before navigating so the user knows why they were logged out.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.lock_clock_outlined, color: Colors.white, size: 18),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Session expired at midnight. Please log in again.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          backgroundColor: Color(0xFF1E40AF),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 3),
        ),
      );
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    }
  }

  /// Handles the edge-case where the app was backgrounded across midnight.
  /// Called every time the app is resumed from the background.
  void _checkDateChangeLogout() {
    final today = DateTime.now();
    if (today.day != _sessionStartDate.day ||
        today.month != _sessionStartDate.month ||
        today.year != _sessionStartDate.year) {
      debugPrint('[HomeScreen] Date changed since session start — triggering midnight logout.');
      _performMidnightLogout();
    }
  }

  Future<void> _initCallTracker() async {
    final hasPerms = await PermissionService.hasAllPermissions();
    if (!hasPerms) {
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/permissions');
      }
      return;
    }
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
        return 'CallNow - Settings';
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
      CallingDeskScreen(
        onOpenReports: () => _onItemTapped(3),
      ),
      CallReportsScreen(
        key: _reportsKey,
        initialTabIndex: _reportsInitialTab,
        initialStatus: _reportsInitialStatus,
        initialTimingTier: _reportsInitialTimingTier,
        initialPeriod: _reportsInitialPeriod,
      ),
      const SettingsScreen(),
    ];

    final colorScheme = Theme.of(context).colorScheme;

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
          // User Profile Avatar (tap to open Profile Screen)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2.0),
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProfileScreen()),
                );
              },
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                padding: const EdgeInsets.all(4.0),
                child: ValueListenableBuilder<int>(
                  valueListenable: ConfigService.profileNotifier,
                  builder: (context, _, child) {
                    final avatarProvider = ConfigService.userAvatarImageProvider;
                    final name = ConfigService.userDisplayName;
                    return CircleAvatar(
                      radius: 14,
                      backgroundColor: colorScheme.primaryContainer,
                      backgroundImage: avatarProvider,
                      child: avatarProvider == null
                          ? Text(
                              name.isNotEmpty ? name[0].toUpperCase() : 'U',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onPrimaryContainer,
                              ),
                            )
                          : null,
                    );
                  },
                ),
              ),
            ),
          ),
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
                InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ProfileScreen()),
                    );
                  },
                  borderRadius: BorderRadius.circular(26),
                  child: ValueListenableBuilder<int>(
                    valueListenable: ConfigService.profileNotifier,
                    builder: (context, _, child) {
                      final avatarProvider = ConfigService.userAvatarImageProvider;
                      return CircleAvatar(
                        radius: 24,
                        backgroundColor: colorScheme.primary.withValues(alpha: 0.15),
                        child: CircleAvatar(
                          radius: 22,
                          backgroundColor: colorScheme.primary,
                          backgroundImage: avatarProvider,
                          child: avatarProvider == null
                              ? Text(
                                  userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                    color: Colors.white,
                                  ),
                                )
                              : null,
                        ),
                      );
                    },
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

            // Calling Desk Shortcut Card with Today's Goal Progress Bar
            ListenableBuilder(
              listenable: EngagementService.instance,
              builder: (context, _) {
                final eng = EngagementService.instance.state;
                final effectiveTarget = ConfigService.dailyCallingLimit > 0
                    ? ConfigService.dailyCallingLimit
                    : (eng.targetToday > 0 ? eng.targetToday : 250);
                final connectedToday = eng.connectedToday;
                final progress = effectiveTarget > 0
                    ? (connectedToday / effectiveTarget).clamp(0.0, 1.0)
                    : 0.0;
                final isTargetMet = connectedToday >= effectiveTarget;

                return Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  clipBehavior: Clip.antiAlias,
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
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
                            Row(
                              children: [
                                const Text(
                                  'Calling Desk',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    eng.levelTitle,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                if (eng.streakDays > 0) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.withValues(alpha: 0.25),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.local_fire_department, color: Colors.amber, size: 14),
                                        const SizedBox(width: 2),
                                        Text(
                                          '${eng.streakDays}d',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '${eng.totalXp} XP',
                                    style: const TextStyle(
                                      color: Colors.amberAccent,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        // Today's Goal Progress Bar
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "Today's Goal: $connectedToday / $effectiveTarget Connected",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              '${(progress * 100).toInt()}%',
                              style: TextStyle(
                                color: isTargetMet ? Colors.greenAccent : Colors.amberAccent,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 8,
                            backgroundColor: Colors.white24,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              isTargetMet ? Colors.greenAccent : Colors.amberAccent,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FutureBuilder<bool>(
                            future: PendingCallRecoveryService.hasPendingCall(),
                            builder: (context, snapshot) {
                              final hasPending = snapshot.data == true;
                              return FilledButton.icon(
                                onPressed: widget.onStartCalling,
                                icon: Icon(
                                  hasPending ? Icons.history_toggle_off_rounded : Icons.phone_in_talk,
                                  size: 20,
                                ),
                                label: Text(
                                  hasPending ? 'Resume Pending Call Outcome' : 'Start Calling Session',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                                style: FilledButton.styleFrom(
                                  backgroundColor: hasPending ? const Color(0xFFFEF3C7) : Colors.white,
                                  foregroundColor: hasPending ? const Color(0xFFB45309) : const Color(0xFF1E3C72),
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
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
            const SizedBox(height: 16),

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
