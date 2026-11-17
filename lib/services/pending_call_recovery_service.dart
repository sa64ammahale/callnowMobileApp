import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service to persist and recover in-progress/dialed calls across cold app restarts.
/// Essential for low-RAM mobile devices where the Android OS terminates background
/// apps when the system phone dialer is launched.
class PendingCallRecoveryService {
  static const String _prefKeyPendingLead = 'callnow_pending_dialed_lead';
  static const String _prefKeyPendingTime = 'callnow_pending_dialed_timestamp';

  /// Maximum age for a pending call before it is considered expired (4 hours).
  static const Duration maxPendingAge = Duration(hours: 4);

  /// Saves the active lead and current timestamp to persistent storage before launching phone dialer.
  static Future<void> savePendingCall(Map<String, dynamic> lead) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKeyPendingLead, jsonEncode(lead));
      await prefs.setInt(_prefKeyPendingTime, DateTime.now().millisecondsSinceEpoch);
      debugPrint('[PendingCallRecovery] Saved pending call for ${lead['name']} (${lead['mobile']})');
    } catch (e) {
      debugPrint('[PendingCallRecovery] Failed to save pending call: $e');
    }
  }

  /// Retrieves the persisted lead if dialed within [maxPendingAge].
  /// Returns null if no call is pending or if it has expired.
  static Future<Map<String, dynamic>?> getPendingCall() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawLead = prefs.getString(_prefKeyPendingLead);
      final timestamp = prefs.getInt(_prefKeyPendingTime);

      if (rawLead == null || rawLead.isEmpty || timestamp == null) {
        return null;
      }

      final dialedTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      final age = DateTime.now().difference(dialedTime);

      if (age > maxPendingAge) {
        debugPrint('[PendingCallRecovery] Pending call expired (${age.inMinutes} mins old). Clearing.');
        await clearPendingCall();
        return null;
      }

      final decoded = jsonDecode(rawLead);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (e) {
      debugPrint('[PendingCallRecovery] Failed to load pending call: $e');
    }
    return null;
  }

  /// Checks if there is an active pending call awaiting disposition.
  static Future<bool> hasPendingCall() async {
    final pending = await getPendingCall();
    return pending != null;
  }

  /// Returns the timestamp when the pending call was dialed, or null.
  static Future<DateTime?> getPendingCallDialedTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getInt(_prefKeyPendingTime);
      if (timestamp != null) {
        return DateTime.fromMillisecondsSinceEpoch(timestamp);
      }
    } catch (_) {}
    return null;
  }

  /// Helper to reliably extract lead ID from lead maps
  static int extractLeadId(Map<String, dynamic> lead) {
    final raw = lead['id'] ?? lead['lead_id'] ?? lead['record_id'] ?? lead['ID'] ?? lead['cust_id'];
    return int.tryParse(raw?.toString() ?? '0') ?? 0;
  }

  /// Helper to reliably extract and normalize source ('TEMP' or 'MAIN')
  static String extractSource(Map<String, dynamic> lead) {
    final raw = (lead['source'] ?? lead['source_type'] ?? lead['SOURCE'] ?? 'TEMP').toString().trim().toUpperCase();
    if (raw == 'TEMPORARY' || raw == 'TEMP') return 'TEMP';
    if (raw == 'MAIN' || raw == 'CLIENT_DATA') return 'MAIN';
    if (raw == 'LEAD' || raw == 'CRM') return 'LEAD';
    return raw.isNotEmpty ? raw : 'TEMP';
  }

  /// Clears the pending call after the user successfully submits or skips the call.
  static Future<void> clearPendingCall() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefKeyPendingLead);
      await prefs.remove(_prefKeyPendingTime);
      debugPrint('[PendingCallRecovery] Cleared pending call.');
    } catch (e) {
      debugPrint('[PendingCallRecovery] Failed to clear pending call: $e');
    }
  }
}
