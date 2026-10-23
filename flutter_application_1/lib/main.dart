import 'package:flutter/material.dart';
import 'app/website_screen.dart';
import 'legacy_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const bool.fromEnvironment('SOCIAL9_LEGACY_NATIVE')
        ? const VCueSocial9App()
        : const Social9App(),
  );
}

class Social9App extends StatelessWidget {
  const Social9App({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Social9',
    theme: ThemeData(
      colorSchemeSeed: const Color(0xFF7948EA),
      useMaterial3: true,
    ),
    home: const Social9WebsiteScreen(),
  );
}
