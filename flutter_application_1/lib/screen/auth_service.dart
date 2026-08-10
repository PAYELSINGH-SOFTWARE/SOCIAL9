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
    );
  }
}
