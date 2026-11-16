import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:callnow_new/model/user_profile.dart';
import 'package:callnow_new/services/secure_storage_service.dart';
import 'package:callnow_new/services/followup_service.dart';

class ConfigService {
  static final ValueNotifier<int> profileNotifier = ValueNotifier<int>(0);
  static const String _baseUrlKey = 'base_url';
  static const String _userDataKey = 'user_data';
  static const String _companyCodeKey = 'company_code';
  static const String _lastLoginDateKey = 'last_login_date';
  static const String _defaultBaseUrl =
      'https://callnow.increditsolutions.in/api/v1';

  static String _cachedBaseUrl = _defaultBaseUrl;
  static String? _cachedToken;
  static String? _cachedCompanyCode;
  static Map<String, dynamic>? _cachedUserData;
  static DateTime? _cachedLastLoginDate;
  static bool _initialized = false;

  @visibleForTesting
  static void resetForTesting() {
    _initialized = false;
    _cachedBaseUrl = _defaultBaseUrl;
    _cachedToken = null;
    _cachedCompanyCode = null;
    _cachedUserData = null;
    _cachedLastLoginDate = null;
  }

  static DateTime? get lastLoginDate => _cachedLastLoginDate;

  static Future<void> init() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();

    // Check last login date — if from a previous calendar day, clear all auth
    // data so the user must log in again on the new day. This covers the case
    // where the app process was killed before midnight and restarted after.
    final lastLoginStr = prefs.getString(_lastLoginDateKey);
    if (lastLoginStr != null) {
      try {
        final lastLogin = DateTime.tryParse(lastLoginStr);
        if (lastLogin != null) {
          final today = DateTime.now();
          if (today.day != lastLogin.day ||
              today.month != lastLogin.month ||
              today.year != lastLogin.year) {
            await SecureStorageService.instance.clearAll();
            await prefs.remove(_userDataKey);
            _cachedToken = null;
            _cachedUserData = null;
            _cachedCompanyCode = null;
            await prefs.remove(_companyCodeKey);
            await prefs.remove(_lastLoginDateKey);
            FollowupService.instance.clearLocalCache();
            _cachedBaseUrl = prefs.getString(_baseUrlKey) ?? _defaultBaseUrl;
            _initialized = true;
            return;
          }
          _cachedLastLoginDate = lastLogin;
        }
      } catch (_) {}
    }

    _cachedBaseUrl = prefs.getString(_baseUrlKey) ?? _defaultBaseUrl;
    _cachedToken = await SecureStorageService.instance.readToken();
    _cachedCompanyCode = await SecureStorageService.instance.readCompanyCode() ??
        prefs.getString(_companyCodeKey);
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

  /// Resolve user input (company code, domain, or full URL) into a canonical API base URL
  static String resolveServerUrl(String input) {
    String trimmed = input.trim();
    if (trimmed.isEmpty) return _defaultBaseUrl;

    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      while (trimmed.endsWith('/')) {
        trimmed = trimmed.substring(0, trimmed.length - 1);
      }
      if (!trimmed.endsWith('/api/v1')) {
        trimmed = '$trimmed/api/v1';
      }
      return trimmed;
    }

    if (trimmed.contains('.')) {
      return 'https://$trimmed/api/v1';
    }

