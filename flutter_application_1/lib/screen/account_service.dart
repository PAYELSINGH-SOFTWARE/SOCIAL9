import 'api_config.dart';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AccountService {
  static const String baseUrl = ApiConfig.baseUrl;

  static Future<Map<String, String>> _headers() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(ApiConfig.tokenKey);

    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  // Get connected social media accounts
  static Future<List<dynamic>> list() async {
    final response = await http.get(
      Uri.parse('$baseUrl/social-accounts'),
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

    final connected = jsonDecode(response.body) as List<dynamic>;
    final statusResponse = await http.get(
      Uri.parse('$baseUrl/social-accounts/provider-status'),
      headers: await _headers(),
    );
    if (statusResponse.statusCode != 200) {
      throw Exception('Could not load provider availability');
    }
    final providers = jsonDecode(statusResponse.body) as List<dynamic>;
    return providers.map((provider) {
      final matches = connected.where(
        (account) =>
            account['provider'] == provider['provider'] &&
            account['status'] == 'connected',
      );
      return {
        'provider': provider['provider'],
        'configured': provider['configured'] == true,
        'connected': matches.isNotEmpty,
        'display_name': matches.isEmpty ? null : matches.first['account_name'],
      };
    }).toList();
  }

  // Get authorization URL for connecting an account
  static Future<String> authorizationUrl(String provider) async {
    final response = await http.post(
      Uri.parse('$baseUrl/social-accounts/$provider/connect'),
      headers: await _headers(),
    );

    final body = jsonDecode(response.body);

    if (response.statusCode != 200) {
      throw Exception(body['detail'] ?? 'Could not begin connection');
    }

    return body['authorization_url'] as String;
  }
}
