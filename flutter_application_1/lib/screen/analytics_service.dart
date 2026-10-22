import '../core/api_client.dart';

class AnalyticsService {
  static Future<Map<String, dynamic>> summary({int days = 30}) async =>
      Map<String, dynamic>.from(
        await ApiClient.get('/analytics/summary?days=$days') as Map,
      );

  static Future<Map<String, dynamic>> actions() async =>
      Map<String, dynamic>.from(
        await ApiClient.get('/workspace/actions') as Map,
      );
}
