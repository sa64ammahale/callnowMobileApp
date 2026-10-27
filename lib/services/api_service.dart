import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:callnow_new/services/config_service.dart';

class ApiService {
  static String get _baseUrl => ConfigService.baseUrl;
  static String? get _token => ConfigService.token;

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  // --- AUTH ---
  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    // Try both email and username field names
    final fieldNames = ['email', 'username'];
    
    for (final fieldName in fieldNames) {
      final url = '$_baseUrl/auth/login';
      print('[ApiService] Login request to: $url');
      print('[ApiService] Login payload: $fieldName=$email');

      final body = {fieldName: email, 'password': password};
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: json.encode(body),
      );

      print('[ApiService] Login response: ${response.statusCode} - ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final token = data['data']['token'];
          final userData = data['data']['user'];
          await ConfigService.saveAuthData(token, userData);
          return {
            'success': true,
            'token': token,
            'user': userData,
            'expires_at': data['data']['expires_at'],
          };
        }
        throw Exception(data['message'] ?? 'Login failed');
      } else if (response.statusCode == 401) {
        // Parse the exact error message
        try {
          final error = json.decode(response.body);
          final msg = error['error']?['message'] ?? error['message'] ?? 'Invalid credentials';
          print('[ApiService] 401 Error: $msg (tried field: $fieldName)');
          // If this is the last field name, throw the error
          if (fieldName == fieldNames.last) {
            throw Exception('Login failed: $msg. Tried fields: ${fieldNames.join(', ')}');
          }
          // Otherwise try next field
        } catch (e) {
          if (fieldName == fieldNames.last) {
            throw Exception('Login failed: ${response.statusCode} - ${response.body}');
          }
        }
      } else if (response.statusCode != 410 && response.statusCode != 400) {
        String errorMsg;
        try {
          final error = json.decode(response.body);
          errorMsg = error['message'] ?? error['error'] ?? 'Login failed: ${response.statusCode}';
        } catch (_) {
          errorMsg = 'Login failed: ${response.statusCode} - ${response.body}';
        }
        throw Exception(errorMsg);
      }
    }
    
    throw Exception('Login failed: Invalid credentials or endpoint issue');
  }

  // Login with pre-generated API token (Bearer token)
  static Future<Map<String, dynamic>> loginWithToken(String token) async {
    if (token.isEmpty) {
      throw Exception('API token is required');
    }

    // Save token first, then verify with getProfile
    final tempToken = token;
    await ConfigService.saveAuthData(tempToken, {});

    try {
      // Verify token works by getting profile
      final profile = await getProfile();
      return {
        'success': true,
        'token': tempToken,
        'user': profile,
      };
    } catch (e) {
      await ConfigService.clearAuthData();
      throw Exception('Invalid API token: $e');
    }
  }

  static Future<Map<String, dynamic>> getProfile() async {
    final response = await http.get(
      Uri.parse('$_baseUrl/auth/me'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success'] == true) {
        await ConfigService.saveAuthData(_token!, data['data']);
        return data['data'];
      }
      throw Exception(data['message'] ?? 'Failed to get profile');
    } else if (response.statusCode == 401) {
      await ConfigService.clearAuthData();
      throw Exception('Session expired. Please login again.');
    } else {
      throw Exception('Failed to get profile: ${response.statusCode}');
    }
  }

  static Future<void> refreshToken() async {
    final response = await http.get(
      Uri.parse('$_baseUrl/auth/refresh'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success'] == true && data['data'] != null) {
        await ConfigService.saveAuthData(
          data['data']['token'],
          ConfigService.userData ?? {},
        );
      }
    } else if (response.statusCode == 401) {
      await ConfigService.clearAuthData();
      throw Exception('Session expired. Please login again.');
    }
  }

  static Future<void> logout() async {
    await ConfigService.clearAuthData();
  }

  // --- TELECALLER ---
  static Future<Map<String, dynamic>> getDashboardStats() async {
    final response = await http.get(
      Uri.parse('$_baseUrl/telecaller/dashboard'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success'] == true) return data['data'];
      throw Exception(data['message'] ?? 'Failed to load dashboard');
    } else if (response.statusCode == 401) {
      await ConfigService.clearAuthData();
      throw Exception('Session expired. Please login again.');
    } else {
      throw Exception('Failed to load dashboard: ${response.statusCode}');
    }
  }

  /// Fetch a batch of uncalled leads (default 15) from the server
  static Future<List<Map<String, dynamic>>> getBatchLeads({int limit = 15}) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/telecaller/batch-leads?limit=$limit'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success'] == true && data['data'] != null) {
        final list = data['data']['leads'] as List? ?? [];
        return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
      return [];
    } else if (response.statusCode == 401) {
      await ConfigService.clearAuthData();
      throw Exception('Session expired. Please login again.');
    } else {
      throw Exception('Failed to get batch leads: ${response.statusCode}');
    }
  }

  /// Single lead fallback fetch
  static Future<Map<String, dynamic>> getNextCall() async {
    final response = await http.get(
      Uri.parse('$_baseUrl/telecaller/next-call'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success'] == true) return data['data'];
      throw Exception(data['message'] ?? 'No pending calls');
    } else if (response.statusCode == 401) {
      await ConfigService.clearAuthData();
      throw Exception('Session expired. Please login again.');
    } else {
      throw Exception('Failed to get next call: ${response.statusCode}');
    }
  }

  /// Get aggregated performance reports summary
  static Future<Map<String, dynamic>> getCallReportSummary({
    String period = 'today',
    String? dateFrom,
    String? dateTo,
  }) async {
    final queryParams = <String, String>{'period': period};
    if (dateFrom != null) queryParams['date_from'] = dateFrom;
    if (dateTo != null) queryParams['date_to'] = dateTo;

    final uri = Uri.parse('$_baseUrl/telecaller/reports/summary')
        .replace(queryParameters: queryParams);
    final response = await http.get(uri, headers: _headers);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success'] == true) return data['data'] as Map<String, dynamic>;
      throw Exception(data['message'] ?? 'Failed to load report summary');
    } else if (response.statusCode == 401) {
      await ConfigService.clearAuthData();
      throw Exception('Session expired. Please login again.');
    } else {
      throw Exception('Failed to load report summary: ${response.statusCode}');
    }
  }

  /// Get rich joined dialed calls history
  static Future<Map<String, dynamic>> getCallHistory({
    String period = 'today',
    String? source,
    String? status,
    String? timingTier,
    String? dateFrom,
    String? dateTo,
    String? search,
    int page = 1,
    int limit = 30,
  }) async {
    final queryParams = <String, String>{
      'period': period,
      'page': page.toString(),
      'limit': limit.toString(),
    };
    if (source != null && source != 'all') queryParams['source'] = source;
    if (status != null && status != 'all') queryParams['status'] = status;
    if (timingTier != null && timingTier != 'all') queryParams['timing_tier'] = timingTier;
    if (dateFrom != null) queryParams['date_from'] = dateFrom;
    if (dateTo != null) queryParams['date_to'] = dateTo;
    if (search != null && search.isNotEmpty) queryParams['search'] = search;

    final uri = Uri.parse('$_baseUrl/telecaller/calls').replace(queryParameters: queryParams);
    final response = await http.get(uri, headers: _headers);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success'] == true) return data['data'];
      throw Exception(data['message'] ?? 'Failed to load call history');
    } else if (response.statusCode == 401) {
      await ConfigService.clearAuthData();
      throw Exception('Session expired. Please login again.');
    } else {
      throw Exception('Failed to load call history: ${response.statusCode}');
    }
  }

  static Future<Map<String, dynamic>> getCallRecordHistory({
    required int recordId,
    required String source,
  }) async {
    final uri = Uri.parse('$_baseUrl/telecaller/call-history/$recordId')
        .replace(queryParameters: {'source': source});
    final response = await http.get(uri, headers: _headers);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success'] == true) return data['data'];
      throw Exception(data['message'] ?? 'Failed to load call record history');
    } else if (response.statusCode == 401) {
      await ConfigService.clearAuthData();
      throw Exception('Session expired. Please login again.');
    } else {
      throw Exception('Failed to load call record history: ${response.statusCode}');
    }
  }

  /// Submit comprehensive call report to server
  static Future<Map<String, dynamic>> submitCallResult({
    required int callId,
    required String source,
    required String status,
    String? notes,
    int? durationSeconds,
    String? timingClassification,
    String? nextFollowupAt,
    String? callStartTime,
    String? callEndTime,
  }) async {
    final body = <String, dynamic>{
      'source': source,
      'call_status': status,
    };
    if (notes != null) body['notes'] = notes;
    if (durationSeconds != null) body['call_duration'] = durationSeconds;
    if (timingClassification != null) body['timing_classification'] = timingClassification;
    if (nextFollowupAt != null) body['next_followup'] = nextFollowupAt;
    if (callStartTime != null) body['call_start_time'] = callStartTime;
    if (callEndTime != null) body['call_end_time'] = callEndTime;

    final response = await http.post(
      Uri.parse('$_baseUrl/telecaller/calls/$callId/complete'),
      headers: _headers,
      body: json.encode(body),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success'] == true) return data['data'];
      throw Exception(data['message'] ?? 'Failed to submit call result');
    } else if (response.statusCode == 401) {
      await ConfigService.clearAuthData();
      throw Exception('Session expired. Please login again.');
    } else {
      throw Exception('Failed to submit call result: ${response.statusCode}');
    }
  }

  static Future<Map<String, dynamic>> submitCallDirect({
    required int recordId,
    required String source,
    required String callStatus,
    int? callDuration,
    String? notes,
    String? nextFollowup,
    String? recordingUrl,
  }) async {
    final body = <String, dynamic>{
      'record_id': recordId,
      'source': source,
      'call_status': callStatus,
    };
    if (callDuration != null) body['call_duration'] = callDuration;
    if (notes != null) body['notes'] = notes;
    if (nextFollowup != null) body['next_followup'] = nextFollowup;
    if (recordingUrl != null) body['recording_url'] = recordingUrl;

    final response = await http.post(
      Uri.parse('$_baseUrl/telecaller/submit_call.php'),
      headers: _headers,
      body: json.encode(body),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success'] == true) return data['data'];
      throw Exception(data['message'] ?? 'Failed to submit call');
    } else if (response.statusCode == 401) {
      await ConfigService.clearAuthData();
      throw Exception('Session expired. Please login again.');
    } else {
      throw Exception('Failed to submit call: ${response.statusCode}');
    }
  }

  // --- ADMIN (optional) ---
  static Future<Map<String, dynamic>> getAdminSettings() async {
    final response = await http.get(
      Uri.parse('$_baseUrl/admin/settings'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success'] == true) return data['data'];
      throw Exception(data['message'] ?? 'Failed to load settings');
    } else if (response.statusCode == 401) {
      await ConfigService.clearAuthData();
      throw Exception('Session expired. Please login again.');
    } else {
      throw Exception('Failed to load settings: ${response.statusCode}');
    }
  }
}