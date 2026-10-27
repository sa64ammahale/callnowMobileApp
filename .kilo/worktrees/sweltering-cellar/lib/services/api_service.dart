import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  static const String baseUrl =
      "https://starsinfotech.in/callnow/FLUTTER_API.php?apicall=";

  static Future<Map<String, dynamic>> login(
      String username, String password) async {
    final response = await http.post(
      Uri.parse("${baseUrl}LOGIN"),
      headers: {"Content-Type": "application/x-www-form-urlencoded"},
      body: {"username": username, "password": password},
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception("Login failed: ${response.statusCode}");
    }
  }

  static Future<Map<String, dynamic>> changePassword(
      String userId, String oldPassword, String newPassword) async {
    final response = await http.post(
      Uri.parse("${baseUrl}RESET_PASSWORD"),
      headers: {"Content-Type": "application/x-www-form-urlencoded"},
      body: {
        "user_id": userId,
        "old_password": oldPassword,
        "new_password": newPassword,
      },
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception("Password change failed: ${response.statusCode}");
    }
  }

  static Future<Map<String, dynamic>> getCompanyList() async {
    final response = await http.get(Uri.parse("${baseUrl}COMPANY_LIST"));

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception("Failed to load companies: ${response.statusCode}");
    }
  }

  static Future<Map<String, dynamic>> getSplashData() async {
    final response = await http.get(Uri.parse("${baseUrl}SPLASH_SCREEN"));

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception("Failed to load splash data: ${response.statusCode}");
    }
  }
}