    final slug = trimmed.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\-_]'), '');
    return 'https://$slug.increditsolutions.in/api/v1';
  }

  static Future<void> setBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    String normalizedUrl = resolveServerUrl(url);
    await prefs.setString(_baseUrlKey, normalizedUrl);
    _cachedBaseUrl = normalizedUrl;
    _initialized = true;
  }

  static String? get token => _cachedToken;

  static String? get companyCode => _cachedCompanyCode;

  static Future<void> setCompanyCode(String? code) async {
    final prefs = await SharedPreferences.getInstance();
    if (code != null && code.trim().isNotEmpty) {
      final clean = code.trim().toLowerCase();
      await SecureStorageService.instance.writeCompanyCode(clean);
      await prefs.setString(_companyCodeKey, clean);
      _cachedCompanyCode = clean;
    } else {
      await SecureStorageService.instance.deleteCompanyCode();
      await prefs.remove(_companyCodeKey);
      _cachedCompanyCode = null;
    }
  }

  static Map<String, dynamic>? get userData => _cachedUserData;

  static UserProfile get userProfile => UserProfile.fromJson(_cachedUserData ?? {});

  static String? get userProfilePhotoUrl {
    if (_cachedUserData == null) return null;
    return userProfile.profilePhotoUrl;
  }

  static ImageProvider? get userAvatarImageProvider {
    if (_cachedUserData == null) return null;
    return userProfile.avatarImageProvider;
  }

  static int get dailyCallingLimit => userProfile.dailyCallingLimit;

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

  static bool get isManagementOrSupervisor {
    final r = userRole.toUpperCase();
    return r.contains('SUPER ADMIN') ||
        r.contains('SUPERADMIN') ||
        r.contains('ADMIN') ||
        r.contains('SUPERVISOR') ||
        r.contains('MANAGER');
  }

  static bool get isAdminOrManager {
    final r = userRole.toUpperCase();
    return r.contains('SUPER ADMIN') ||
        r.contains('SUPERADMIN') ||
        r.contains('ADMIN') ||
        r.contains('MANAGER');
  }

  static bool get isSupervisor {
    final r = userRole.toUpperCase();
    return r.contains('SUPERVISOR') && !isAdminOrManager;
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

  static Future<void> saveAuthData(String token, Map<String, dynamic> userData, {String? fallbackEmail, String? companyCode}) async {
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

    // If incoming explicitly clears profile photo, remove photo keys from cached data
    if (incoming.containsKey('profile_photo') && (incoming['profile_photo'] == null || incoming['profile_photo'] == '')) {
      merged.remove('profile_photo');
      merged.remove('profile_photo_url');
      merged.remove('avatar_url');
      merged.remove('profile_picture');
      merged.remove('profile_picture_url');
    }

    final resolvedCompanyCode = (companyCode ?? merged['company_code'] ?? _cachedCompanyCode)?.toString().trim().toLowerCase();
    if (resolvedCompanyCode != null && resolvedCompanyCode.isNotEmpty) {
      merged['company_code'] = resolvedCompanyCode;
      await setCompanyCode(resolvedCompanyCode);
    }

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
    final phoneVal = merged['phone'] ?? merged['mobile'] ?? merged['phone_number'] ?? merged['mobile_no'];
    if (phoneVal != null && phoneVal.toString().isNotEmpty) {
      await SecureStorageService.instance.writePhone(phoneVal.toString());
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
    profileNotifier.value++;
    // Persist the login date so midnight rollover can be detected across
    // app restarts (process killed before midnight, reopened after).
    _cachedLastLoginDate = DateTime.now();
    await prefs.setString(_lastLoginDateKey, _cachedLastLoginDate!.toIso8601String());
  }

  static final List<void Function()> _onLogoutCallbacks = [];

  static void registerLogoutCallback(void Function() cb) {
    if (!_onLogoutCallbacks.contains(cb)) {
      _onLogoutCallbacks.add(cb);
    }
  }

  @visibleForTesting
  static void clearLogoutCallbacks() => _onLogoutCallbacks.clear();

  static Future<void> clearAuthData({bool clearCompanyCode = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final savedCompany = _cachedCompanyCode;
    await SecureStorageService.instance.clearAll();
    await prefs.remove(_userDataKey);
    await prefs.remove(_lastLoginDateKey);
    _cachedToken = null;
    _cachedUserData = null;
    _cachedLastLoginDate = null;
    profileNotifier.value++;
    if (clearCompanyCode) {
      _cachedCompanyCode = null;
      await prefs.remove(_companyCodeKey);
    } else if (savedCompany != null) {
      // Retain company code across logouts so user does not need to retype it
      await SecureStorageService.instance.writeCompanyCode(savedCompany);
      await prefs.setString(_companyCodeKey, savedCompany);
      _cachedCompanyCode = savedCompany;
    }
    FollowupService.instance.clearLocalCache();
    for (final cb in List<void Function()>.from(_onLogoutCallbacks)) {
      try {
        cb();
      } catch (_) {}
    }
  }

  static String get defaultBaseUrl => _defaultBaseUrl;

  static Future<void> resetToDefault() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_baseUrlKey);
    _cachedBaseUrl = _defaultBaseUrl;
  }

  static bool get isUsingDefault => _cachedBaseUrl == _defaultBaseUrl;
}