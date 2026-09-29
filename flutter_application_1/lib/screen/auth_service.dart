import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class AuthService {
  static const String baseUrl = "https://social9-1.onrender.com";

  static Future<http.Response> login(
    String email,
    String password,
  ) {
    return http.post(
      Uri.parse("$baseUrl/auth/login"),
      headers: {
        "Content-Type": "application/json",
      },
      body: jsonEncode({
        "email": email,
        "password": password,
      }),
    ).timeout(
      const Duration(seconds: 60),
      onTimeout: () => throw TimeoutException(
        'The server took too long to respond. Please try again. If you were signing up, try signing in first in case your account was created.',
      ),
    );
  }

  static Future<http.Response> signup(
    String name,
    String email,
    String password,
  ) {
    return http.post(
      Uri.parse("$baseUrl/auth/signup"),
      headers: {
        "Content-Type": "application/json",
      },
      body: jsonEncode({
        "name": name,
        "email": email,
        "password": password,
      }),
    ).timeout(
      const Duration(seconds: 60),
      onTimeout: () => throw TimeoutException(
        'The server took too long to respond. Please try again. If you were signing up, try signing in first in case your account was created.',
      ),
    );
  }
}
