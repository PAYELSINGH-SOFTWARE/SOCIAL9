import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'api_client.dart';

/// Numeric release ordering, so 1.10.0 is newer than 1.9.0.
int compareAppVersions(String left, String right) {
  List<int> parts(String value) {
    if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(value)) {
      throw const FormatException('Invalid app version');
    }
    return value.split('.').map(int.parse).toList();
  }

  final a = parts(left), b = parts(right);
  for (var i = 0; i < 3; i++) {
    final order = a[i].compareTo(b[i]);
    if (order != 0) return order;
  }
  return 0;
}

class AppUpdate {
  const AppUpdate({
    required this.installedVersion,
    required this.installedBuild,
    required this.latestVersion,
    required this.latestBuild,
    required this.required,
    required this.url,
  });

  final String installedVersion, latestVersion;
  final int installedBuild, latestBuild;
  final bool required;
  final Uri? url;

  String get release => '$latestVersion+$latestBuild';

  static AppUpdate? fromJson(
    Map<String, dynamic> json, {
    required String installedVersion,
    required int installedBuild,
  }) {
    int build(String key) {
      final value = json[key];
      if (value is! int || value < 0) {
        throw const FormatException('Invalid app build');
      }
      return value;
    }

    final latest = json['latest_version'] as String;
    final latestBuild = build('latest_build');
    final minimum = json['min_supported_version'] as String;
    final minimumBuild = build('min_supported_build');
    final versionOrder = compareAppVersions(latest, installedVersion);
    final newer =
        versionOrder > 0 || (versionOrder == 0 && latestBuild > installedBuild);
    final unsupported =
        compareAppVersions(installedVersion, minimum) < 0 ||
        installedBuild < minimumBuild;
    final force = json['force_update'];
    if (force is! bool) {
      throw const FormatException('Invalid update policy');
    }
    if (!newer && !unsupported) return null;

    final rawUrl = json['update_url'];
    final url = rawUrl is String ? Uri.tryParse(rawUrl) : null;
    return AppUpdate(
      installedVersion: installedVersion,
      installedBuild: installedBuild,
      latestVersion: latest,
      latestBuild: latestBuild,
      required: unsupported || (force && newer),
      url:
          url != null &&
              url.scheme == 'https' &&
              url.host.isNotEmpty &&
              url.userInfo.isEmpty
          ? url
          : null,
    );
  }
}

class AppUpdateService {
  const AppUpdateService();

  Future<AppUpdate?> check() async {
    final client = http.Client();
    try {
      final package = await PackageInfo.fromPlatform();
      final response = await client
          .get(
            Uri.parse('${ApiClient.baseUrl}/app/version'),
            headers: const {'Accept': 'application/json'},
          )
          // Render may need to wake up; this check never delays the app UI.
          .timeout(const Duration(seconds: 75));
      if (response.statusCode != 200) return null;
      return AppUpdate.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
        installedVersion: package.version,
        installedBuild: int.parse(package.buildNumber),
      );
    } catch (_) {
      // Offline, old backends and malformed metadata must not block startup.
      return null;
    } finally {
      client.close();
    }
  }
}
