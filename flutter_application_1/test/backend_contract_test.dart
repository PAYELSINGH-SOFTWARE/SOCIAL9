import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/screen/api_config.dart';
import 'package:flutter_application_1/screen/account_service.dart';
import 'package:flutter_application_1/screen/analytics_service.dart';
import 'package:flutter_application_1/screen/post_service.dart';

void main() {
  setUp(
    () => SharedPreferences.setMockInitialValues({
      ApiConfig.tokenKey: 'test-token',
    }),
  );

  test('publish now creates a draft then publishes its ID', () async {
    final paths = <String>[];
    await http.runWithClient(
      () async {
        final response = await PostService.create(
          caption: 'Hello',
          platforms: ['linkedin'],
          publishNow: true,
        );
        expect(response.statusCode, 200);
        expect(jsonDecode(response.body)['status'], 'published');
      },
      () => MockClient((request) async {
        paths.add(request.url.path);
        expect(request.headers['Authorization'], 'Bearer test-token');
        if (request.url.path == '/posts') {
          expect(jsonDecode(request.body).containsKey('publish_now'), false);
          return http.Response('{"id":42,"status":"draft"}', 201);
        }
        return http.Response('{"id":42,"status":"published"}', 200);
      }),
    );
    expect(paths, ['/posts', '/posts/42/publish']);
  });

  test('failed creation is not followed by publishing', () async {
    var calls = 0;
    await http.runWithClient(
      () async {
        final response = await PostService.create(
          caption: '',
          platforms: ['linkedin'],
          publishNow: true,
        );
        expect(response.statusCode, 422);
      },
      () => MockClient((request) async {
        calls++;
        return http.Response('{"detail":"Invalid caption"}', 422);
      }),
    );
    expect(calls, 1);
  });

  test(
    'connected accounts join provider availability, including unconnected providers',
    () async {
      await http.runWithClient(
        () async {
          final accounts = await AccountService.list();
          expect(accounts[0]['connected'], true);
          expect(accounts[0]['display_name'], 'Example');
          expect(accounts[1]['connected'], false);
          expect(accounts[1]['configured'], true);
        },
        () => MockClient(
          (request) async => http.Response(
            request.url.path.endsWith('/provider-status')
                ? '[{"provider":"instagram","configured":true},{"provider":"linkedin","configured":true}]'
                : '[{"provider":"instagram","status":"connected","account_name":"Example"}]',
            200,
          ),
        ),
      );
    },
  );

  test(
    'nested analytics become dashboard counts without invented engagement',
    () async {
      await http.runWithClient(
        () async {
          final summary = await AnalyticsService.summary();
          expect(summary['total_posts'], 3);
          expect(summary['success_rate'], 50);
          expect(summary['connected_accounts'], ['instagram']);
          expect(summary['posts_by_platform'], {'instagram': 3});
          expect(summary.containsKey('impressions'), false);
        },
        () => MockClient((request) async {
          expect(request.url.path, '/analytics/summary');
          return http.Response(
            '{"overview":{"total_posts":3,"publish_success_rate":50},"channels":[{"provider":"instagram","connected":true,"post_count":3}]}',
            200,
          );
        }),
      );
    },
  );
}
