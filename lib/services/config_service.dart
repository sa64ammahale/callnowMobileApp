import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:callnow_new/model/user_profile.dart';
import 'package:callnow_new/services/secure_storage_service.dart';
import 'package:callnow_new/services/followup_service.dart';

class ConfigService {
  static const String _baseUrlKey = 'base_url';
  static const String _userDataKey = 'user_data';
  static const String _defaultBaseUrl =
      'https://callnow.increditsolutions.in/api/v1';

  static String _cachedBaseUrl = _defaultBaseUrl;
  static String? _cachedToken;
  static Map<String, dynamic>? _cachedUserData;
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    _cachedBaseUrl = prefs.getString(_baseUrlKey) ?? _defaultBaseUrl;
    _cachedToken = await SecureStorageService.instance.readToken();
    final userDataStr = prefs.getString(_userDataKey);
    if (userDataStr != null) {
      try {
        final decoded = json.decode(userDataStr);
        if (decoded is Map) {
          _cachedUserData = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
    }
    _initialized = true;
  }

  static String get baseUrl {
    String url = _cachedBaseUrl.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  static Future<void> setBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    String normalizedUrl = url.trim();
    while (normalizedUrl.endsWith('/')) {
      normalizedUrl = normalizedUrl.substring(0, normalizedUrl.length - 1);
    }
    await prefs.setString(_baseUrlKey, normalizedUrl);
    _cachedBaseUrl = normalizedUrl;
    _initialized = true;
  }

  static String? get token => _cachedToken;

  static Map<String, dynamic>? get userData => _cachedUserData;

  static UserProfile get userProfile => UserProfile.fromJson(_cachedUserData ?? {});

  static String? get userProfilePhotoUrl {
    if (_cachedUserData == null) return null;
    return userProfile.profilePhotoUrl;
  }

  static bool get isLoggedIn => _cachedToken != null;

  static String get userDisplayName {
    final u = _cachedUserData;
    if (u == null) return 'Telecaller';
    if (u['name'] != null && u['name'].toString().trim().isNotEmpty) {
      return u['name'].toString().trim();
    }
    if (u['full_name'] != null && u['full_name'].toString().trim().isNotEmpty) {
      return u['full_name'].toString().trim();
    }
    if (u['username'] != null && u['username'].toString().trim().isNotEmpty) {
      return u['username'].toString().trim();
    }
    if (u['user'] is Map) {
      final nested = u['user'] as Map;
      return nested['name']?.toString() ??
          nested['full_name']?.toString() ??
          nested['username']?.toString() ??
          'Telecaller';
    }
    return 'Telecaller';
  }

  static String get userRole {
    final u = _cachedUserData;
    if (u == null) return 'TELECALLER';
    final role = u['role'] ?? (u['user'] is Map ? (u['user'] as Map)['role'] : null);
    return role?.toString().toUpperCase() ?? 'TELECALLER';
  }

  static bool get canMoveLeadStage {
    final u = _cachedUserData;
    if (u != null) {
      if (u['can_move_lead_stage'] == true || u['can_change_lead_status'] == true) {
        return true;
      }
      final userObj = u['user'] is Map ? u['user'] as Map : null;
      if (userObj != null && (userObj['can_move_lead_stage'] == true || userObj['can_change_lead_status'] == true)) {
        return true;
      }
    }
    final r = userRole.toUpperCase();
    return r.contains('SUPER ADMIN') ||
        r.contains('SUPERADMIN') ||
        r.contains('ADMIN') ||
        r.contains('SUPERVISOR') ||
        r.contains('MANAGER');
  }

  static String get userId {
    final u = _cachedUserData;
    if (u == null) return 'N/A';
    final id = u['id'] ?? (u['user'] is Map ? (u['user'] as Map)['id'] : null);
    return id != null ? '#$id' : 'N/A';
  }

  static String get userEmail {
    final u = _cachedUserData;
    if (u == null) return '';
    const emailKeys = [
      'email',
      'user_email',
      'email_address',
      'email_id',
      'work_email',
      'mail',
      'username',
    ];
    for (final k in emailKeys) {
      if (u[k] != null) {
        final val = u[k].toString().trim();
        if (val.contains('@')) return val;
      }
      if (u['user'] is Map && (u['user'] as Map)[k] != null) {
        final val = (u['user'] as Map)[k].toString().trim();
        if (val.contains('@')) return val;
      }
      if (u['profile'] is Map && (u['profile'] as Map)[k] != null) {
        final val = (u['profile'] as Map)[k].toString().trim();
        if (val.contains('@')) return val;
      }
    }
    // If username is an email
    if (u['username'] != null && u['username'].toString().contains('@')) {
      return u['username'].toString().trim();
    }
    return u['email']?.toString() ?? '';
  }

  static String get userPhone {
    final u = _cachedUserData;
    if (u == null) return '';
    const phoneKeys = [
      'phone',
      'mobile',
      'phone_number',
      'mobile_no',
      'mobile_number',
      'contact_number',
      'contact_no',
      'phone_no',
      'contact',
      'telephone',
    ];
    for (final k in phoneKeys) {
      if (u[k] != null && u[k].toString().trim().isNotEmpty) {
        return u[k].toString().trim();
      }
      if (u['user'] is Map && (u['user'] as Map)[k] != null) {
        final val = (u['user'] as Map)[k].toString().trim();
        if (val.isNotEmpty) return val;
      }
      if (u['profile'] is Map && (u['profile'] as Map)[k] != null) {
        final val = (u['profile'] as Map)[k].toString().trim();
        if (val.isNotEmpty) return val;
      }
    }
    return '';
  }

  static Future<void> saveAuthData(String token, Map<String, dynamic> userData, {String? fallbackEmail}) async {
    final prefs = await SharedPreferences.getInstance();

    // Preserve existing cached user fields so an empty profile from the server doesn't wipe them out!
    Map<String, dynamic> merged = {};
    if (_cachedUserData != null) {
      merged.addAll(_cachedUserData!);
    }

    // Normalize if nested under 'user' or 'profile'
    Map<String, dynamic> incoming = Map<String, dynamic>.from(userData);
    if (incoming.containsKey('user') && incoming['user'] is Map) {
      final nested = Map<String, dynamic>.from(incoming['user'] as Map);
      nested.forEach((k, v) => incoming.putIfAbsent(k, () => v));
    }
    if (incoming.containsKey('profile') && incoming['profile'] is Map) {
      final nested = Map<String, dynamic>.from(incoming['profile'] as Map);
      nested.forEach((k, v) => incoming.putIfAbsent(k, () => v));
    }

    // Merge non-null, non-empty incoming values into merged
    incoming.forEach((k, v) {
      if (v != null && v != 'null' && v != '<null>') {
        if (v is String && v.trim().isEmpty) return;
        if (v is List && v.isEmpty) return;
        merged[k] = v;
      }
    });

    if (fallbackEmail != null && fallbackEmail.trim().isNotEmpty && fallbackEmail.contains('@')) {
      merged.putIfAbsent('email', () => fallbackEmail.trim());
      merged.putIfAbsent('user_email', () => fallbackEmail.trim());
    }

    // If name is still missing or generic 'Telecaller', derive a friendly name from email
    final currentName = merged['name']?.toString().trim() ?? '';
    final emailStr = merged['email']?.toString().trim() ?? (fallbackEmail?.trim() ?? '');
    if ((currentName.isEmpty || currentName.toLowerCase() == 'telecaller') && emailStr.contains('@')) {
      final prefix = emailStr.split('@').first;
      final parts = prefix.split(RegExp(r'[._-]')).where((p) => p.isNotEmpty);
      final capitalized = parts.map((p) => p[0].toUpperCase() + p.substring(1)).join(' ');
      if (capitalized.isNotEmpty) {
        merged['name'] = capitalized;
      }
      merged.putIfAbsent('username', () => prefix);
    }

    await SecureStorageService.instance.writeToken(token);
    // Sync sensitive PII to encrypted secure storage
    if (merged['email'] != null && merged['email'].toString().isNotEmpty) {
      await SecureStorageService.instance.writeEmail(merged['email'].toString());
    }
    if (merged['phone'] != null && merged['phone'].toString().isNotEmpty) {
      await SecureStorageService.instance.writePhone(merged['phone'].toString());
    }
    if (merged['name'] != null && merged['name'].toString().isNotEmpty) {
      await SecureStorageService.instance.writeName(merged['name'].toString());
    }
    if (merged['id'] != null) {
      await SecureStorageService.instance.writeUserId(merged['id'].toString());
    }
    await prefs.setString(_userDataKey, json.encode(merged));
    _cachedToken = token;
    _cachedUserData = merged;
  }

  static Future<void> clearAuthData() async {
    final prefs = await SharedPreferences.getInstance();
    await SecureStorageService.instance.clearAll();
    await prefs.remove(_userDataKey);
    _cachedToken = null;
    _cachedUserData = null;
    FollowupService.instance.clearLocalCache();
  }

  static String get defaultBaseUrl => _defaultBaseUrl;

  static Future<void> resetToDefault() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_baseUrlKey);
    _cachedBaseUrl = _defaultBaseUrl;
  }

  static bool get isUsingDefault => _cachedBaseUrl == _defaultBaseUrl;
}