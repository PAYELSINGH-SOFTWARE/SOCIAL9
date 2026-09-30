import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'analytics_screen.dart';
import 'analytics_service.dart';
import 'create_post_screen.dart';
import 'login_screen.dart';
import 'posts_screen.dart';
import 'settings_screen.dart';
import 'profile_screen.dart';
import 'products_screen.dart';
import 'plans_screen.dart';
import 'subscription_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<Map<String, dynamic>> summary;

  // TEMPORARY:
  // true = Create Post is visible
  // false = Create Post is hidden
  //
  // Later this will come from the user's real subscription
  // status from the backend/payment system.
  bool hasActiveSubscription = false;

  @override
  void initState() {
    super.initState();
    refreshSummary();
    loadSubscriptionStatus();
  }

  void refreshSummary() {
    setState(() {
      summary = AnalyticsService.summary();
    });
  }

  Future<void> loadSubscriptionStatus() async {
    final prefs = await SharedPreferences.getInstance();

    final active =
        prefs.getBool('has_active_subscription') ?? false;

    if (!mounted) return;

    setState(() {
      hasActiveSubscription = active;
    });
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove('token');

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => const LoginScreen(),
      ),
      (route) => false,
    );
  }

  Widget overviewCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return SizedBox(
      width: 170,
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(
                icon,
                color: color,
                size: 30,
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                textAlign: TextAlign.center,
              ),
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(
          radius: 25,
          child: Icon(icon),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(subtitle),
        ),
        trailing: const Icon(
          Icons.arrow_forward_ios,
          size: 18,
        ),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => screen,
            ),
          );

          if (!mounted) return;

          await loadSubscriptionStatus();
          refreshSummary();
        },
      ),
    );
  }

  Widget sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(
        top: 24,
        bottom: 10,
      ),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }

  Widget subscriptionMessage() {
    if (hasActiveSubscription) {
      return Card(
        elevation: 2,
        child: ListTile(
          leading: const CircleAvatar(
            child: Icon(Icons.check),
          ),
          title: const Text(
            'Subscription Active',
            style: TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: const Text(
            'Your paid Social9 features are unlocked.',
          ),
        ),
      );
    }

    return Card(
      elevation: 2,
      child: ListTile(
        leading: const CircleAvatar(
          child: Icon(Icons.lock),
        ),
        title: const Text(
          'Choose a Social9 Plan',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: const Text(
          'Choose a plan to unlock Create Post and paid features.',
        ),
        trailing: const Icon(
          Icons.arrow_forward_ios,
          size: 18,
        ),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const PlansScreen(),
            ),
          );

          if (!mounted) return;

          await loadSubscriptionStatus();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'vCueSocial9 Dashboard',
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              refreshSummary();
              await loadSubscriptionStatus();
            },
          ),
          IconButton(
            tooltip: 'Profile',
            icon: const Icon(Icons.person),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ProfileScreen(),
                ),
              );

              if (!mounted) return;

              await loadSubscriptionStatus();
            },
          ),
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout),
            onPressed: logout,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          refreshSummary();
          await loadSubscriptionStatus();
        },
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Welcome back 👋',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 6),

            const Text(
              'Manage and grow your social media from one place.',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),

            sectionTitle('Your Social9'),

            dashboardCard(
              'Profile',
              'View and manage your Social9 profile',
              Icons.person,
              const ProfileScreen(),
            ),

            const SizedBox(height: 12),

            subscriptionMessage(),

            sectionTitle('Publishing Overview'),

            FutureBuilder<Map<String, dynamic>>(
              future: summary,
              builder: (context, snapshot) {
                if (snapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: CircularProgressIndicator(),
                    ),
                  );
                }

                if (snapshot.hasError) {
                  return Card(
                    child: ListTile(
                      leading: const Icon(
                        Icons.error_outline,
                      ),
                      title: const Text(
                        'Unable to load analytics summary',
                      ),
                      subtitle: Text(
                        snapshot.error.toString(),
                      ),
                      trailing: TextButton(
                        onPressed: refreshSummary,
                        child: const Text('Retry'),
                      ),
                    ),
                  );
                }

                final data = snapshot.data ?? {};

                final platforms =
                    (data['posts_by_platform']
                            as Map<String, dynamic>?) ??
                        {};

                final connected =
                    (data['connected_accounts'] as List?)
                            ?.cast<String>() ??
                        [];

                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    overviewCard(
                      'Total Posts',
                      '${data['total_posts'] ?? 0}',
                      Icons.article,
                      Colors.indigo,
                    ),
                    overviewCard(
                      'Drafts',
                      '${data['drafts'] ?? 0}',
                      Icons.edit_note,
                      Colors.blueGrey,
                    ),
                    overviewCard(
                      'Scheduled',
                      '${data['scheduled'] ?? 0}',
                      Icons.schedule,
                      Colors.deepPurple,
                    ),
                    overviewCard(
                      'Published',
                      '${data['published'] ?? 0}',
                      Icons.check_circle,
                      Colors.green,
                    ),
                    overviewCard(
                      'Failed',
                      '${data['failed'] ?? 0}',
                      Icons.error_outline,
                      Colors.red,
                    ),
                    overviewCard(
                      'Success Rate',
                      '${data['success_rate'] ?? 0}%',
                      Icons.trending_up,
                      Colors.teal,
                    ),

                    if (connected.contains('instagram'))
                      overviewCard(
                        'Instagram Posts',
                        '${platforms['instagram'] ?? 0}',
                        Icons.camera_alt,
                        Colors.pink,
                      ),

                    if (connected.contains('linkedin'))
                      overviewCard(
                        'LinkedIn Posts',
                        '${platforms['linkedin'] ?? 0}',
                        Icons.work,
                        Colors.blue,
                      ),
                  ],
                );
              },
            ),

            sectionTitle('Social Media Management'),

            // CREATE POST IS ONLY AVAILABLE
            // WHEN THE USER HAS AN ACTIVE PLAN.
            if (hasActiveSubscription) ...[
              dashboardCard(
                'Create Post',
                'Create, publish, and schedule posts',
                Icons.post_add,
                const CreatePostScreen(),
              ),

              const SizedBox(height: 12),
            ],

            dashboardCard(
              'Performance Analytics',
              'View reach, impressions, engagement and performance',
              Icons.analytics,
              const AnalyticsScreen(),
            ),

            const SizedBox(height: 12),

            dashboardCard(
              'Posts',
              'View scheduled, published and existing posts',
              Icons.schedule,
              const PostsScreen(),
            ),

            const SizedBox(height: 12),

            dashboardCard(
              'Settings',
              'Manage your connected social media accounts',
              Icons.settings,
              const SettingsScreen(),
            ),

            // ====================================================
            // SOCIAL9 PRODUCTS
            // ====================================================

            sectionTitle('Social9 Products'),

            dashboardCard(
              'Explore Social9',
              'Explore Social9 AI, analytics and growth products',
              Icons.shopping_bag,
              const ProductsScreen(),
            ),

            const SizedBox(height: 12),

            dashboardCard(
              'Plans & Pricing',
              'Choose a Social9 plan that fits your needs',
              Icons.workspace_premium,
              const PlansScreen(),
            ),

            const SizedBox(height: 12),

            dashboardCard(
              'My Subscription',
              'View your current plan and subscription status',
              Icons.card_membership,
              const SubscriptionScreen(),
            ),

            const SizedBox(height: 25),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                icon: const Icon(
                  Icons.workspace_premium,
                ),
                label: Text(
                  hasActiveSubscription
                      ? 'Manage Subscription'
                      : 'Choose a Social9 Plan',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => hasActiveSubscription
                          ? const SubscriptionScreen()
                          : const PlansScreen(),
                    ),
                  );

                  if (!mounted) return;

                  await loadSubscriptionStatus();
                },
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

