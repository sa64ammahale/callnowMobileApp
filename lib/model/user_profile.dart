import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:callnow_new/services/config_service.dart';

class UserProfile {
  final int id;
  final String name;
  final String username;
  final String email;
  final String mobile;
  final String role;
  final String companyName;
  final String teamName;
  final String department;
  final String joinDate;
  final String? profilePhoto;
  final String? profilePhotoUrl;
  final String? avatarUrl;
  final String? profilePicture;
  final String? profilePictureUrl;

  UserProfile({
    required this.id,
    required this.name,
    required this.username,
    required this.email,
    required this.mobile,
    required this.role,
    required this.companyName,
    required this.teamName,
    required this.department,
    required this.joinDate,
    this.profilePhoto,
    this.profilePhotoUrl,
    this.avatarUrl,
    this.profilePicture,
    this.profilePictureUrl,
  });

  static String _extractString(dynamic val) {
    if (val == null) return '';
    if (val is List) {
      if (val.isEmpty) return '';
      return val.first.toString().trim();
    }
    final s = val.toString().trim();
    if (s == '[]' || s == 'null' || s == '<null>') return '';
    return s;
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> user = (json['user'] is Map)
        ? Map<String, dynamic>.from(json['user'])
        : (json['profile'] is Map)
            ? Map<String, dynamic>.from(json['profile'])
            : json;

    // Resolve ID
    final rawId = user['id'] ?? user['user_id'] ?? user['agent_id'];
    final id = int.tryParse(rawId?.toString() ?? '0') ?? 0;

    // Resolve Name
    String name = _extractString(user['name']);
    if (name.isEmpty) name = _extractString(user['full_name']);
    if (name.isEmpty) name = _extractString(user['display_name']);

    // Resolve Username / Login ID
    String username = _extractString(user['username']);
    if (username.isEmpty) username = _extractString(user['login_id']);

    // Resolve Email
    String email = '';
    for (final k in ['email', 'user_email', 'email_address', 'mail']) {
      final candidate = _extractString(user[k]);
      if (candidate.isNotEmpty && candidate.contains('@')) {
        email = candidate;
        break;
      }
    }
    if (email.isEmpty && username.contains('@')) {
      email = username;
    }

    // Resolve Mobile / Phone
    String mobile = '';
    for (final k in [
      'mobile',
      'phone',
      'phone_number',
      'mobile_no',
      'mobile_number',
      'contact_number',
      'contact_no',
    ]) {
      final candidate = _extractString(user[k]);
      if (candidate.replaceAll(RegExp(r'\D'), '').length >= 7) {
        mobile = candidate;
        break;
      }
    }

    // Role
    final rawRole = _extractString(user['role']);
    final role = rawRole.isNotEmpty ? rawRole.toUpperCase() : 'TELECALLER';

    // Company
    String company = _extractString(user['company_name']);
    if (company.isEmpty) company = _extractString(user['company']);
    if (company.isEmpty) company = 'CallNow CRM';

    // Team
    String team = _extractString(user['team_name']);
    if (team.isEmpty) team = _extractString(user['team']);

    // Department
    String dept = _extractString(user['department']);
    if (dept.isEmpty) dept = _extractString(user['branch']);
    if (dept.isEmpty) dept = _extractString(user['division']);
    if (dept.isEmpty && team.isNotEmpty) dept = team;

    // Join date
    String joinDate = _extractString(user['join_date']);
    if (joinDate.isEmpty) joinDate = _extractString(user['created_at']);
    if (joinDate.isEmpty) joinDate = _extractString(user['registered_at']);

    // Profile photo mappings
    final rawPhoto = _extractString(user['profile_photo']);
    String photoUrlStr = _extractString(user['profile_photo_url']);
    if (photoUrlStr.isEmpty) photoUrlStr = _extractString(user['avatar_url']);
    if (photoUrlStr.isEmpty) photoUrlStr = _extractString(user['profile_picture_url']);
    if (photoUrlStr.isEmpty) photoUrlStr = _extractString(user['photo']);

    final avatarUrlStr = _extractString(user['avatar_url']).isNotEmpty
        ? _extractString(user['avatar_url'])
        : (photoUrlStr.isNotEmpty ? photoUrlStr : null);

    final picUrlStr = _extractString(user['profile_picture_url']).isNotEmpty
        ? _extractString(user['profile_picture_url'])
        : (photoUrlStr.isNotEmpty ? photoUrlStr : null);

    final profilePicture = _extractString(user['profile_picture']).isNotEmpty
        ? _extractString(user['profile_picture'])
        : null;

    // Normalization of photo URL if relative (e.g. /uploads/... or /callnowCRM/uploads/...)
    if (photoUrlStr.isNotEmpty && photoUrlStr.startsWith('/') && !photoUrlStr.startsWith('//')) {
      final base = ConfigService.baseUrl.replaceAll(RegExp(r'/api.*'), '').replaceAll(RegExp(r'/+$'), '');
      if (base.isNotEmpty) {
        final baseUri = Uri.tryParse(base);
        if (baseUri != null && baseUri.path.isNotEmpty && photoUrlStr.startsWith(baseUri.path)) {
          final origin = '${baseUri.scheme}://${baseUri.authority}';
          photoUrlStr = '$origin$photoUrlStr';
        } else {
          photoUrlStr = '$base$photoUrlStr';
        }
      }
    }

    // Rewrite localhost or 127.0.0.1 to server base host if configured
    if (photoUrlStr.isNotEmpty && (photoUrlStr.startsWith('http://localhost') || photoUrlStr.startsWith('http://127.0.0.1'))) {
      try {
        final uri = Uri.parse(photoUrlStr);
        final baseUri = Uri.parse(ConfigService.baseUrl);
        if (baseUri.host.isNotEmpty && baseUri.host != 'localhost' && baseUri.host != '127.0.0.1') {
          photoUrlStr = uri.replace(
            scheme: baseUri.scheme,
            host: baseUri.host,
            port: baseUri.hasPort ? baseUri.port : (baseUri.scheme == 'https' ? 443 : 80),
          ).toString();
        }
      } catch (_) {}
    }

    final photoUrl = photoUrlStr.isNotEmpty ? photoUrlStr : null;

    if (name.isEmpty) {
      name = username.isNotEmpty ? username : 'Telecaller';
    }
    if (username.isEmpty) {
      username = email.isNotEmpty ? email : name.toLowerCase().replaceAll(' ', '.');
    }

    return UserProfile(
      id: id,
      name: name,
      username: username,
      email: email,
      mobile: mobile,
      role: role,
      companyName: company,
      teamName: team,
      department: dept,
      joinDate: joinDate,
      profilePhoto: rawPhoto.isNotEmpty ? rawPhoto : null,
      profilePhotoUrl: photoUrl,
      avatarUrl: avatarUrlStr,
      profilePicture: profilePicture,
      profilePictureUrl: picUrlStr,
    );
  }

