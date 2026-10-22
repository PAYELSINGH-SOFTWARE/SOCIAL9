import '../core/api_client.dart';

class AccountService {
  static Future<List<Map<String, dynamic>>> list() async =>
      (await ApiClient.get('/social-accounts') as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

  static Future<List<Map<String, dynamic>>> providerStatus() async =>
      (await ApiClient.get('/social-accounts/provider-status') as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

  static Future<String> authorizationUrl(String provider) async {
    final body =
        await ApiClient.post('/social-accounts/$provider/connect') as Map;
    return body['authorization_url'].toString();
  }

  static Future<void> disconnect(int accountId) =>
      ApiClient.delete('/social-accounts/$accountId');
}
