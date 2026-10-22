import 'package:flutter/material.dart';

import 'account_service.dart';
import 'auth_service.dart';
import 'settings_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late Future<(Map<String, dynamic>, List<Map<String, dynamic>>)> profile;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  void refresh() => setState(() {
    profile = Future.wait([AuthService.me(), AccountService.list()]).then(
      (values) => (
        values[0] as Map<String, dynamic>,
        values[1] as List<Map<String, dynamic>>,
      ),
    );
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Profile'),
      actions: [
        IconButton(onPressed: refresh, icon: const Icon(Icons.refresh)),
      ],
    ),
    body: FutureBuilder<(Map<String, dynamic>, List<Map<String, dynamic>>)>(
      future: profile,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: OutlinedButton(
              onPressed: refresh,
              child: const Text('Try again'),
            ),
          );
        }
        final user = snapshot.data!.$1;
        final accounts = snapshot.data!.$2;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 60),
          children: [
            Center(
              child: CircleAvatar(
                radius: 48,
                child: Text(
                  _initials(user['name']?.toString() ?? ''),
                  style: const TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              user['name']?.toString() ?? 'Social9 user',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            Text(
              user['email']?.toString() ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 24),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.badge_outlined),
                    title: const Text('Name'),
                    subtitle: Text(user['name']?.toString() ?? '—'),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.mail_outline),
                    title: const Text('Email'),
                    subtitle: Text(user['email']?.toString() ?? '—'),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: Icon(
                      user['is_verified'] == true
                          ? Icons.verified_outlined
                          : Icons.warning_amber,
                    ),
                    title: const Text('Email status'),
                    subtitle: Text(
                      user['is_verified'] == true
                          ? 'Verified'
                          : 'Verification required',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Connected profiles',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  ).then((_) => refresh()),
                  child: const Text('Manage'),
                ),
              ],
            ),
            if (accounts.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('No social accounts connected yet.'),
                ),
              )
            else
              for (final account in accounts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Icon(
                          account['provider'] == 'instagram'
                              ? Icons.camera_alt_outlined
                              : Icons.work_outline,
                        ),
                      ),
                      title: Text(
                        account['account_name']?.toString() ??
                            account['provider'].toString(),
                      ),
                      subtitle: Text(account['provider'].toString()),
                      trailing: const Icon(
                        Icons.check_circle,
                        color: Colors.green,
                      ),
                    ),
                  ),
                ),
          ],
        );
      },
    ),
  );

  String _initials(String value) {
    final parts = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((item) => item.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'S9';
    return parts.take(2).map((item) => item[0].toUpperCase()).join();
  }
}
