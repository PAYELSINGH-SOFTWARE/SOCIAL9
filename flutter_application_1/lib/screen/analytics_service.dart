import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AnalyticsService {
  static const String baseUrl = "https://social9-1.onrender.com";

  static Future<Map<String, String>> _headers() async {
    final token = (await SharedPreferences.getInstance()).getString('token');
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<Map<String, dynamic>> _get(String path) async {
    final response = await http.get(
      Uri.parse('$baseUrl$path'),
      headers: await _headers(),
    );
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw Exception(
        'Your session has expired. Please log out and log in again.',
      );
    }
    if (response.statusCode != 200) {
      String message = 'Could not load analytics (${response.statusCode})';
      try {
        final body = jsonDecode(response.body);
        if (body is Map && body['detail'] != null) {
          message = body['detail'].toString();
        }
      } catch (_) {}
      throw Exception(message);
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> summary() => _get('/analytics/summary');

  static Future<Map<String, dynamic>> performance() =>
      _get('/analytics/performance');
}

