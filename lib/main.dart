import 'package:flutter/material.dart';
import 'package:callnow_new/services/config_service.dart';
import 'package:callnow_new/widgets/splash_screen.dart';
import 'package:callnow_new/screens/login_screen.dart';
import 'package:callnow_new/screens/home_screen.dart';
import 'package:callnow_new/screens/settings_screen.dart';
import 'package:callnow_new/screens/profile_screen.dart';

import 'package:callnow_new/screens/calling_desk_screen.dart';
import 'package:callnow_new/screens/call_reports_screen.dart';
import 'package:callnow_new/screens/leads_screen.dart';
import 'package:callnow_new/screens/followup_screen.dart';
import 'package:callnow_new/screens/permission_screen.dart';
import 'package:callnow_new/screens/server_settings_screen.dart';
import 'package:callnow_new/services/notification_service.dart';
import 'package:callnow_new/services/followup_service.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Future.wait([
    ConfigService.init(),
    NotificationService.init(),
    FollowupService.init(),
  ]);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'CallNow 5.0',
      themeMode: ThemeMode.light,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF6FAF7),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF10B981),
          brightness: Brightness.light,
          primary: const Color(0xFF10B981),
          surface: Colors.white,
          surfaceContainerLowest: Colors.white,
          surfaceContainerLow: const Color(0xFFF6FAF7),
          surfaceContainer: const Color(0xFFECFDF5),
          outline: const Color(0xFFCBD5E1),
          outlineVariant: const Color(0xFFE2E8F0),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF064E3B),
          elevation: 0,
          scrolledUnderElevation: 0.5,
          surfaceTintColor: Colors.transparent,
          iconTheme: IconThemeData(color: Color(0xFF065F46)),
          titleTextStyle: TextStyle(
            color: Color(0xFF064E3B),
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFFD1FAE5), width: 1),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.white,
          elevation: 4,
          surfaceTintColor: Colors.transparent,
          indicatorColor: const Color(0xFFD1FAE5),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF047857),
              );
            }
            return const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Color(0xFF64748B),
            );
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const IconThemeData(color: Color(0xFF047857), size: 24);
            }
            return const IconThemeData(color: Color(0xFF64748B), size: 24);
          }),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF10B981), width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFEF4444)),
          ),
          hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
          labelStyle: const TextStyle(color: Color(0xFF475569), fontSize: 14),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF10B981),
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF10B981),
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: Color(0xFFE2E8F0),
          thickness: 1,
          space: 1,
        ),
      ),
      initialRoute: '/splash',
      routes: {
        '/splash': (context) => const SplashScreen(),
        '/login': (context) => const LoginScreen(),
        '/home': (context) => const HomeScreen(),
        '/leads': (context) => const LeadsScreen(),
        '/calling_desk': (context) => const CallingDeskScreen(),
        '/reports': (context) => const CallReportsScreen(),
        '/settings': (context) => const SettingsScreen(),
        '/profile': (context) => const ProfileScreen(),
        '/followups': (context) => const FollowUpScreen(),
        '/permissions': (context) => const PermissionScreen(),
        '/server_settings': (context) => const ServerSettingsScreen(),
      },
      debugShowCheckedModeBanner: false,
    );
  }
}
