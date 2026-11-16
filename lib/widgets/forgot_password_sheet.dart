import 'dart:async';
import 'package:flutter/material.dart';
import 'package:callnow_new/services/api_service.dart';
import 'package:callnow_new/services/config_service.dart';

class ForgotPasswordSheet extends StatefulWidget {
  final String initialEmail;
  final String? initialCompanyCode;
  final ValueChanged<String>? onPasswordResetSuccess;

  const ForgotPasswordSheet({
    super.key,
    this.initialEmail = '',
    this.initialCompanyCode,
    this.onPasswordResetSuccess,
  });

  static Future<void> show(
    BuildContext context, {
    String initialEmail = '',
    String? initialCompanyCode,
    ValueChanged<String>? onPasswordResetSuccess,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ForgotPasswordSheet(
        initialEmail: initialEmail,
        initialCompanyCode: initialCompanyCode,
        onPasswordResetSuccess: onPasswordResetSuccess,
      ),
    );
  }

  @override
  State<ForgotPasswordSheet> createState() => _ForgotPasswordSheetState();
}

class _ForgotPasswordSheetState extends State<ForgotPasswordSheet> {
  final _emailController = TextEditingController();
  final _companyCodeController = TextEditingController();
  final _otpController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isSendingOtp = false;
  bool _isResettingPassword = false;
  bool _otpSent = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  String? _debugOtp;
  int _resendCooldown = 0;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _emailController.text = widget.initialEmail.contains('@') ? widget.initialEmail.trim() : '';
    final code = widget.initialCompanyCode?.trim() ?? ConfigService.companyCode ?? '';
    _companyCodeController.text = code;
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _emailController.dispose();
    _companyCodeController.dispose();
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

    setState(() {
      _isSendingOtp = true;
      _debugOtp = null;
    });

    try {
      final companyCode = _companyCodeController.text.trim();
      final res = await ApiService.sendPasswordResetOtp(
        email,
        companyCode: companyCode.isNotEmpty ? companyCode : null,
      );

      final msg = res['message']?.toString() ?? 'OTP sent to $email. Please check your inbox or spam.';
      final devOtp = res['debug_otp']?.toString();

      if (mounted) {
        setState(() {
          _otpSent = true;
          _isSendingOtp = false;
          _debugOtp = devOtp;
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
      final companyCode = _companyCodeController.text.trim();
      final res = await ApiService.resetPasswordWithOtp(
        email: email,
        otp: otp,
        newPassword: newPass,
        companyCode: companyCode.isNotEmpty ? companyCode : null,
      );
      final msg = res['message']?.toString() ?? 'Password reset successfully! You can now sign in with your new password.';

      if (mounted) {
        setState(() => _isResettingPassword = false);
        Navigator.pop(context);
        widget.onPasswordResetSuccess?.call(newPass);

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
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.mark_email_read_outlined, color: Color(0xFF2563EB), size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Reset Password via Email OTP',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Step 1: Email & Company Code Inputs
            const Text(
              '1. Account Verification',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _companyCodeController,
              enabled: !_otpSent,
              decoration: InputDecoration(
                labelText: 'Company / Organization Code',
                hintText: 'e.g. incredit (optional)',
                prefixIcon: const Icon(Icons.business_outlined, size: 20),
                filled: true,
                fillColor: _otpSent ? const Color(0xFFF1F5F9) : const Color(0xFFF8FAFC),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _emailController,
              enabled: !_otpSent,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: 'Registered Email Address',
                hintText: 'Enter email to receive OTP (e.g. user@gmail.com)',
                prefixIcon: const Icon(Icons.email_outlined, size: 20),
                filled: true,
                fillColor: _otpSent ? const Color(0xFFF1F5F9) : const Color(0xFFF8FAFC),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(height: 12),

            if (!_otpSent) ...[
              FilledButton.icon(
                onPressed: _isSendingOtp ? null : _handleSendOtp,
                icon: _isSendingOtp
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_rounded, size: 18),
                label: Text(_isSendingOtp ? 'Sending OTP...' : 'Send Verification OTP'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ] else ...[
              // Step 2: OTP & New Password Inputs
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline, color: Colors.green.shade700, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'OTP sent to your email. Please check your inbox or spam.',
                        style: TextStyle(color: Colors.green.shade800, fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                    ),
                    TextButton(
                      onPressed: _resendCooldown > 0 ? null : _handleSendOtp,
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(60, 30)),
                      child: Text(
                        _resendCooldown > 0 ? '${_resendCooldown}s' : 'Resend',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _resendCooldown > 0 ? Colors.grey : const Color(0xFF2563EB)),
                      ),
                    ),
                  ],
                ),
              ),
              if (_debugOtp != null && _debugOtp!.isNotEmpty) ...[
                const SizedBox(height: 8),
                InkWell(
                  onTap: () {
                    _otpController.text = _debugOtp!;
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.developer_mode, size: 16, color: Colors.amber.shade900),
                        const SizedBox(width: 6),
                        Text(
                          'Test OTP: $_debugOtp (Tap to paste)',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 14),

              const Text(
                '2. Verification Code (OTP)',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: InputDecoration(
                  labelText: '6-Digit OTP Code',
                  hintText: 'Enter 6-digit OTP code',
                  counterText: '',
                  prefixIcon: const Icon(Icons.pin_outlined, size: 20),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
              const SizedBox(height: 10),

              const Text(
                '3. Set New Password',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'New Password',
                  hintText: 'Minimum 6 characters',
                  prefixIcon: const Icon(Icons.lock_outline, size: 20),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _confirmPasswordController,
                obscureText: _obscureConfirmPassword,
                decoration: InputDecoration(
                  labelText: 'Confirm New Password',
                  hintText: 'Re-enter new password',
                  prefixIcon: const Icon(Icons.lock_outline, size: 20),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureConfirmPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
                    onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
              const SizedBox(height: 16),

              FilledButton.icon(
                onPressed: _isResettingPassword ? null : _handleResetPassword,
                icon: _isResettingPassword
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check_circle_outline, size: 18),
                label: Text(_isResettingPassword ? 'Resetting Password...' : 'Reset Password & Save'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
