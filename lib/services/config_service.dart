import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class ConfigService {
  static const String _baseUrlKey = 'base_url';
  static const String _tokenKey = 'auth_token';
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
    _cachedToken = prefs.getString(_tokenKey);
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
    String url = (_initialized ? _cachedBaseUrl : _defaultBaseUrl).trim();
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
  }

  static String? get token => _cachedToken;

  static Map<String, dynamic>? get userData => _cachedUserData;

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
    // Normalize if nested under 'user' or 'profile'
    Map<String, dynamic> normalized = Map<String, dynamic>.from(userData);
    if (normalized.containsKey('user') && normalized['user'] is Map) {
      final nested = Map<String, dynamic>.from(normalized['user'] as Map);
      nested.forEach((k, v) => normalized.putIfAbsent(k, () => v));
    }
    if (normalized.containsKey('profile') && normalized['profile'] is Map) {
      final nested = Map<String, dynamic>.from(normalized['profile'] as Map);
      nested.forEach((k, v) => normalized.putIfAbsent(k, () => v));
    }
    if (fallbackEmail != null && fallbackEmail.trim().isNotEmpty && fallbackEmail.contains('@')) {
      normalized.putIfAbsent('email', () => fallbackEmail.trim());
    }
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_userDataKey, json.encode(normalized));
    _cachedToken = token;
    _cachedUserData = normalized;
  }

  static Future<void> clearAuthData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userDataKey);
    _cachedToken = null;
    _cachedUserData = null;
  }

  static String get defaultBaseUrl => _defaultBaseUrl;

  static Future<void> resetToDefault() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_baseUrlKey);
    _cachedBaseUrl = _defaultBaseUrl;
  }

  static bool get isUsingDefault => _cachedBaseUrl == _defaultBaseUrl;
}