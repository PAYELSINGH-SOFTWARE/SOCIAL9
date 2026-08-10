import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class PostService {
static const String baseUrl = "https://social9-1.onrender.com";
  static Future<Map<String, String>> _headers() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
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
    return http.post(
      Uri.parse('$baseUrl/posts'),
      headers: await _headers(),
      body: jsonEncode({
        'caption': caption,
        'platforms': platforms,
        'media': media,
        'scheduled_for': scheduledFor?.toUtc().toIso8601String(),
        'publish_now': publishNow,
      }),
    );
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

