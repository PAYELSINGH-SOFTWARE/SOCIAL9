import 'api_config.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class PostService {
  static const String baseUrl = ApiConfig.baseUrl;
  static Future<Map<String, String>> _headers() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(ApiConfig.tokenKey);
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<http.Response> create({
    required String caption,
    required List<String> platforms,
    List<Map<String, String>> media = const [],
    DateTime? scheduledFor,
    bool publishNow = false,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/posts'),
      headers: await _headers(),
      body: jsonEncode({
        'caption': caption,
        'platforms': platforms,
        'media': media,
        'scheduled_for': scheduledFor?.toUtc().toIso8601String(),
        'post_type':
            media.any(
              (item) => RegExp(
                r'\.(mp4|mov)$',
                caseSensitive: false,
              ).hasMatch(item['name'] ?? ''),
            )
            ? 'video'
            : 'post',
      }),
    );
    if (publishNow && response.statusCode == 201) {
      final post = jsonDecode(response.body) as Map<String, dynamic>;
      return publish(post['id'] as int);
    }
    return response;
  }

  static Future<http.Response> publish(int id) async {
    return http.post(
      Uri.parse('$baseUrl/posts/$id/publish'),
      headers: await _headers(),
    );
  }

  static Future<http.Response> list({String? status}) async {
    final uri = Uri.parse(
      '$baseUrl/posts',
    ).replace(queryParameters: status == null ? null : {'status': status});
    return http.get(uri, headers: await _headers());
  }

  static Future<http.Response> delete(int id) async {
    return http.delete(
      Uri.parse('$baseUrl/posts/$id'),
      headers: await _headers(),
    );
  }
}
