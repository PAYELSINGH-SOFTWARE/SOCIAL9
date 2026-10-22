import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'workspace_session.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient._();

  static const String baseUrl = String.fromEnvironment(
    'SOCIAL9_API_URL',
    defaultValue: 'https://social9-backend-ghqu.onrender.com',
  );

  static Future<String?> token() async =>
      (await SharedPreferences.getInstance()).getString('token');

  static Future<Map<String, String>> headers({
    bool authenticated = true,
  }) async {
    final accessToken = authenticated ? await token() : null;
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (accessToken != null && accessToken.isNotEmpty)
        'Authorization': 'Bearer $accessToken',
      if (authenticated && WorkspaceSession.brandId.value != null)
        'X-Brand-ID': '${WorkspaceSession.brandId.value}',
    };
  }

  static Future<dynamic> get(String path) => _request('GET', path);

  static Future<dynamic> post(
    String path, {
    Object? body,
    bool authenticated = true,
  }) => _request('POST', path, body: body, authenticated: authenticated);

  static Future<dynamic> patch(String path, {Object? body}) =>
      _request('PATCH', path, body: body);

  static Future<dynamic> put(String path, {Object? body}) =>
      _request('PUT', path, body: body);

  static Future<void> delete(String path) async {
    await _request('DELETE', path);
  }

  static Future<dynamic> _request(
    String method,
    String path, {
    Object? body,
    bool authenticated = true,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    try {
      final requestHeaders = await headers(authenticated: authenticated);
      final encoded = body == null ? null : jsonEncode(body);
      final request = switch (method) {
        'POST' => http.post(uri, headers: requestHeaders, body: encoded),
        'PATCH' => http.patch(uri, headers: requestHeaders, body: encoded),
        'PUT' => http.put(uri, headers: requestHeaders, body: encoded),
        'DELETE' => http.delete(uri, headers: requestHeaders),
        _ => http.get(uri, headers: requestHeaders),
      };
      final response = await request.timeout(const Duration(seconds: 75));

      if (response.statusCode == 204) return null;
      dynamic decoded;
      try {
        decoded = response.body.isEmpty ? null : jsonDecode(response.body);
      } catch (_) {
        decoded = null;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (response.statusCode == 401 && authenticated) {
          await WorkspaceSession.clear();
          WorkspaceSession.onExpired?.call();
        }
        var message = 'Something went wrong (${response.statusCode}).';
        if (decoded is Map && decoded['detail'] is String) {
          message = decoded['detail'] as String;
        } else if (decoded is Map && decoded['detail'] is List) {
          message = (decoded['detail'] as List)
              .map((item) => item is Map ? item['msg'] : item)
              .where((item) => item != null)
              .join('. ');
        }
        throw ApiException(message, statusCode: response.statusCode);
      }
      if (decoded == null) {
        throw const ApiException(
          'Social9 returned an invalid response. Please try again.',
        );
      }
      return decoded;
    } on TimeoutException {
      throw const ApiException(
        'The Social9 server took too long to respond. Please try again.',
      );
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException(
        'The Social9 server is unavailable. Check your connection and try again.',
      );
    }
  }
}
