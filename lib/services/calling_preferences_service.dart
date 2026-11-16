import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CallingPreferencesService {
  static const String keyVibrateOnEnd = 'callnow_pref_vibrate_on_end';
  static const String keyKeepScreenAwake = 'callnow_pref_keep_screen_awake';
  static const String keyPreferredDialer = 'callnow_pref_preferred_dialer';
  static const String keyAutoCopyNumber = 'callnow_pref_auto_copy_number';

  /// Default dialer mode is 'system' (Standard Android Phone Dialer via tel: URL)
  static const String dialerSystem = 'system';
  /// Direct dialer mode passes directly to dialer prompt
  static const String dialerDirect = 'direct';

  static Future<bool> isVibrateOnCallEndEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(keyVibrateOnEnd) ?? true;
  }

  static Future<void> setVibrateOnCallEnd(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyVibrateOnEnd, enabled);
  }

  static Future<bool> isKeepScreenAwakeEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(keyKeepScreenAwake) ?? true;
  }

  static Future<void> setKeepScreenAwake(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyKeepScreenAwake, enabled);
  }

  static Future<String> getPreferredDialer() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(keyPreferredDialer) ?? dialerSystem;
  }

  static Future<void> setPreferredDialer(String dialer) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyPreferredDialer, dialer);
  }

  static Future<bool> isAutoCopyNumberEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(keyAutoCopyNumber) ?? false;
  }

  static Future<void> setAutoCopyNumber(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyAutoCopyNumber, enabled);
  }

  /// Triggers a haptic vibration when a call completes if vibration preference is enabled
  static Future<void> triggerCallEndVibration() async {
    final enabled = await isVibrateOnCallEndEnabled();
    if (enabled) {
      try {
        await HapticFeedback.vibrate();
      } catch (_) {}
    }
  }
}
