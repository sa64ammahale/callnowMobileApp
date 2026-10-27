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
      _cachedUserData = Map<String, dynamic>.from(
        Map.castFrom(json.decode(userDataStr)),
      );
    }
    _initialized = true;
  }

  static String get baseUrl {
    if (!_initialized) {
      return _defaultBaseUrl;
    }
    print('[ConfigService] baseUrl: $_cachedBaseUrl');
    return _cachedBaseUrl;
  }

  static Future<void> setBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    String normalizedUrl = url.trim();
    if (!normalizedUrl.endsWith('/')) {
      normalizedUrl = '$normalizedUrl/';
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
    final email = u['email'] ?? (u['user'] is Map ? (u['user'] as Map)['email'] : null);
    return email?.toString() ?? '';
  }

  static Future<void> saveAuthData(String token, Map<String, dynamic> userData) async {
    final prefs = await SharedPreferences.getInstance();
    // Normalize if nested under 'user'
    Map<String, dynamic> normalized = Map<String, dynamic>.from(userData);
    if (normalized.containsKey('user') && normalized['user'] is Map) {
      final nested = Map<String, dynamic>.from(normalized['user'] as Map);
      nested.forEach((k, v) => normalized.putIfAbsent(k, () => v));
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