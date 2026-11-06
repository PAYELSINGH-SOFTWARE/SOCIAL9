import 'dart:convert';

import 'package:flutter_application_1/core/app_update.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';

Map<String, dynamic> policy({
  String latest = '1.1.2',
  int build = 4,
  String minimum = '1.1.1',
  int minimumBuild = 3,
  bool force = false,
}) => {
  'latest_version': latest,
  'latest_build': build,
  'min_supported_version': minimum,
  'min_supported_build': minimumBuild,
  'force_update': force,
  'update_url': 'https://downloads.example.com/social9.apk',
};

AppUpdate? evaluate(
  Map<String, dynamic> json, {
  String version = '1.1.1',
  int build = 3,
}) =>
    AppUpdate.fromJson(json, installedVersion: version, installedBuild: build);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('version comparison uses numeric components', () {
    expect(compareAppVersions('1.10.0', '1.9.9'), greaterThan(0));
    expect(compareAppVersions('2.0.0', '1.99.99'), greaterThan(0));
    expect(compareAppVersions('1.1.1', '1.1.1'), 0);
  });

  test('newer version and same-version build releases prompt', () {
    expect(evaluate(policy())?.required, isFalse);
    expect(evaluate(policy(latest: '1.1.1'))?.latestBuild, 4);
    expect(evaluate(policy(latest: '1.1.1', build: 3)), isNull);
  });

  test('newer installed versions are not prompted to downgrade', () {
    expect(evaluate(policy(latest: '1.0.0', build: 99)), isNull);
    expect(evaluate(policy(force: true), version: '1.1.2', build: 4), isNull);
  });

  test('force applies to outdated installations only', () {
    expect(evaluate(policy(force: true))?.required, isTrue);
    expect(evaluate(policy(force: true), version: '1.1.2', build: 4), isNull);
  });

  test('either minimum supported version or build makes update mandatory', () {
    expect(evaluate(policy(minimum: '1.1.2'))?.required, isTrue);
    expect(evaluate(policy(minimumBuild: 4))?.required, isTrue);
    expect(evaluate(policy())?.required, isFalse);
  });

  test(
    'malformed metadata is rejected and unsafe download URLs are ignored',
    () {
      expect(
        () => evaluate({...policy(), 'latest_version': 'bad'}),
        throwsFormatException,
      );
      expect(
        () => evaluate({...policy(), 'latest_build': -1}),
        throwsFormatException,
      );
      expect(
        () => evaluate({...policy(), 'force_update': 'false'}),
        throwsFormatException,
      );
      for (final url in [
        'http://download.test/app.apk',
        'javascript:alert(1)',
        'https://user@download.test/app.apk',
        null,
      ]) {
        expect(evaluate({...policy(), 'update_url': url})?.url, isNull);
      }
    },
  );

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Social9',
      packageName: 'com.example.flutter_application_1',
      version: '1.1.1',
      buildNumber: '3',
      buildSignature: '',
    );
  });

  test(
    'public request uses production backend and installed package info',
    () async {
      final result = await http.runWithClient(
        () => const AppUpdateService().check(),
        () => MockClient((request) async {
          expect(
            request.url.toString(),
            'https://social9-backend-ghqu.onrender.com/app/version',
          );
          expect(request.headers.containsKey('Authorization'), isFalse);
          return http.Response(jsonEncode(policy()), 200);
        }),
      );
      expect(result?.installedVersion, '1.1.1');
      expect(result?.installedBuild, 3);
      expect(result?.latestVersion, '1.1.2');
    },
  );

  test(
    'offline, unavailable endpoint and invalid metadata fail open',
    () async {
      for (final status in [404, 500, 200]) {
        expect(
          await http.runWithClient(
            () => const AppUpdateService().check(),
            () =>
                MockClient((_) async => http.Response('invalid json', status)),
          ),
          isNull,
        );
      }
      expect(
        await http.runWithClient(
          () => const AppUpdateService().check(),
          () => MockClient((_) async => throw http.ClientException('Offline')),
        ),
        isNull,
      );
    },
  );
}
