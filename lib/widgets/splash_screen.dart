import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:callnow_new/services/config_service.dart';
import 'package:callnow_new/services/permission_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _handleStartupRouting();
  }

  Future<void> _handleStartupRouting() async {
    final stopwatch = Stopwatch()..start();

    // Check permissions
    final hasAllPermissions = await PermissionService.hasAllPermissions();

    final elapsedMs = stopwatch.elapsedMilliseconds;
    final remainingMs = 1200 - elapsedMs;

    if (remainingMs > 0) {
      final completer = Completer<void>();
      _timer = Timer(Duration(milliseconds: remainingMs), () {
        if (!completer.isCompleted) completer.complete();
      });
      await completer.future;
    }

    if (!mounted) return;

    if (!hasAllPermissions) {
      Navigator.pushReplacementNamed(context, '/permissions');
    } else if (ConfigService.isLoggedIn) {
      Navigator.pushReplacementNamed(context, '/home');
    } else {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2A2B29),
      body: Center(
        child: Text(
          'CallNow',
          style: GoogleFonts.aclonica(
            textStyle: Theme.of(context).textTheme.displayMedium,
            color: Colors.white70,
            fontSize: 45,
          ),
        ),
      ),
    );
  }
}
