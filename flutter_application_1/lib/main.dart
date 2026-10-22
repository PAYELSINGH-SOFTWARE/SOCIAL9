import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/social9_theme.dart';
import 'core/workspace_session.dart';
import 'screen/auth_service.dart';
import 'screen/brand_service.dart';
import 'core/api_client.dart';
import 'screen/dashboard_screen.dart';
import 'screen/login_screen.dart';

void main() {
  runApp(const VCueSocial9App());
}

class VCueSocial9App extends StatelessWidget {
  const VCueSocial9App({super.key});

  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString("token");

    if (token == null || token.isEmpty) return false;
    await WorkspaceSession.restoreBrand();
    try {
      await AuthService.me();
      await BrandService.list();
      return true;
    } on ApiException catch (error) {
      return error.statusCode != 401;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Social9',
      theme: Social9Theme.light(),
      home: FutureBuilder<bool>(
        future: isLoggedIn(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          if (snapshot.data == true) {
            return const DashboardScreen();
          }

          return const LoginScreen();
        },
      ),
      builder: (context, child) {
        WorkspaceSession.onExpired = () {
          _navigatorKey.currentState?.pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
            (_) => false,
          );
        };
        return child!;
      },
    );
  }
}

final _navigatorKey = GlobalKey<NavigatorState>();
