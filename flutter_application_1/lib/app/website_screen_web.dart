import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'website_policy.dart';

@JS('window.location.replace')
external void _replaceLocation(JSString location);

/// A browser must navigate directly, not iframe the website (its CSP correctly
/// forbids framing). This also preserves the site's own origin and CORS setup.
class Social9WebsiteScreen extends StatefulWidget {
  const Social9WebsiteScreen({super.key});
  @override
  State<Social9WebsiteScreen> createState() => _Social9WebsiteScreenState();
}

class _Social9WebsiteScreenState extends State<Social9WebsiteScreen> {
  final policy = WebsitePolicy(
    website: const String.fromEnvironment(
      'SOCIAL9_WEB_URL',
      defaultValue: WebsitePolicy.canonicalOrigin,
    ),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = policy.browserDestination(Uri.base);
      _replaceLocation(target.toString().toJS);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          const Text('Opening the Social9 website…'),
          TextButton(
            onPressed: () => _replaceLocation(policy.startPage.toString().toJS),
            child: const Text('Continue to Social9'),
          ),
        ],
      ),
    ),
  );
}
