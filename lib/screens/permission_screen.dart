import 'package:flutter/material.dart';
import 'package:callnow_new/services/permission_service.dart';
import 'package:callnow_new/services/config_service.dart';
import 'package:callnow_new/services/call_tracking_service.dart';

class PermissionScreen extends StatefulWidget {
  const PermissionScreen({super.key});

  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen>
    with WidgetsBindingObserver {
  PermissionStatusReport? _report;
  bool _isLoading = true;
  bool _hasRequestedOnce = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // User may have toggled permissions in Android Settings and returned
      _checkPermissions();
    }
  }

  Future<void> _checkPermissions() async {
    setState(() => _isLoading = true);
    final report = await PermissionService.checkAllPermissions();
    if (!mounted) return;

    setState(() {
      _report = report;
      _isLoading = false;
    });

    if (report.allGranted) {
      // Re-initialize call tracker with newly granted permissions
      await CallTrackingService.initialize();
      if (!mounted) return;

      // Navigate to destination
      _proceedToApp();
    }
  }

  void _proceedToApp() {
    if (ConfigService.isLoggedIn) {
      Navigator.pushReplacementNamed(context, '/home');
    } else {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  Future<void> _requestPermissions() async {
    setState(() {
      _isLoading = true;
      _hasRequestedOnce = true;
    });

    final updated = await PermissionService.requestAllPermissions();
    if (!mounted) return;

    setState(() {
      _report = updated;
      _isLoading = false;
    });

    if (updated.allGranted) {
      await CallTrackingService.initialize();
      if (!mounted) return;
      _proceedToApp();
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    final allGranted = report?.allGranted ?? false;
    final grantedCount = report?.grantedCount ?? 0;
    final totalCount = report?.totalCount ?? 4;

    return PopScope(
      canPop: false, // Disallow bypassing permission gate via back button
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: const Text('Required Permissions'),
          automaticallyImplyLeading: false,
          elevation: 0,
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF0F172A),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Check Again',
              onPressed: _isLoading ? null : _checkPermissions,
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header Card
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF1E3A8A), Color(0xFF2563EB)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF2563EB).withValues(alpha: 0.25),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.verified_user_rounded,
                                size: 36,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Permissions Setup',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'CallNow requires the following telecalling permissions to log call durations and alert you for scheduled callbacks.',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.white.withValues(alpha: 0.9),
                                height: 1.4,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 14),
                            // Progress Pill
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '$grantedCount of $totalCount Permissions Granted',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Missing permissions warning card if requested once and still not granted
                      if (_hasRequestedOnce && !allGranted)
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFF59E0B)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.info_outline, color: Color(0xFFB45309), size: 22),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Permissions need enabling in Settings',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: Color(0xFF92400E),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    const Text(
                                      'If Android did not show a permission popup, please tap "Open Device Settings" below to toggle the remaining permissions manually.',
                                      style: TextStyle(fontSize: 12, color: Color(0xFF78350F), height: 1.3),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                      // READ_CALL_LOG restricted-permission degradation notice
                      if (report != null && report.isCallLogRestricted && allGranted == false)
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3E8FF),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF8B5CF6)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.error_outline, color: Color(0xFF7C3AED), size: 22),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Call Log access restricted',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: Color(0xFF7C3AED),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'READ_CALL_LOG is a restricted permission on Android 10+. '
                                      'Call duration logging will be estimated until the permission is granted via '
                                      'Play Store approval or device settings.',
                                      style: TextStyle(fontSize: 12, color: Color(0xFF6B21A8), height: 1.3),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                      // 1. Phone State Permission Tile
                      _buildPermissionTile(
                        icon: Icons.phone_in_talk_rounded,
                        title: 'Phone Call Detection',
                        subtitle: 'Monitors ringing, answered, and disconnected states to trigger call logging.',
                        isGranted: report?.phoneState ?? false,
                      ),
                      const SizedBox(height: 12),

                      // 2. Call Log Permission Tile
                      _buildPermissionTile(
                        icon: Icons.history_rounded,
                        title: 'Call Log & Talk Time',
                        subtitle: 'Reads system call history to accurately record conversation duration in CRM.',
                        isGranted: report?.callLog ?? false,
                      ),
                      const SizedBox(height: 12),

                      // 3. Direct Calling Permission Tile
                      _buildPermissionTile(
                        icon: Icons.call_made_rounded,
                        title: 'One-Tap Direct Calling',
                        subtitle: 'Enables placing customer calls directly from Calling Desk without dialing manually.',
                        isGranted: report?.callPhone ?? false,
                      ),
                      const SizedBox(height: 12),

                      // 4. Notifications Permission Tile
                      _buildPermissionTile(
                        icon: Icons.notifications_active_rounded,
                        title: 'Callback Notifications',
                        subtitle: 'Alerts you with heads-up push notifications when client callbacks are due.',
                        isGranted: report?.notifications ?? false,
                      ),
                      const SizedBox(height: 24),

                      // Action Buttons
                      if (!allGranted) ...[
                        FilledButton.icon(
                          onPressed: _isLoading ? null : _requestPermissions,
                          icon: const Icon(Icons.check_circle_outline),
                          label: const Text('Grant All Permissions'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                        ),
                        if (_hasRequestedOnce) ...[
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: _isLoading ? null : PermissionService.openDeviceSettings,
                            icon: const Icon(Icons.settings_outlined),
                            label: const Text('Open Device Settings'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF2563EB),
                              side: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ] else ...[
                        FilledButton.icon(
                          onPressed: _proceedToApp,
                          icon: const Icon(Icons.arrow_forward_rounded),
                          label: const Text('Continue to App'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF059669),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildPermissionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isGranted,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isGranted ? const Color(0xFF86EFAC) : const Color(0xFFE2E8F0),
          width: isGranted ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isGranted
                  ? const Color(0xFFDCFCE7)
                  : const Color(0xFFF1F5F9),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 20,
              color: isGranted ? const Color(0xFF16A34A) : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isGranted
                            ? const Color(0xFFDCFCE7)
                            : const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isGranted ? Icons.check_circle : Icons.error_outline,
                            size: 12,
                            color: isGranted
                                ? const Color(0xFF15803D)
                                : const Color(0xFFB45309),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isGranted ? 'Granted' : 'Required',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isGranted
                                  ? const Color(0xFF15803D)
                                  : const Color(0xFFB45309),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

