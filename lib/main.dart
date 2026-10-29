import 'package:flutter/material.dart';
import 'package:callnow_new/services/config_service.dart';
import 'package:callnow_new/widgets/splash_screen.dart';
import 'package:callnow_new/screens/login_screen.dart';
import 'package:callnow_new/screens/home_screen.dart';
import 'package:callnow_new/screens/settings_screen.dart';

import 'package:callnow_new/screens/calling_desk_screen.dart';
import 'package:callnow_new/screens/call_reports_screen.dart';
import 'package:callnow_new/screens/leads_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ConfigService.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CallNow 5.0',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color.fromARGB(255, 42, 43, 41),
        ),
        useMaterial3: true,
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
      },
      debugShowCheckedModeBanner: false,
    );
  }
}
