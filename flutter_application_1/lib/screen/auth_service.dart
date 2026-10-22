import '../core/api_client.dart';

class AuthService {
  static Future<Map<String, dynamic>> login(
    String email,
    String password,
  ) async {
    final value = await ApiClient.post(
      '/auth/login',
      authenticated: false,
      body: {'email': email.trim(), 'password': password},
    );
    return Map<String, dynamic>.from(value as Map);
  }

  static Future<Map<String, dynamic>> signup(
    String name,
    String email,
    String password,
  ) async {
    final value = await ApiClient.post(
      '/auth/signup',
      authenticated: false,
      body: {'name': name.trim(), 'email': email.trim(), 'password': password},
    );
    return Map<String, dynamic>.from(value as Map);
  }

  static Future<String> forgotPassword(String email) async {
    final value =
        await ApiClient.post(
              '/auth/password/forgot',
              authenticated: false,
              body: {'email': email.trim()},
            )
            as Map;
    return value['message']?.toString() ??
        'Password reset instructions are ready.';
  }

  static Future<Map<String, dynamic>> me() async =>
      Map<String, dynamic>.from(await ApiClient.get('/auth/me') as Map);
}
