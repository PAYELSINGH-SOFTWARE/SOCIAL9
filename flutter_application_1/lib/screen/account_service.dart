import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AccountService {
  static const baseUrl = 'http://127.0.0.1:8000';

  static Future<Map<String, String>> _headers() async {
    final token = (await SharedPreferences.getInstance()).getString('token');
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<List<dynamic>> list() async {
    final response = await http.get(
      Uri.parse('$baseUrl/accounts'),
      headers: await _headers(),
    );
    if (response.statusCode != 200)
      throw Exception('Could not load connected accounts');
    return jsonDecode(response.body) as List<dynamic>;
  }

  static Future<String> authorizationUrl(String provider) async {
    final response = await http.post(
      Uri.parse('$baseUrl/accounts/$provider/authorization-url'),
      headers: await _headers(),
    );
    final body = jsonDecode(response.body);
    if (response.statusCode != 200)
      throw Exception(body['detail'] ?? 'Could not begin connection');
    return body['authorization_url'] as String;
  }

  static Future<Map<String, dynamic>> startSocialLogin(String provider) async {
    final response = await http.post(
      Uri.parse('$baseUrl/accounts/$provider/login-url'),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200)
      throw Exception(body['detail'] ?? 'Social login is unavailable');
    return body;
  }

  static Future<Map<String, dynamic>> socialLoginStatus(
    String attemptId,
  ) async {
    final response = await http.get(
      Uri.parse('$baseUrl/accounts/login-status/$attemptId'),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200)
      throw Exception(body['detail'] ?? 'Could not complete social login');
    return body;
  }
}
