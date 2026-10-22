import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/core/api_client.dart';
import 'package:flutter_application_1/core/workspace_session.dart';
import 'package:flutter_application_1/core/social9_theme.dart';
import 'package:flutter_application_1/main.dart';
import 'package:flutter_application_1/screen/account_service.dart';
import 'package:flutter_application_1/screen/brand_service.dart';
import 'package:flutter_application_1/screen/post_service.dart';
import 'package:flutter_application_1/screen/settings_screen.dart';
import 'package:flutter_application_1/screen/analytics_screen.dart';
import 'package:flutter_application_1/screen/calendar_screen.dart';
import 'package:flutter_application_1/screen/agency_screen.dart';
import 'package:flutter_application_1/screen/templates_screen.dart';
import 'package:flutter_application_1/screen/brand_profile_screen.dart';
import 'package:flutter_application_1/screen/provider_insights_screen.dart';
import 'package:flutter_application_1/screen/subscription_screen.dart';
import 'package:flutter_application_1/screen/create_post_screen.dart';
import 'package:flutter_application_1/screen/action_center_screen.dart';

http.Response jsonResponse(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    WorkspaceSession.onExpired = null;
    WorkspaceSession.brandId.value = null;
  });

  final screens = <String, Widget>{
    'analytics': const AnalyticsScreen(),
    'calendar': const CalendarScreen(),
    'agency': const AgencyScreen(),
    'templates': const TemplatesScreen(),
    'brand context': const BrandProfileScreen(),
    'social insights': const ProviderInsightsScreen(),
    'billing': const SubscriptionScreen(),
    'composer': const CreatePostScreen(),
    'action center': const ActionCenterScreen(),
  };
  for (final screen in screens.entries) {
    testWidgets('${screen.key} loads without crashes at phone width', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            MaterialApp(theme: Social9Theme.light(), home: screen.value),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('Try again'), findsNothing);
        },
        () => MockClient((request) async {
          final path = request.url.path;
          if (path == '/brands') {
            return jsonResponse([
              {'id': 4, 'name': 'Test brand'},
            ]);
          }
          if (path == '/posts' ||
              path == '/social-accounts' ||
              path == '/agency/workspaces') {
            return jsonResponse([]);
          }
          if (path == '/billing/public-plans') {
            return jsonResponse({
              'plans': [
                {
                  'code': 'starter_monthly_v2',
                  'name': 'Starter',
                  'duration': 'monthly',
                  'total_price_inr': 810,
                  'monthly_equivalent_inr': 810,
                  'commitment': '30 days',
                  'features': {'brand_limit': 2, 'competitor_limit': 5},
                },
              ],
            });
          }
          if (path == '/billing/subscription') {
            return jsonResponse({
              'plan': 'free',
              'status': 'inactive',
              'is_paid': false,
              'mock_mode': false,
              'features': {},
            });
          }
          if (path == '/billing/razorpay/config') {
            return jsonResponse({'enabled': true, 'test_mode': true});
          }
          return jsonResponse({
            'industry': '',
            'overview': {},
            'consistency': {},
            'channels': [],
            'suggestions': [],
            'provider_metrics': {},
            'actions': [],
            'summary': {},
            'items': [],
          });
        }),
      );
    });
  }

  test(
    'uses the required Render API and scopes account connections to the active brand',
    () async {
      SharedPreferences.setMockInitialValues({'token': 'test-session'});
      final requests = <http.Request>[];
      await http.runWithClient(
        () async {
          await WorkspaceSession.selectBrand(42);
          final url = await AccountService.authorizationUrl('instagram');
          expect(
            url,
            'https://www.instagram.com/oauth/authorize?state=server-state',
          );
          await AccountService.authorizationUrl('linkedin');
        },
        () => MockClient((request) async {
          requests.add(request);
          return jsonResponse({
            'provider': request.url.pathSegments[1],
            'authorization_url':
                'https://www.instagram.com/oauth/authorize?state=server-state',
          });
        }),
      );
      expect(
        requests.map((r) => r.url.host),
        everyElement('social9-backend-ghqu.onrender.com'),
      );
      expect(requests.map((r) => r.url.path), [
        '/social-accounts/instagram/connect',
        '/social-accounts/linkedin/connect',
      ]);
      for (final request in requests) {
        expect(request.headers['Authorization'], 'Bearer test-session');
        expect(request.headers['X-Brand-ID'], '42');
        expect(request.method, 'POST');
      }
    },
  );

  test(
    'selects an available brand instead of keeping a brand from another session',
    () async {
      await WorkspaceSession.selectBrand(9);
      await http.runWithClient(
        () async {
          await BrandService.list();
          expect(WorkspaceSession.brandId.value, 17);
          expect(
            (await SharedPreferences.getInstance()).getInt(
              'social9_active_brand_id',
            ),
            17,
          );
        },
        () => MockClient(
          (_) async => jsonResponse([
            {'id': 17, 'name': 'My brand'},
          ]),
        ),
      );
    },
  );

  test(
    'clears an expired authenticated session and requests sign-in',
    () async {
      SharedPreferences.setMockInitialValues({
        'token': 'expired',
        'user_email': 'user@example.invalid',
      });
      var expired = false;
      WorkspaceSession.onExpired = () => expired = true;
      await http.runWithClient(
        () async {
          await expectLater(
            ApiClient.get('/auth/me'),
            throwsA(
              isA<ApiException>().having((e) => e.statusCode, 'status', 401),
            ),
          );
        },
        () => MockClient(
          (_) async => jsonResponse({'detail': 'Invalid token'}, 401),
        ),
      );
      expect(expired, isTrue);
      expect(await ApiClient.token(), isNull);
      expect(WorkspaceSession.brandId.value, isNull);
    },
  );

  test(
    'creates a media draft then publishes through the separate publish endpoint',
    () async {
      final requests = <http.Request>[];
      await http.runWithClient(
        () async {
          final draft = await PostService.create(
            caption: 'A real caption',
            platforms: ['instagram', 'linkedin'],
            media: [
              {'name': 'photo.png', 'data': 'base64'},
            ],
            postType: 'post',
          );
          final published = await PostService.publish(draft['id'] as int);
          expect(published['status'], 'published');
        },
        () => MockClient((request) async {
          requests.add(request);
          return jsonResponse({
            'id': 15,
            'status': request.url.path.endsWith('/publish')
                ? 'published'
                : 'draft',
          }, request.url.path.endsWith('/publish') ? 200 : 201);
        }),
      );
      final payload = jsonDecode(requests.first.body) as Map;
      expect(payload['platforms'], ['instagram', 'linkedin']);
      expect(payload['media'], isNotEmpty);
      expect(payload.containsKey('publish_now'), isFalse);
      expect(requests.last.url.path, '/posts/15/publish');
    },
  );

  test(
    'validation errors and non-JSON server responses become readable API errors',
    () async {
      await http.runWithClient(
        () async {
          await expectLater(
            ApiClient.post('/auth/login', authenticated: false),
            throwsA(
              isA<ApiException>().having(
                (e) => e.message,
                'message',
                'Enter a valid email address',
              ),
            ),
          );
          await expectLater(
            ApiClient.get('/health'),
            throwsA(isA<ApiException>()),
          );
        },
        () => MockClient(
          (request) async => request.url.path == '/health'
              ? http.Response('<html>Starting</html>', 200)
              : jsonResponse({
                  'detail': [
                    {'msg': 'Enter a valid email address'},
                  ],
                }, 422),
        ),
      );
    },
  );

  testWidgets('sign-in opens the Render workspace with the selected brand', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await http.runWithClient(
      () async {
        await tester.pumpWidget(const VCueSocial9App());
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextFormField).at(0),
          'user@example.invalid',
        );
        await tester.enterText(
          find.byType(TextFormField).at(1),
          'test-password',
        );
        await tester.tap(find.text('Sign in'));
        await tester.pumpAndSettle();
        expect(find.text('Good to see you, Test.'), findsOneWidget);
        expect(find.text('Test brand'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      () => MockClient((request) async {
        if (request.url.path == '/auth/login') {
          return jsonResponse({
            'access_token': 'test-session',
            'user': {'name': 'Test User', 'email': 'user@example.invalid'},
          });
        }
        if (request.url.path == '/brands') {
          return jsonResponse([
            {'id': 4, 'name': 'Test brand'},
          ]);
        }
        return jsonResponse({
          'overview': {
            'published': 1,
            'scheduled': 1,
            'drafts': 0,
            'connected_accounts': 2,
          },
          'consistency': {'message': 'Keep your rhythm.'},
          'suggestions': [],
          'upcoming_posts': [],
        });
      }),
    );
  });

  testWidgets('Instagram and LinkedIn account controls fit a narrow phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await http.runWithClient(
      () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: Social9Theme.light(),
            home: const SettingsScreen(),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Connect'), findsNWidgets(2));
        expect(tester.takeException(), isNull);
      },
      () => MockClient(
        (request) async => jsonResponse(
          request.url.path.endsWith('provider-status')
              ? [
                  {'provider': 'instagram', 'mode': 'live', 'configured': true},
                  {'provider': 'linkedin', 'mode': 'live', 'configured': true},
                ]
              : [],
        ),
      ),
    );
  });
}
