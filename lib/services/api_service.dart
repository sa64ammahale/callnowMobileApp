import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:callnow_new/services/config_service.dart';
import 'package:callnow_new/services/secure_http_client.dart';
import 'package:callnow_new/model/user_profile.dart';

class ApiService {
  static final http.Client _client = SecureHttpClient(
    requireHttps: true,
    enablePinning: SslPinningConfig.enabled,
  );

  static String get _baseUrl {
    String url = ConfigService.baseUrl.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (Uri.parse(url).scheme != 'https') {
      debugPrint('[ApiService] WARNING: Insecure base URL scheme (not HTTPS): $url');
    }
    return url;
  }
  static String? get _token => ConfigService.token;

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  // --- SERVER DIAGNOSTICS ---
  static Future<Map<String, dynamic>> testConnection(String candidateUrl) async {
    String url = candidateUrl.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      return {
        'success': false,
        'message': 'Invalid URL format. Please include http:// or https://'
      };
    }

    final stopwatch = Stopwatch()..start();
    final client = http.Client();
    try {
      final probeUri = Uri.parse('$url/auth/profile');
      final res = await client
          .get(probeUri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 8));
      stopwatch.stop();

      if (res.statusCode >= 200 && res.statusCode < 500) {
        return {
          'success': true,
          'statusCode': res.statusCode,
          'latencyMs': stopwatch.elapsedMilliseconds,
          'message': 'Server reached (${stopwatch.elapsedMilliseconds}ms, HTTP ${res.statusCode})',
        };
      } else {
        return {
          'success': false,
          'statusCode': res.statusCode,
          'latencyMs': stopwatch.elapsedMilliseconds,
          'message': 'Server responded with HTTP ${res.statusCode}',
        };
      }
    } catch (e) {
      stopwatch.stop();
      return {
        'success': false,
        'message': 'Connection failed: ${e.toString().replaceFirst('Exception: ', '')}',
      };
    } finally {
      client.close();
    }
  }

  // --- AUTH ---
  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    // Try both email and username field names
    final fieldNames = ['email', 'username'];
    for (final fieldName in fieldNames) {
      final url = '$_baseUrl/auth/login';

      final body = {fieldName: email, 'password': password};
      final response = await _client.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: json.encode(body),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final token = data['data']['token'];
          final userData = data['data']['user'] is Map
              ? Map<String, dynamic>.from(data['data']['user'])
              : <String, dynamic>{};
          await ConfigService.saveAuthData(token, userData, fallbackEmail: email);
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
    final candidateEndpoints = [
      '$_baseUrl/auth/me',
      '$_baseUrl/auth/profile',
      '$_baseUrl/me',
      '$_baseUrl/profile',
      '$_baseUrl/telecaller/profile',
    ];

    http.Response? lastResponse;

    for (final url in candidateEndpoints) {
      try {
        final response = await _client.get(
          Uri.parse(url),
          headers: _headers,
        );
        lastResponse = response;

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['success'] == true) {
            final raw = data['data'];
            Map<String, dynamic> profileData = raw is Map ? Map<String, dynamic>.from(raw) : {};
            if (profileData.containsKey('user') && profileData['user'] is Map) {
              final nested = Map<String, dynamic>.from(profileData['user'] as Map);
              nested.forEach((k, v) => profileData.putIfAbsent(k, () => v));
            }
            if (profileData.containsKey('profile') && profileData['profile'] is Map) {
              final nested = Map<String, dynamic>.from(profileData['profile'] as Map);
              nested.forEach((k, v) => profileData.putIfAbsent(k, () => v));
            }
            if (_token != null && _token!.isNotEmpty) {
              await ConfigService.saveAuthData(_token!, profileData);
            }
            return ConfigService.userData ?? profileData;
          }
        } else if (response.statusCode == 401) {
          await ConfigService.clearAuthData();
          throw Exception('Session expired. Please login again.');
        }
      } catch (e) {
        if (e.toString().contains('Session expired')) rethrow;
      }
    }

    if (lastResponse != null) {
      if (lastResponse.statusCode == 401) {
        await ConfigService.clearAuthData();
        throw Exception('Session expired. Please login again.');
      }
      throw Exception('Failed to get profile: ${lastResponse.statusCode}');
    }
    throw Exception('Failed to get profile: Could not reach server');
  }

  /// Get strongly typed user profile
  static Future<UserProfile> getUserProfile() async {
    final data = await getProfile();
    return UserProfile.fromJson(data);
  }

  /// Request Password Reset OTP to registered email
  static Future<Map<String, dynamic>> sendPasswordResetOtp(String email) async {
    final cleanEmail = email.trim();
    if (cleanEmail.isEmpty) {
      throw Exception('Email address is required');
    }

    final endpoints = [
      '$_baseUrl/auth/forgot-password',
      '$_baseUrl/auth/send-otp',
      '$_baseUrl/auth/reset-password/otp',
      '$_baseUrl/auth/password/email-otp',
    ];

    final body = json.encode({'email': cleanEmail});
    http.Response? lastResponse;

    for (final url in endpoints) {
      try {
        final res = await _client.post(
          Uri.parse(url),
          headers: _headers,
          body: body,
        );
        lastResponse = res;
        if (res.statusCode == 200 || res.statusCode == 201) {
          final data = json.decode(res.body);
          if (data is Map<String, dynamic>) {
            return data;
          }
          return {'success': true, 'message': 'OTP sent to $cleanEmail'};
        }
      } catch (_) {
        // Try next endpoint fallback
      }
    }

    if (lastResponse != null) {
      try {
        final data = json.decode(lastResponse.body);
        final msg = data['message'] ?? data['error']?['message'] ?? 'Failed to send OTP';
        throw Exception(msg);
      } catch (e) {
        if (e is Exception) rethrow;
        throw Exception('Failed to send OTP: ${lastResponse.statusCode}');
      }
    }
    throw Exception('Could not reach password reset service. Please check your connection.');
  }

  /// Verify OTP and reset password
  static Future<Map<String, dynamic>> resetPasswordWithOtp({
    required String email,
    required String otp,
    required String newPassword,
  }) async {
    final cleanEmail = email.trim();
    final cleanOtp = otp.trim();
    final cleanPass = newPassword.trim();

    if (cleanEmail.isEmpty) throw Exception('Email address is required');
    if (cleanOtp.isEmpty) throw Exception('OTP verification code is required');
    if (cleanPass.length < 6) throw Exception('Password must be at least 6 characters');

    final endpoints = [
      '$_baseUrl/auth/reset-password',
      '$_baseUrl/auth/verify-otp-reset',
      '$_baseUrl/auth/password/reset',
    ];

    final body = json.encode({
      'email': cleanEmail,
      'otp': cleanOtp,
      'token': cleanOtp,
      'code': cleanOtp,
      'password': cleanPass,
      'new_password': cleanPass,
      'password_confirmation': cleanPass,
    });

    http.Response? lastResponse;

    for (final url in endpoints) {
      try {
        final res = await _client.post(
          Uri.parse(url),
          headers: _headers,
          body: body,
        );
        lastResponse = res;
        if (res.statusCode == 200 || res.statusCode == 201) {
          final data = json.decode(res.body);
          if (data is Map<String, dynamic>) {
            return data;
          }
          return {'success': true, 'message': 'Password reset successfully'};
        }
      } catch (_) {
        // Try next fallback
      }
    }

    if (lastResponse != null) {
      try {
        final data = json.decode(lastResponse.body);
        final msg = data['message'] ?? data['error']?['message'] ?? 'Failed to reset password';
        throw Exception(msg);
      } catch (e) {
        if (e is Exception) rethrow;
        throw Exception('Failed to reset password: ${lastResponse.statusCode}');
      }
    }
    throw Exception('Could not reset password. Please check your network and try again.');
  }

  /// Update Agent Profile Details (Name, Company, etc.)
  /// Note: Server strictly restricts modifying email and mobile number.
  static Future<Map<String, dynamic>> updateProfile({
    required String name,
    String? companyName,
    String? photoBase64,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      throw Exception('Name cannot be empty');
    }
    final body = <String, dynamic>{
      'name': cleanName,
      if (companyName != null && companyName.trim().isNotEmpty)
        'company_name': companyName.trim(),
      if (photoBase64 != null && photoBase64.isNotEmpty)
        'profile_photo_base64': photoBase64,
    };
    final response = await _client.post(
      Uri.parse('$_baseUrl/auth/profile'),
      headers: _headers,
      body: json.encode(body),
    );
    final data = json.decode(response.body);
    if (response.statusCode == 200 && data['success'] == true) {
      final updatedUser = data['data'] != null && data['data']['user'] is Map
          ? Map<String, dynamic>.from(data['data']['user'])
          : (data['data'] is Map ? Map<String, dynamic>.from(data['data']) : <String, dynamic>{});
      if (_token != null) {
        await ConfigService.saveAuthData(_token!, updatedUser);
      }
      return updatedUser;
    }
    final errorMsg = data['error']?['message'] ??
        data['message'] ??
        'Failed to update profile (${response.statusCode})';
    throw Exception(errorMsg);
  }

  /// Change Password while logged in
  static Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    if (currentPassword.isEmpty) throw Exception('Current password is required');
    if (newPassword.length < 6) throw Exception('New password must be at least 6 characters');
    if (newPassword != confirmPassword) throw Exception('Passwords do not match');
    final response = await _client.post(
      Uri.parse('$_baseUrl/auth/change-password'),
      headers: _headers,
      body: json.encode({
        'current_password': currentPassword,
        'new_password': newPassword,
        'confirm_password': confirmPassword,
      }),
    );
    final data = json.decode(response.body);
    if (response.statusCode == 200 && data['success'] == true) {
      return;
    }
    final errorMsg = data['error']?['message'] ??
        data['message'] ??
        'Failed to change password (${response.statusCode})';
    throw Exception(errorMsg);
  }

  static Future<void> refreshToken() async {
    final response = await _client.get(
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
    try {
      if (_token != null && _token!.isNotEmpty) {
        await _client.post(
          Uri.parse('$_baseUrl/auth/logout'),
          headers: _headers,
        ).timeout(const Duration(seconds: 4));
      }
    } catch (e) {
      debugPrint('[ApiService] Backend logout notification error: $e');
    } finally {
      await ConfigService.clearAuthData();
    }
  }

  static Map<String, dynamic> _toMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }

  // --- TELECALLER ---
  static Future<Map<String, dynamic>> getDashboardStats() async {
    final response = await _client.get(
      Uri.parse('$_baseUrl/telecaller/dashboard'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success'] == true) return _toMap(data['data']);
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
    final response = await _client.get(
      Uri.parse('$_baseUrl/telecaller/batch-leads?limit=$limit'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success'] == true && data['data'] != null) {
        final raw = data['data'];
        final dynamic listData = raw is Map ? raw['leads'] : raw;
        if (listData is List) {
          return listData
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
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
    final response = await _client.get(
      Uri.parse('$_baseUrl/telecaller/next-call'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success'] == true) return _toMap(data['data']);
      throw Exception(data['message'] ?? 'No pending calls');
    } else if (response.statusCode == 401) {
      await ConfigService.clearAuthData();
      throw Exception('Session expired. Please login again.');
    } else {
      throw Exception('Failed to get next call: ${response.statusCode}');
    }
  }

  /// Create a new CRM lead from mobile app
  static Future<Map<String, dynamic>> createLead({
    required String name,
    required String mobile,
    String? company,
    String? package,
    String? otherInfo,
    String? status,
    String? loanType,
    String? stage,
    String? priority,
    String? loginBank,
    String? nextFollowup,
    String source = 'MAIN',
    String? netSalary,
    String? salaryAccount,
    String? bankName,
    int? clientContactId,
  }) async {
    final payload = <String, dynamic>{
      'name': name.trim(),
      'mobile': mobile.trim(),
      'company': company?.trim() ?? '',
      'package': package?.trim() ?? '',
      'other_info': otherInfo?.trim() ?? '',
      'status': status?.trim() ?? 'LEAD',
      'source': source,
    };
    if (loanType != null) payload['loan_type'] = loanType;
    if (stage != null) payload['lead_stage'] = stage;
    if (priority != null) payload['priority'] = priority;
    if (loginBank != null) payload['login_bank_name'] = loginBank;
    if (nextFollowup != null) payload['next_followup_at'] = nextFollowup;
    if (netSalary != null) payload['net_salary'] = netSalary;
    if (salaryAccount != null) payload['salary_account'] = salaryAccount;
    if (bankName != null) payload['bank_name'] = bankName;
    if (clientContactId != null) payload['client_contact_id'] = clientContactId;

    final response = await _client.post(
      Uri.parse('$_baseUrl/telecaller/leads'),
      headers: _headers,
      body: json.encode(payload),
    );

    final data = json.decode(response.body);
    if (response.statusCode == 200 || response.statusCode == 201) {
      if (data['success'] == true) return _toMap(data['data']);
    } else if (response.statusCode == 422) {
      final msg = data['message'] ?? data['error']?['message'] ?? 'Number is registered on Do Not Call / DND list';
      throw Exception(msg);
    } else if (response.statusCode == 401) {
      await ConfigService.clearAuthData();
      throw Exception('Session expired. Please login again.');
    }
    throw Exception(data['message'] ?? data['error']?['message'] ?? 'Failed to create lead');
  }

  /// Fetch created / assigned leads with filters & pagination
  static Future<Map<String, dynamic>> getCreatedLeads({
    int page = 1,
    int limit = 30,
    String? search,
    String? status,
    String? source,
    String? period,
    String? dateFrom,
    String? dateTo,
    String? scope,
    int? teamId,
    int? userId,
  }) async {
    final queryParams = <String, String>{
      'page': page.toString(),
      'limit': limit.toString(),
    };
    if (search != null && search.isNotEmpty) queryParams['search'] = search;
    if (status != null && status.isNotEmpty && status != 'all') queryParams['status'] = status;
    if (source != null && source.isNotEmpty && source != 'all') queryParams['source'] = source;
    if (period != null && period.isNotEmpty && period != 'all') queryParams['period'] = period;
    if (dateFrom != null && dateFrom.isNotEmpty) queryParams['date_from'] = dateFrom;
    if (dateTo != null && dateTo.isNotEmpty) queryParams['date_to'] = dateTo;
    if (scope != null && scope.isNotEmpty) queryParams['scope'] = scope;
    if (teamId != null && teamId > 0) queryParams['team_id'] = teamId.toString();
    if (userId != null && userId > 0) queryParams['user_id'] = userId.toString();

    final uri = Uri.parse('$_baseUrl/telecaller/leads').replace(queryParameters: queryParams);
    final response = await _client.get(uri, headers: _headers);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success'] == true && data['data'] != null) {
        return _toMap(data['data']);
      }
      return {'leads': [], 'pagination': {}};
    } else if (response.statusCode == 401) {
      await ConfigService.clearAuthData();
      throw Exception('Session expired. Please login again.');
    } else {
      throw Exception('Failed to get leads: ${response.statusCode}');
    }
  }

  /// Fetch accessible teams and officers for TL & Manager leads filtering
  static Future<Map<String, dynamic>> getTeamOfficers() async {
    final uri = Uri.parse('$_baseUrl/telecaller/team-officers');
    final response = await _client.get(uri, headers: _headers);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success'] == true && data['data'] != null) {
        return _toMap(data['data']);
      }
      return {'teams': [], 'officers': []};
    } else if (response.statusCode == 401) {
      await ConfigService.clearAuthData();
      throw Exception('Session expired. Please login again.');
    } else {
      throw Exception('Failed to get team officers: ${response.statusCode}');
    }
  }

  /// Update an existing lead
  static Future<void> updateLead({
    required int id,
    required String source,
    String? name,
    String? company,
    String? package,
    String? otherInfo,
    String? status,
    String? nextFollowupAt,
  }) async {
    final payload = <String, dynamic>{};
    if (name != null) payload['name'] = name;
    if (company != null) payload['company'] = company;
    if (package != null) payload['package'] = package;
    if (otherInfo != null) payload['other_info'] = otherInfo;
    if (status != null) {
      payload['status'] = status;
      payload['lead_status_new'] = status;
    }
    if (nextFollowupAt != null) payload['next_followup_at'] = nextFollowupAt;

    final response = await _client.put(
      Uri.parse('$_baseUrl/telecaller/leads/$id?source=$source'),
      headers: _headers,
      body: json.encode(payload),
    );

    final data = json.decode(response.body);
    if (response.statusCode != 200 || data['success'] != true) {
      throw Exception(data['message'] ?? 'Failed to update lead');
    }
  }

  /// Update CRM Lead Stage & Pipeline status
  static Future<void> updateLeadStage({
    required int id,
    required String newStage,
    String? remarks,
    String? nextFollowupAt,
    String source = 'MAIN',
  }) async {
    if (id <= 0) {
      throw Exception('Invalid lead ID ($id). Cannot update stage.');
    }

    final payload = <String, dynamic>{
      'status': newStage,
      'lead_status_new': newStage,
    };
    if (remarks != null && remarks.isNotEmpty) payload['other_info'] = remarks;
    if (nextFollowupAt != null) payload['next_followup'] = nextFollowupAt;

    debugPrint(
      '[ApiService] updateLeadStage REQUEST: POST $_baseUrl/telecaller/leads/$id/stage?source=$source',
    );
    debugPrint('[ApiService] updateLeadStage REQUEST BODY: ${json.encode(payload)}');

    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/telecaller/leads/$id/stage?source=$source'),
        headers: _headers,
        body: json.encode(payload),
      );
      debugPrint(
        '[ApiService] updateLeadStage RESPONSE: ${response.statusCode} - ${response.body}',
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('[ApiService] updateLeadStage primary succeeded for lead $id');
        return;
      }
    } catch (e) {
      debugPrint('[ApiService] updateLeadStage primary failed: $e');
    }

    // Fallback to updateLead endpoint with stage-specific fields
    debugPrint(
      '[ApiService] updateLeadStage falling back to updateLead for lead $id',
    );
    await updateLead(
      id: id,
      source: source,
      status: newStage,
      otherInfo: remarks,
      nextFollowupAt: nextFollowupAt,
    );
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
    final response = await _client.get(uri, headers: _headers);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success'] == true) return _toMap(data['data']);
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
    final response = await _client.get(uri, headers: _headers);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success'] == true) return _toMap(data['data']);
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
    final response = await _client.get(uri, headers: _headers);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success'] == true) return _toMap(data['data']);
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
    Map<String, dynamic>? loanQualification,
    String? phoneNumber,
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
    if (loanQualification != null) body['loan_qualification'] = loanQualification;
    if (phoneNumber != null && phoneNumber.trim().isNotEmpty) {
      body['phone_number'] = phoneNumber.trim();
      body['mobile'] = phoneNumber.trim();
    }

    final response = await _client.post(
      Uri.parse('$_baseUrl/telecaller/calls/$callId/complete'),
      headers: _headers,
      body: json.encode(body),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success'] == true) return _toMap(data['data']);
      throw Exception(data['message'] ?? 'Failed to submit call result');
    } else if (response.statusCode == 401) {
      await ConfigService.clearAuthData();
      throw Exception('Session expired. Please login again.');
    } else {
      String errMsg = 'Failed to submit call result: ${response.statusCode}';
      try {
        final errData = json.decode(response.body);
        if (errData is Map && errData['message'] != null) {
          errMsg = errData['message'].toString();
        } else if (errData is Map && errData['error'] != null) {
          errMsg = errData['error'].toString();
        }
      } catch (_) {}
      throw Exception(errMsg);
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
    Map<String, dynamic>? loanQualification,
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
    if (loanQualification != null) body['loan_qualification'] = loanQualification;

    final response = await _client.post(
      Uri.parse('$_baseUrl/telecaller/submit_call.php'),
      headers: _headers,
      body: json.encode(body),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success'] == true) return _toMap(data['data']);
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
    final response = await _client.get(
      Uri.parse('$_baseUrl/admin/settings'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success'] == true) return _toMap(data['data']);
      throw Exception(data['message'] ?? 'Failed to load settings');
    } else if (response.statusCode == 401) {
      await ConfigService.clearAuthData();
      throw Exception('Session expired. Please login again.');
    } else {
      throw Exception('Failed to load settings: ${response.statusCode}');
    }
  }

  // --- FOLLOW-UP SYNCHRONIZATION ---
  static Future<Map<String, dynamic>> fetchServerFollowups({
    String status = 'OPEN',
    String due = 'all',
    int page = 1,
    int limit = 50,
    String? period,
    String? dateFrom,
    String? dateTo,
    String scope = 'mine',
    int? userId,
  }) async {
    final queryParams = <String, String>{
      'status': status,
      'due': due,
      'page': page.toString(),
      'limit': limit.toString(),
      'scope': scope,
    };
    if (userId != null && userId > 0) queryParams['user_id'] = userId.toString();
    if (period != null && period.isNotEmpty && period != 'all') queryParams['period'] = period;
    if (dateFrom != null && dateFrom.isNotEmpty) queryParams['date_from'] = dateFrom;
    if (dateTo != null && dateTo.isNotEmpty) queryParams['date_to'] = dateTo;

    final uri = Uri.parse('$_baseUrl/telecaller/follow-ups').replace(queryParameters: queryParams);

    final response = await _client.get(uri, headers: _headers);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success'] == true) return _toMap(data['data']);
      throw Exception(data['message'] ?? 'Failed to load follow-ups');
    } else if (response.statusCode == 401) {
      await ConfigService.clearAuthData();
      throw Exception('Session expired. Please login again.');
    } else {
      throw Exception('Failed to load follow-ups: ${response.statusCode}');
    }
  }

  static Future<Map<String, dynamic>> createServerFollowup({
    int? leadId,
    int? contactId,
    int? clientContactId,
    String contactSource = 'MAIN',
    required dynamic followupAt,
    String? note,
    String? customerName,
    String? phoneNumber,
  }) async {
    final DateTime scheduled = followupAt is DateTime
        ? followupAt
        : (DateTime.tryParse(followupAt.toString()) ?? DateTime.now());
    final int? cId = clientContactId ?? contactId;
    final body = <String, dynamic>{
      'followup_at': scheduled.toIso8601String().replaceAll('T', ' ').substring(0, 19),
      'contact_source': contactSource,
    };
    if (leadId != null) body['lead_id'] = leadId;
    if (cId != null) body['client_contact_id'] = cId;
    if (note != null && note.isNotEmpty) body['note'] = note;
    if (customerName != null && customerName.trim().isNotEmpty) {
      body['customer_name'] = customerName.trim();
    }
    if (phoneNumber != null && phoneNumber.trim().isNotEmpty) {
      body['phone_number'] = phoneNumber.trim();
      body['customer_mobile'] = phoneNumber.trim();
    }

    final response = await _client.post(
      Uri.parse('$_baseUrl/telecaller/follow-ups'),
      headers: _headers,
      body: json.encode(body),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success'] == true) return _toMap(data['data']);
      throw Exception(data['message'] ?? 'Failed to create follow-up');
    } else if (response.statusCode == 401) {
      await ConfigService.clearAuthData();
      throw Exception('Session expired. Please login again.');
    } else {
      throw Exception('Failed to create follow-up: ${response.statusCode}');
    }
  }

  static Future<Map<String, dynamic>> completeServerFollowup(int followupId) async {
    final response = await _client.put(
      Uri.parse('$_baseUrl/telecaller/follow-ups/$followupId/complete'),
      headers: _headers,
      body: json.encode({}),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success'] == true) return _toMap(data['data']);
      throw Exception(data['message'] ?? 'Failed to complete follow-up');
    } else if (response.statusCode == 401) {
      await ConfigService.clearAuthData();
      throw Exception('Session expired. Please login again.');
    } else {
      throw Exception('Failed to complete follow-up: ${response.statusCode}');
    }
  }

  static Future<Map<String, dynamic>> rescheduleServerFollowup(
    int followupId,
    DateTime newTime,
    String? note,
  ) async {
    final body = <String, dynamic>{
      'followup_at': newTime.toIso8601String().replaceAll('T', ' ').substring(0, 19),
    };
    if (note != null && note.isNotEmpty) body['note'] = note;

    final response = await _client.put(
      Uri.parse('$_baseUrl/telecaller/follow-ups/$followupId/reschedule'),
      headers: _headers,
      body: json.encode(body),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success'] == true) return _toMap(data['data']);
      throw Exception(data['message'] ?? 'Failed to reschedule follow-up');
    } else if (response.statusCode == 401) {
      await ConfigService.clearAuthData();
      throw Exception('Session expired. Please login again.');
    } else {
      throw Exception('Failed to reschedule follow-up: ${response.statusCode}');
    }
  }

  /// Lookup a contact by phone number in CRM (checks Leads, Main Database, and Temp Database)
  static Future<Map<String, dynamic>?> lookupContact(String phoneNumber) async {
    final clean = phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
    if (clean.length < 10) return null;
    final last10 = clean.length > 10 ? clean.substring(clean.length - 10) : clean;

    try {
      final response = await _client.get(
        Uri.parse('$_baseUrl/telecaller/lookup-contact?phone=$last10'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['data'] is Map) {
          return Map<String, dynamic>.from(data['data']);
        }
      }
    } catch (e) {
      debugPrint('[ApiService] lookupContact error: $e');
    }
    return null;
  }
}