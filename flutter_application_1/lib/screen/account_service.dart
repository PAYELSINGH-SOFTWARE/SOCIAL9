import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AccountService {
  static const String baseUrl = 'https://social9-1.onrender.com';

  static Future<Map<String, String>> _headers() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');

    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty)
        'Authorization': 'Bearer $token',
    };
  }

  // Get connected social media accounts
  static Future<List<dynamic>> list() async {
    final response = await http.get(
      Uri.parse('$baseUrl/accounts'),
      headers: await _headers(),
    );

    if (response.statusCode != 200) {
      String message = 'Could not load connected accounts';

      try {
        final body = jsonDecode(response.body);
        message = body['detail'] ?? message;
      } catch (_) {}

      throw Exception(message);
    }

    return jsonDecode(response.body) as List<dynamic>;
  }

  // Get authorization URL for connecting an account
  static Future<String> authorizationUrl(String provider) async {
    final response = await http.post(
      Uri.parse('$baseUrl/accounts/$provider/authorization-url'),
      headers: await _headers(),
    );

    final body = jsonDecode(response.body);

    if (response.statusCode != 200) {
      throw Exception(
        body['detail'] ?? 'Could not begin connection',
      );
    }

    return body['authorization_url'] as String;
  }

  // Start Social9 login with a social provider
  static Future<Map<String, dynamic>> startSocialLogin(
    String provider,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/accounts/$provider/login-url'),
      headers: {
        'Content-Type': 'application/json',
      },
    );

    Map<String, dynamic> body;

    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw Exception(
        'Invalid response from Social9 server',
      );
    }

    if (response.statusCode != 200) {
      throw Exception(
        body['detail'] ?? 'Social login is unavailable',
      );
    }

    if (!body.containsKey('authorization_url')) {
      throw Exception(
        'LinkedIn authorization URL was not returned',
      );
    }

    if (!body.containsKey('attempt_id')) {
      throw Exception(
        'Social login attempt ID was not returned',
      );
    }

    return body;
  }

  // Check whether social login has completed
  static Future<Map<String, dynamic>> socialLoginStatus(
    String attemptId,
  ) async {
    final response = await http.get(
      Uri.parse(
        '$baseUrl/accounts/login-status/$attemptId',
      ),
    );

    Map<String, dynamic> body;

    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw Exception(
        'Invalid response from Social9 server',
      );
    }

    if (response.statusCode != 200) {
      throw Exception(
        body['detail'] ?? 'Could not complete social login',
      );
    }

    return body;
  }
}
