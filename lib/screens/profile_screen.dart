import 'dart:async';
import 'package:flutter/material.dart';
import 'package:callnow_new/services/api_service.dart';
import 'package:callnow_new/services/config_service.dart';
import 'package:callnow_new/services/followup_service.dart';
import 'package:callnow_new/model/user_profile.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isLoading = true;
  bool _isRefreshing = false;
  Map<String, dynamic> _profileData = {};

  @override
  void initState() {
    super.initState();
    _profileData = ConfigService.userData ?? {};
    _isLoading = _profileData.isEmpty;
    _fetchProfile(isInitial: true);
  }

  Future<void> _fetchProfile({bool isInitial = false}) async {
    final cached = ConfigService.userData ?? {};
    if (isInitial) {
      setState(() {
        _profileData = cached;
        _isLoading = cached.isEmpty;
        _isRefreshing = cached.isNotEmpty;
      });
    } else {
      setState(() => _isRefreshing = true);
    }

    try {
      final fetched = await ApiService.getProfile();
      if (mounted) {
        setState(() {
          _profileData = fetched;
          _isLoading = false;
          _isRefreshing = false;
        });
        if (!isInitial) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Profile details updated from server.'),
              duration: Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
          if (_profileData.isEmpty) {
            _profileData = ConfigService.userData ?? {};
          }
        });
        if (!isInitial) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to sync profile: $e'),
              backgroundColor: Colors.red.shade700,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }



  UserProfile get _userProfile => UserProfile.fromJson(
        _profileData.isNotEmpty ? _profileData : (ConfigService.userData ?? {}),
      );

  String _resolveJoinDate() => _userProfile.joinDate.isNotEmpty
      ? (_userProfile.joinDate.length >= 10
          ? _userProfile.joinDate.substring(0, 10)
          : _userProfile.joinDate)
      : 'Active Member';

  void _showEditProfileDialog() {
    final profile = _userProfile;
    final nameCtrl = TextEditingController(text: profile.name);
    final companyCtrl = TextEditingController(text: profile.companyName);
    final email = profile.displayEmail;
    final phone = profile.displayMobile;
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Edit Profile Details',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              
              // Full Name (Editable)
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Full Name',
                  prefixIcon: Icon(Icons.person_outline),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              // Company (Editable)
              TextField(
                controller: companyCtrl,
                decoration: const InputDecoration(
                  labelText: 'Company / Organization',
                  prefixIcon: Icon(Icons.business_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              // Registered Email (RESTRICTED / READ-ONLY)
              TextField(
                controller: TextEditingController(text: email),
                enabled: false,
                decoration: InputDecoration(
                  labelText: 'Registered Email',
                  prefixIcon: const Icon(Icons.email_outlined),
                  suffixIcon: const Tooltip(
                    message: 'Email cannot be changed from mobile app',
                    child: Icon(Icons.lock_outline, size: 18, color: Colors.grey),
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  border: const OutlineInputBorder(),
                  helperText: 'Locked • Contact CRM Administrator to change email',
                ),
              ),
              const SizedBox(height: 12),
              // Registered Mobile (RESTRICTED / READ-ONLY)
              TextField(
                controller: TextEditingController(text: phone),
                enabled: false,
                decoration: InputDecoration(
                  labelText: 'Registered Mobile Number',
                  prefixIcon: const Icon(Icons.phone_outlined),
                  suffixIcon: const Tooltip(
                    message: 'Mobile number cannot be changed from mobile app',
                    child: Icon(Icons.lock_outline, size: 18, color: Colors.grey),
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  border: const OutlineInputBorder(),
                  helperText: 'Locked • Contact CRM Administrator to change phone',
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: isSaving
                    ? null
                    : () async {
                        setModalState(() => isSaving = true);
                        try {
                          final updated = await ApiService.updateProfile(
                            name: nameCtrl.text,
                            companyName: companyCtrl.text,
                          );
                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                          }
                          if (mounted) {
                            setState(() => _profileData = updated);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Profile updated successfully!')),
                            );
                          }
                        } catch (e) {
                          if (ctx.mounted) {
                            setModalState(() => isSaving = false);
                          }
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')), backgroundColor: Colors.red),
                            );
                          }
                        }
                      },
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Save Changes'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showChangePasswordDialog() {
    final currentPassCtrl = TextEditingController();
    final newPassCtrl = TextEditingController();
    final confirmPassCtrl = TextEditingController();
    bool obscureCurrent = true;
    bool obscureNew = true;
    bool obscureConfirm = true;
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Change Password',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Enter your current password and your new desired password.',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: currentPassCtrl,
                obscureText: obscureCurrent,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: 'Current Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(obscureCurrent ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
                    onPressed: () => setModalState(() => obscureCurrent = !obscureCurrent),
                  ),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: newPassCtrl,
                obscureText: obscureNew,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: 'New Password (Min 6 chars)',
                  prefixIcon: const Icon(Icons.lock_reset_rounded),
                  suffixIcon: IconButton(
                    icon: Icon(obscureNew ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
                    onPressed: () => setModalState(() => obscureNew = !obscureNew),
                  ),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmPassCtrl,
                obscureText: obscureConfirm,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: 'Confirm New Password',
                  prefixIcon: const Icon(Icons.lock_reset_rounded),
                  suffixIcon: IconButton(
                    icon: Icon(obscureConfirm ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
                    onPressed: () => setModalState(() => obscureConfirm = !obscureConfirm),
                  ),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: isSaving
                    ? null
                    : () async {
                        if (currentPassCtrl.text.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Please enter current password.')),
                          );
                          return;
                        }
                        if (newPassCtrl.text.length < 6) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('New password must be at least 6 characters.')),
                          );
                          return;
                        }
                        if (newPassCtrl.text != confirmPassCtrl.text) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('New passwords do not match.')),
                          );
                          return;
                        }

                        setModalState(() => isSaving = true);
                        try {
                          await ApiService.changePassword(
                            currentPassword: currentPassCtrl.text,
                            newPassword: newPassCtrl.text,
                            confirmPassword: confirmPassCtrl.text,
                          );
                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                          }
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Password changed successfully!'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        } catch (e) {
                          if (ctx.mounted) {
                            setModalState(() => isSaving = false);
                          }
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(e.toString().replaceFirst('Exception: ', '')),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Update Password'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPasswordResetDialog() {
    final email = _userProfile.email;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PasswordResetModal(
        initialEmail: email.contains('@') ? email : '',
      ),
    );
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
          'Are you sure you want to log out of your telecaller session on this device?',
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
    final profile = _userProfile;
    final displayName = profile.name.isNotEmpty ? profile.name : ConfigService.userDisplayName;
    final email = profile.displayEmail;
    final phone = profile.displayMobile;
    final username = profile.username;
    final role = profile.role;
    final userId = profile.displayId;
    final department = profile.displayDepartment;
    final joinDate = _resolveJoinDate();
    final pendingFollowups = FollowupService.instance.getPending().length;

    final isEmailMissing = !profile.hasEmail;
    final isPhoneMissing = !profile.hasMobile;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Agent Profile', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit Profile',
            onPressed: _showEditProfileDialog,
          ),
          IconButton(
            icon: _isRefreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.sync_rounded),
            tooltip: 'Sync from Server',
            onPressed: _isRefreshing ? null : () => _fetchProfile(isInitial: false),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Fetching latest profile from server...', style: TextStyle(color: Color(0xFF64748B))),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: () => _fetchProfile(isInitial: false),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. Hero Profile Header Card
                    Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF1E3A8A), Color(0xFF2563EB)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF2563EB).withValues(alpha: 0.25),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 40,
                            backgroundColor: Colors.white.withValues(alpha: 0.25),
                            child: CircleAvatar(
                              radius: 36,
                              backgroundColor: Colors.white,
                              backgroundImage: (profile.profilePhotoUrl != null && profile.profilePhotoUrl!.isNotEmpty)
                                  ? NetworkImage(profile.profilePhotoUrl!)
                                  : null,
                              child: (profile.profilePhotoUrl == null || profile.profilePhotoUrl!.isEmpty)
                                  ? Text(
                                      displayName.trim().isNotEmpty ? displayName.trim()[0].toUpperCase() : 'A',
                                      style: const TextStyle(
                                        fontSize: 32,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF1E3A8A),
                                      ),
                                    )
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            displayName,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            !isEmailMissing ? email : '@$username',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                                ),
                                child: Text(
                                  role,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFF34D399)),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.circle, color: Color(0xFF34D399), size: 7),
                                    SizedBox(width: 4),
                                    Text(
                                      'Active Session',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
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
                    const SizedBox(height: 16),

                    // 2. Metrics Summary Strip
                    Row(
                      children: [
                        Expanded(
                          child: _buildMetricTile(
                            icon: Icons.tag_rounded,
                            label: 'Agent ID',
                            value: userId,
                            color: const Color(0xFF2563EB),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildMetricTile(
                            icon: Icons.alarm_on_rounded,
                            label: 'Callbacks',
                            value: '$pendingFollowups Due',
                            color: const Color(0xFFD97706),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildMetricTile(
                            icon: Icons.shield_outlined,
                            label: 'Call Tracker',
                            value: 'Active',
                            color: const Color(0xFF059669),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // 3. Detailed Agent Information Card
                    Card(
                      elevation: 0.5,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.badge_outlined, size: 18, color: Color(0xFF2563EB)),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    'Server Profile Details',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: _showEditProfileDialog,
                                  icon: const Icon(Icons.edit_outlined, size: 14),
                                  label: const Text('Edit Details', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                  style: TextButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            _buildInfoRow(
                              icon: Icons.person_outline,
                              label: 'Full Name',
                              value: displayName,
                            ),
                            const Divider(height: 18, color: Color(0xFFF1F5F9)),
                            _buildInfoRow(
                              icon: Icons.alternate_email_rounded,
                              label: 'Username',
                              value: username,
                            ),
                            const Divider(height: 18, color: Color(0xFFF1F5F9)),
                            _buildInfoRow(
                              icon: Icons.email_outlined,
                              label: 'Registered Email',
                              value: email,
                              isWarning: isEmailMissing,
                            ),
                            const Divider(height: 18, color: Color(0xFFF1F5F9)),
                            _buildInfoRow(
                              icon: Icons.phone_android_rounded,
                              label: 'Registered Phone',
                              value: phone,
                              isWarning: isPhoneMissing,
                            ),
                            const Divider(height: 18, color: Color(0xFFF1F5F9)),
                            _buildInfoRow(
                              icon: Icons.corporate_fare_rounded,
                              label: 'Department',
                              value: department,
                            ),
                            const Divider(height: 18, color: Color(0xFFF1F5F9)),
                            _buildInfoRow(
                              icon: Icons.calendar_today_outlined,
                              label: 'Member Since',
                              value: joinDate,
                            ),
                            const Divider(height: 18, color: Color(0xFFF1F5F9)),
                            _buildInfoRow(
                              icon: Icons.business_rounded,
                              label: 'Organization',
                              value: profile.companyName.contains('CallNow')
                                  ? profile.companyName
                                  : '${profile.companyName} • CallNow CRM',
                            ),

                            // Note when email or phone is not populated in CRM database
                            if (isEmailMissing || isPhoneMissing) ...[
                              const SizedBox(height: 14),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFFBEB),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFFFDE68A)),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFFD97706)),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        isEmailMissing && isPhoneMissing
                                            ? 'Note: Your telecaller user account in the CRM was registered with a username/ID only, without an email or phone column in the database record. You can still reset your password below by typing your email directly.'
                                            : isEmailMissing
                                                ? 'Note: No email address is linked to your telecaller account in the CRM database. You can enter your email directly in the Password Reset section below.'
                                                : 'Note: No mobile phone number is linked to your user account in the CRM database.',
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          height: 1.35,
                                          color: Color(0xFF92400E),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // 4. Security & Password Reset Card
                    Card(
                      elevation: 0.5,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.lock_reset_rounded, size: 18, color: Color(0xFFD97706)),
                                SizedBox(width: 8),
                                Text(
                                  'Security & Authentication',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'Update your login password using your current password, or reset it securely via an email OTP code.',
                              style: TextStyle(fontSize: 12, color: Color(0xFF64748B), height: 1.35),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: _showChangePasswordDialog,
                                    icon: const Icon(Icons.password_rounded, size: 16),
                                    label: const Text('Change Password'),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(0xFF2563EB),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 11),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _showPasswordResetDialog,
                                    icon: const Icon(Icons.mail_outline_rounded, size: 16, color: Color(0xFF2563EB)),
                                    label: const Text('Email OTP Reset', style: TextStyle(color: Color(0xFF2563EB), fontWeight: FontWeight.bold)),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 11),
                                      side: const BorderSide(color: Color(0xFF2563EB), width: 1.2),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Action Buttons
                    FilledButton.tonalIcon(
                      onPressed: _isRefreshing ? null : () => _fetchProfile(isInitial: false),
                      icon: const Icon(Icons.sync_rounded, size: 18),
                      label: const Text('Sync Latest Profile from Server'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _confirmSignOut,
                      icon: const Icon(Icons.logout_rounded, size: 18, color: Colors.red),
                      label: const Text('Sign Out', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.red.shade300, width: 1.2),
                        padding: const EdgeInsets.symmetric(vertical: 12),
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

  Widget _buildMetricTile({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10.5,
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    bool isMonospace = false,
    bool isWarning = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: isWarning ? const Color(0xFFD97706) : const Color(0xFF64748B)),
        const SizedBox(width: 10),
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isWarning ? const Color(0xFFB45309) : const Color(0xFF0F172A),
              fontStyle: isWarning ? FontStyle.italic : FontStyle.normal,
              fontFamily: isMonospace ? 'monospace' : null,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Modal Bottom Sheet for Email OTP Password Reset
class _PasswordResetModal extends StatefulWidget {
  final String initialEmail;

  const _PasswordResetModal({required this.initialEmail});

  @override
  State<_PasswordResetModal> createState() => _PasswordResetModalState();
}

class _PasswordResetModalState extends State<_PasswordResetModal> {
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isSendingOtp = false;
  bool _isResettingPassword = false;
  bool _otpSent = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  int _resendCooldown = 0;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _emailController.text = widget.initialEmail.contains('@') ? widget.initialEmail : '';
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _emailController.dispose();
    _otpController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _startCooldown() {
    setState(() => _resendCooldown = 60);
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendCooldown > 1) {
        if (mounted) setState(() => _resendCooldown--);
      } else {
        timer.cancel();
        if (mounted) setState(() => _resendCooldown = 0);
      }
    });
  }

  Future<void> _handleSendOtp() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid email address to receive the verification OTP.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isSendingOtp = true);

    try {
      final res = await ApiService.sendPasswordResetOtp(email);
      final msg = res['message'] ?? 'OTP sent to $email. Please check your inbox or spam.';
      if (mounted) {
        setState(() {
          _otpSent = true;
          _isSendingOtp = false;
        });
        _startCooldown();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSendingOtp = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _handleResetPassword() async {
    final email = _emailController.text.trim();
    final otp = _otpController.text.trim();
    final newPass = _passwordController.text;
    final confirmPass = _confirmPasswordController.text;

    if (otp.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter the OTP verification code.')),
      );
      return;
    }
    if (newPass.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password must be at least 6 characters.')),
      );
      return;
    }
    if (newPass != confirmPass) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passwords do not match.')),
      );
      return;
    }

    setState(() => _isResettingPassword = true);

    try {
      final res = await ApiService.resetPasswordWithOtp(
        email: email,
        otp: otp,
        newPassword: newPass,
      );
      final msg = res['message'] ?? 'Password reset successfully! Please use your new password next time you log in.';

      if (mounted) {
        setState(() => _isResettingPassword = false);
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isResettingPassword = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 18,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.lock_reset_rounded, color: Color(0xFF2563EB), size: 20),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Reset Password via Email OTP',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20, color: Color(0xFF64748B)),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Step 1: Email Address
            const Text(
              '1. Verification Email Address',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              enabled: !_otpSent,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.email_outlined, size: 18, color: Color(0xFF64748B)),
                hintText: 'Enter email to receive OTP (e.g. user@gmail.com)',
                filled: true,
                fillColor: _otpSent ? const Color(0xFFF1F5F9) : const Color(0xFFF8FAFC),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
              ),
            ),
            const SizedBox(height: 10),

            if (!_otpSent) ...[
              FilledButton.icon(
                onPressed: _isSendingOtp ? null : _handleSendOtp,
                icon: _isSendingOtp
                    ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_rounded, size: 16),
                label: Text(_isSendingOtp ? 'Sending OTP...' : 'Send Verification OTP'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ] else ...[
              // Step 2: OTP & New Password Inputs
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFA7F3D0)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline, color: Color(0xFF059669), size: 16),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        'OTP sent to your email. Please check your inbox or spam.',
                        style: TextStyle(fontSize: 11.5, color: Color(0xFF047857), fontWeight: FontWeight.w600),
                      ),
                    ),
                    TextButton(
                      onPressed: _resendCooldown > 0 ? null : _handleSendOtp,
                      child: Text(
                        _resendCooldown > 0 ? '${_resendCooldown}s' : 'Resend',
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              const Text(
                '2. Verification Code (OTP)',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.pin_outlined, size: 18, color: Color(0xFF64748B)),
                  hintText: 'Enter 6-digit OTP code',
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                ),
              ),
              const SizedBox(height: 12),

              const Text(
                '3. New Password',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.lock_outline, size: 18, color: Color(0xFF64748B)),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  hintText: 'Minimum 6 characters',
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                ),
              ),
              const SizedBox(height: 12),

              const Text(
                '4. Confirm New Password',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _confirmPasswordController,
                obscureText: _obscureConfirmPassword,
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.lock_outline, size: 18, color: Color(0xFF64748B)),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureConfirmPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
                    onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                  ),
                  hintText: 'Re-enter your new password',
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                ),
              ),
              const SizedBox(height: 16),

              FilledButton.icon(
                onPressed: _isResettingPassword ? null : _handleResetPassword,
                icon: _isResettingPassword
                    ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check_circle_outline, size: 16),
                label: Text(_isResettingPassword ? 'Updating Password...' : 'Reset Password'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
