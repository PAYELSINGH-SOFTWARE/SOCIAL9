import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'analytics_screen.dart';
import 'analytics_service.dart';
import 'create_post_screen.dart';
import 'login_screen.dart';
import 'posts_screen.dart';
import 'settings_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<Map<String, dynamic>> summary;

  @override
  void initState() {
    super.initState();
    refreshSummary();
  }

  void refreshSummary() => setState(() {
    summary = AnalyticsService.summary();
  });

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Widget overviewCard(String title, String value, IconData icon, Color color) {
    return SizedBox(
      width: 170,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(icon, color: color),
              const SizedBox(height: 8),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(title, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }

  Widget dashboardCard(
    String title,
    String subtitle,
    IconData icon,
    Widget screen,
  ) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(radius: 25, child: Icon(icon)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.arrow_forward_ios, size: 18),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => screen),
          );
          refreshSummary();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('vCueSocial9 Dashboard'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: refreshSummary,
          ),
          IconButton(icon: const Icon(Icons.logout), onPressed: logout),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => refreshSummary(),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Welcome back',
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Manage all your social media from one place.',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            Text(
              'Publishing overview',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            FutureBuilder<Map<String, dynamic>>(
              future: summary,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.error_outline),
                      title: Text(snapshot.error.toString()),
                      trailing: TextButton(
                        onPressed: refreshSummary,
                        child: const Text('Retry'),
                      ),
                    ),
                  );
                }
                final data = snapshot.data!;
                final platforms =
                    data['posts_by_platform'] as Map<String, dynamic>;
                final connected = (data['connected_accounts'] as List)
                    .cast<String>();
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    overviewCard(
                      'Total Posts',
                      '${data['total_posts']}',
                      Icons.article,
                      Colors.indigo,
                    ),
                    overviewCard(
                      'Drafts',
                      '${data['drafts']}',
                      Icons.edit_note,
                      Colors.blueGrey,
                    ),
                    overviewCard(
                      'Scheduled',
                      '${data['scheduled']}',
                      Icons.schedule,
                      Colors.deepPurple,
                    ),
                    overviewCard(
                      'Published',
                      '${data['published']}',
                      Icons.check_circle,
                      Colors.green,
                    ),
                    overviewCard(
                      'Failed',
                      '${data['failed']}',
                      Icons.error_outline,
                      Colors.red,
                    ),
                    overviewCard(
                      'Success Rate',
                      '${data['success_rate']}%',
                      Icons.trending_up,
                      Colors.teal,
                    ),
                    if (connected.contains('instagram'))
                      overviewCard(
                        'Instagram Posts',
                        '${platforms['instagram']}',
                        Icons.camera_alt,
                        Colors.pink,
                      ),
                    if (connected.contains('linkedin'))
                      overviewCard(
                        'LinkedIn Posts',
                        '${platforms['linkedin']}',
                        Icons.work,
                        Colors.blue,
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 28),
            dashboardCard(
              'Create Post',
              'Create, publish, and schedule posts',
              Icons.post_add,
              const CreatePostScreen(),
            ),
            const SizedBox(height: 12),
            dashboardCard(
              'Performance Analytics',
              'View reach, impressions, and engagement',
              Icons.analytics,
              const AnalyticsScreen(),
            ),
            const SizedBox(height: 12),
            dashboardCard(
              'Posts',
              'View drafts, scheduled, and published posts',
              Icons.schedule,
              const PostsScreen(),
            ),
            const SizedBox(height: 12),
            dashboardCard(
              'Settings',
              'Manage connected accounts',
              Icons.settings,
              const SettingsScreen(),
            ),
          ],
        ),
      ),
    );
  }
}

