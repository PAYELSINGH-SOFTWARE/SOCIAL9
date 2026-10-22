import '../core/api_client.dart';

class PostService {
  static Future<Map<String, dynamic>> create({
    required String caption,
    required List<String> platforms,
    List<Map<String, String>> media = const [],
    DateTime? scheduledFor,
    String postType = 'post',
    int? facebookAccountId,
  }) async => Map<String, dynamic>.from(
    await ApiClient.post(
          '/posts',
          body: {
            'caption': caption,
            'platforms': platforms,
            'media': media,
            'post_type': postType,
            'facebook_account_id': ?facebookAccountId,
            'scheduled_for': scheduledFor?.toUtc().toIso8601String(),
          },
        )
        as Map,
  );

  static Future<Map<String, dynamic>> publish(int id) async =>
      Map<String, dynamic>.from(
        await ApiClient.post('/posts/$id/publish') as Map,
      );

  static Future<List<Map<String, dynamic>>> list({
    String? status,
    String? search,
    String? platform,
    DateTime? from,
    DateTime? to,
  }) async {
    final query = <String, String>{
      if (status != null && status != 'all') 'status': status,
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      if (platform != null && platform != 'all') 'platform': platform,
      if (from != null) 'date_from': from.toUtc().toIso8601String(),
      if (to != null) 'date_to': to.toUtc().toIso8601String(),
    };
    final uri = Uri(
      path: '/posts',
      queryParameters: query.isEmpty ? null : query,
    );
    return (await ApiClient.get(uri.toString()) as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  static Future<Map<String, dynamic>> update(
    int id, {
    required String caption,
    required List<String> platforms,
    DateTime? scheduledFor,
    int? facebookAccountId,
    Map<String, dynamic>? networkOptions,
  }) async => Map<String, dynamic>.from(
    await ApiClient.patch(
          '/posts/$id',
          body: {
            'caption': caption,
            'platforms': platforms,
            'facebook_account_id': facebookAccountId,
            'network_options': networkOptions ?? {},
            'scheduled_for': scheduledFor?.toUtc().toIso8601String(),
          },
        )
        as Map,
  );

  static Future<Map<String, dynamic>> duplicate(int id) async =>
      Map<String, dynamic>.from(
        await ApiClient.post('/posts/$id/duplicate') as Map,
      );

  static Future<Map<String, dynamic>> schedule(int id, DateTime value) async =>
      Map<String, dynamic>.from(
        await ApiClient.patch(
              '/posts/$id/schedule',
              body: {'scheduled_for': value.toUtc().toIso8601String()},
            )
            as Map,
      );

  static Future<Map<String, dynamic>> moveToDraft(int id) async =>
      Map<String, dynamic>.from(
        await ApiClient.patch('/posts/$id/draft') as Map,
      );

  static Future<void> delete(int id) => ApiClient.delete('/posts/$id');

  static Future<Map<String, dynamic>> assist({
    required String action,
    required String topic,
    required String platform,
    List<String> images = const [],
  }) async => Map<String, dynamic>.from(
    await ApiClient.post(
          '/ai/assist',
          body: {
            'action': action,
            'topic': topic,
            'platform': platform,
            'images': images,
          },
        )
        as Map,
  );
}
