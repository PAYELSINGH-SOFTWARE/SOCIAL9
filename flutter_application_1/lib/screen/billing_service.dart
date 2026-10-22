import '../core/api_client.dart';

class BillingService {
  static Future<Map<String, dynamic>> subscription() async =>
      Map<String, dynamic>.from(
        await ApiClient.get('/billing/subscription') as Map,
      );

  static Future<Map<String, dynamic>> mockSubscribe() async =>
      Map<String, dynamic>.from(
        await ApiClient.post('/billing/mock/subscribe') as Map,
      );

  static Future<Map<String, dynamic>> mockCancel() async =>
      Map<String, dynamic>.from(
        await ApiClient.post('/billing/mock/cancel') as Map,
      );
}
