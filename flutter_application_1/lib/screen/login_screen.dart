import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_client.dart';
import '../core/workspace_session.dart';
import 'auth_service.dart';
import 'brand_service.dart';
import 'auth_recovery_screen.dart';
import 'dashboard_screen.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final formKey = GlobalKey<FormState>();
  bool loading = false;
  bool obscure = true;

  Future<void> login() async {
    if (!(formKey.currentState?.validate() ?? false)) return;
    setState(() => loading = true);
    try {
      final data = await AuthService.login(
        emailController.text,
        passwordController.text,
      );
      final prefs = await SharedPreferences.getInstance();
      await WorkspaceSession.clear();
      await prefs.setString('token', data['access_token'].toString());
      if (data['user'] is Map) {
        final user = data['user'] as Map;
        await prefs.setString('user_name', user['name']?.toString() ?? '');
        await prefs.setString('user_email', user['email']?.toString() ?? '');
      }
      await BrandService.list();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const DashboardScreen()),
        (_) => false,
      );
    } on ApiException catch (error) {
      if (mounted) {
        _show(error.message);
        if (error.statusCode == 403 &&
            error.message.toLowerCase().contains('verif')) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AuthRecoveryScreen(
                verifyEmail: true,
                email: emailController.text.trim(),
              ),
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> forgotPassword() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AuthRecoveryScreen(email: emailController.text.trim()),
      ),
    );
  }

  void _show(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Form(
                    key: formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Image.asset(
                              'assets/images/social9-web-mark.png',
                              width: 46,
                              height: 46,
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              'Social9',
                              style: TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Welcome back',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Plan, publish, and grow from one calm workspace.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(color: Colors.black54),
                        ),
                        const SizedBox(height: 28),
                        TextFormField(
                          controller: emailController,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.email],
                          decoration: const InputDecoration(
                            labelText: 'Email address',
                            prefixIcon: Icon(Icons.mail_outline),
                          ),
                          validator: (value) =>
                              value == null || !value.contains('@')
                              ? 'Enter a valid email address'
                              : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: passwordController,
                          obscureText: obscure,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.password],
                          onFieldSubmitted: (_) {
                            if (!loading) login();
                          },
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              onPressed: () =>
                                  setState(() => obscure = !obscure),
                              icon: Icon(
                                obscure
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                              ),
                            ),
                          ),
                          validator: (value) => value == null || value.isEmpty
                              ? 'Enter your password'
                              : null,
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: loading
                                ? null
                                : () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => AuthRecoveryScreen(
                                        email: emailController.text.trim(),
                                      ),
                                    ),
                                  ),
                            child: const Text('Forgot password?'),
                          ),
                        ),
                        const SizedBox(height: 4),
                        FilledButton(
                          onPressed: loading ? null : login,
                          child: loading
                              ? const SizedBox.square(
                                  dimension: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Sign in'),
                        ),
                        const SizedBox(height: 18),
                        Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Text('New to Social9?'),
                            TextButton(
                              onPressed: loading
                                  ? null
                                  : () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => const SignupScreen(),
                                      ),
                                    ),
                              child: const Text('Create an account'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
