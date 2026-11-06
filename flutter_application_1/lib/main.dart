import 'package:flutter/material.dart';
import 'app/website_screen.dart';
import 'legacy_app.dart';
import 'widgets/app_update_gate.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  const useNativeApp = bool.fromEnvironment(
    'SOCIAL9_LEGACY_NATIVE',
    defaultValue: true,
  );

  runApp(useNativeApp ? const VCueSocial9App() : const Social9App());
}

class Social9App extends StatelessWidget {
  const Social9App({super.key});

  @override
  Widget build(BuildContext context) {
    const purple = Color(0xFF7948EA);

    return MaterialApp(
      navigatorKey: _websiteNavigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Social9',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: purple,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F6FC),
        useMaterial3: true,
      ),
      home: const Social9WebsiteScreen(),
      builder: (context, child) =>
          AppUpdateGate(navigatorKey: _websiteNavigatorKey, child: child!),
    );
  }
}

final _websiteNavigatorKey = GlobalKey<NavigatorState>();