  /// Helper to obtain an ImageProvider for avatars supporting both Network and Base64 images
  ImageProvider? get avatarImageProvider {
    final url = profilePhotoUrl ?? profilePictureUrl ?? avatarUrl;
    if (url != null && url.isNotEmpty) {
      if (url.startsWith('http://') || url.startsWith('https://')) {
        return NetworkImage(url);
      }
      if (url.startsWith('data:image/')) {
        return _decodeBase64Image(url);
      }
    }
    if (profilePicture != null && profilePicture!.isNotEmpty) {
      return _decodeBase64Image(profilePicture!);
    }
    return null;
  }

  static ImageProvider? _decodeBase64Image(String raw) {
    try {
      String clean = raw;
      if (clean.contains(',')) {
        clean = clean.split(',').last;
      }
      clean = clean.replaceAll(RegExp(r'\s+'), '');
      return MemoryImage(base64Decode(clean));
    } catch (_) {
      return null;
    }
  }

  String get displayEmail =>
      email.isNotEmpty ? email : 'Not provided on server';

  String get displayMobile =>
      mobile.isNotEmpty ? mobile : 'Not provided on server';

  String get displayDepartment => department.isNotEmpty
      ? department
      : (teamName.isNotEmpty ? teamName : 'Telecalling Operations');

  String get displayId => id > 0 ? '#$id' : 'N/A';

  bool get hasEmail => email.isNotEmpty && email.contains('@');

  bool get hasMobile =>
      mobile.isNotEmpty && mobile.replaceAll(RegExp(r'\D'), '').length >= 7;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'username': username,
        'email': email,
        'mobile': mobile,
        'role': role,
        'company_name': companyName,
        'team_name': teamName,
        'department': department,
        'join_date': joinDate,
        'profile_photo': profilePhoto,
        'profile_photo_url': profilePhotoUrl,
        'avatar_url': avatarUrl ?? profilePhotoUrl,
        'profile_picture': profilePicture,
        'profile_picture_url': profilePictureUrl ?? profilePhotoUrl,
      };
}
