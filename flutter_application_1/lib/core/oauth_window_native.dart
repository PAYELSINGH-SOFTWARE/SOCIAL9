import 'package:url_launcher/url_launcher.dart';

class OAuthWindow {
  bool get closed => false;
  Future<void> navigate(String url) async {
    if (!await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    )) {
      throw Exception('Could not open the authorization page.');
    }
  }

  void close() {}
}

OAuthWindow? reserveOAuthWindow() => OAuthWindow();
