import 'api_config.dart';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AnalyticsService {
  static const String baseUrl = ApiConfig.baseUrl;

  static Future<Map<String, String>> _headers() async {
    final token = (await SharedPreferences.getInstance()).getString(
      ApiConfig.tokenKey,
    );
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

  static Future<Map<String, dynamic>> summary() async {
    final data = await _get('/analytics/summary');
    final overview = Map<String, dynamic>.from(data['overview'] as Map);
    final channels = data['channels'] as List<dynamic>;
    return {
      ...overview,
      'success_rate': overview['publish_success_rate'],
      'posts_by_platform': {
        for (final channel in channels)
          channel['provider'] as String: channel['post_count'],
      },
      'connected_accounts': [
        for (final channel in channels)
          if (channel['connected'] == true) channel['provider'],
      ],
    };
  }
}
