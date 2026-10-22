import 'package:flutter/material.dart';

import '../core/api_client.dart';
import 'auth_service.dart';
import 'auth_recovery_screen.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final formKey = GlobalKey<FormState>();
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool loading = false;
  bool obscure = true;

  Future<void> signup() async {
    if (!(formKey.currentState?.validate() ?? false)) return;
    setState(() => loading = true);
    try {
      final data = await AuthService.signup(
        nameController.text,
        emailController.text,
        passwordController.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(data['message']?.toString() ?? 'Account created.'),
        ),
      );
      final user = data['user'] as Map?;
      if (user?['is_verified'] == false) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AuthRecoveryScreen(
              verifyEmail: true,
              email: emailController.text.trim(),
              token: data['verification_token']?.toString() ?? '',
            ),
          ),
        );
      }
      if (mounted) Navigator.pop(context);
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Form(
                  key: formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Start your Social9 workspace',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Create, schedule, and review your social content in one place.',
                      ),
                      const SizedBox(height: 26),
                      TextFormField(
                        controller: nameController,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.name],
                        decoration: const InputDecoration(
                          labelText: 'Full name',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        validator: (value) => (value?.trim().length ?? 0) < 2
                            ? 'Enter at least 2 characters'
                            : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
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
                        onFieldSubmitted: (_) {
                          if (!loading) signup();
                        },
                        decoration: InputDecoration(
                          labelText: 'Password',
                          helperText: 'Use at least 8 characters',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            onPressed: () => setState(() => obscure = !obscure),
                            icon: Icon(
                              obscure ? Icons.visibility : Icons.visibility_off,
                            ),
                          ),
                        ),
                        validator: (value) => (value?.length ?? 0) < 8
                            ? 'Password must be at least 8 characters'
                            : null,
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: loading ? null : signup,
                        child: loading
                            ? const SizedBox.square(
                                dimension: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Create account'),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'By continuing, you agree to the Social9 terms and privacy policy.',
                        textAlign: TextAlign.center,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: Colors.black54),
                      ),
                    ],
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
