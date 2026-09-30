class ApiConfig {
  static const String baseUrl = String.fromEnvironment(
    'SOCIAL9_API_URL',
    defaultValue: 'https://social9-backend-ghqu.onrender.com',
  );
  // Scope sessions to the API so tokens from the previous backend are ignored.
  static const String tokenKey = 'social9.token.$baseUrl';
}
