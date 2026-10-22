import 'package:flutter/material.dart';
import '../core/api_client.dart';
import '../widgets/workspace_widgets.dart';

class AuthRecoveryScreen extends StatefulWidget {
  const AuthRecoveryScreen({
    super.key,
    this.verifyEmail = false,
    this.email = '',
    this.token = '',
  });
  final bool verifyEmail;
  final String email;
  final String token;
  @override
  State<AuthRecoveryScreen> createState() => _AuthRecoveryScreenState();
}

class _AuthRecoveryScreenState extends State<AuthRecoveryScreen> {
  late final email = TextEditingController(text: widget.email);
  late final token = TextEditingController(text: widget.token);
  final password = TextEditingController();
  bool busy = false;
  String message = '';
  Future<void> submit(bool request) async {
    if (request && !email.text.contains('@')) {
      showMessage(context, 'Enter a valid email address.');
      return;
    }
    if (!request && token.text.trim().isEmpty) {
      showMessage(context, 'Enter the token from your email link.');
      return;
    }
    if (!request && !widget.verifyEmail && password.text.length < 8) {
      showMessage(context, 'Use at least 8 characters for your new password.');
      return;
    }
    setState(() => busy = true);
    try {
      final path = request
          ? (widget.verifyEmail
                ? '/auth/verification/request'
                : '/auth/password/forgot')
          : (widget.verifyEmail
                ? '/auth/verify-email'
                : '/auth/password/reset');
      final result =
          await ApiClient.post(
                path,
                authenticated: false,
                body: request
                    ? {'email': email.text.trim()}
                    : {
                        'token': _tokenText(token.text),
                        if (!widget.verifyEmail) 'new_password': password.text,
                      },
              )
              as Map;
      if (!mounted) return;
      setState(() {
        message = result['message']?.toString() ?? 'Completed.';
        if (result['token'] != null) token.text = result['token'].toString();
      });
      if (!request) {
        showMessage(context, message);
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) showMessage(context, error);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String _tokenText(String text) =>
      Uri.tryParse(text.trim())?.queryParameters['token'] ?? text.trim();
  @override
  void dispose() {
    email.dispose();
    token.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.verifyEmail ? 'Verify email' : 'Reset password'),
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              widget.verifyEmail
                  ? 'Verify your email to sign in.'
                  : 'Get back into your workspace.',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email address'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: busy ? null : () => submit(true),
              child: Text(
                widget.verifyEmail
                    ? 'Resend verification email'
                    : 'Send reset instructions',
              ),
            ),
            if (message.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(message),
              ),
            const Divider(height: 36),
            const Text(
              'Already have the email? Paste the link or its token below.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: token,
              decoration: const InputDecoration(
                labelText: 'Email link or token',
              ),
            ),
            if (!widget.verifyEmail) ...[
              const SizedBox(height: 14),
              TextField(
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'New password',
                  helperText: 'At least 8 characters',
                ),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton(
              onPressed: busy ? null : () => submit(false),
              child: Text(
                widget.verifyEmail ? 'Verify email' : 'Update password',
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
