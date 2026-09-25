import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'analytics_screen.dart';
import 'create_post_screen.dart';
import 'plans_screen.dart';
import 'subscription_screen.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  bool hasActiveSubscription = false;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    loadSubscriptionStatus();
  }

  Future<void> loadSubscriptionStatus() async {
    final prefs = await SharedPreferences.getInstance();

    final active =
        prefs.getBool('has_active_subscription') ?? false;

    if (!mounted) return;

    setState(() {
      hasActiveSubscription = active;
      isLoading = false;
    });
  }

  void openPaidFeature({
    required Widget screen,
    required String featureName,
  }) {
    if (hasActiveSubscription) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => screen,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Subscription Required'),
          content: Text(
            '$featureName is available with a Social9 subscription. '
            'Choose a plan to unlock this feature.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext);

                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const PlansScreen(),
                  ),
                ).then((_) {
                  loadSubscriptionStatus();
                });
              },
              child: const Text('View Plans'),
            ),
          ],
        );
      },
    );
  }

  Widget productCard({
    required IconData icon,
    required String title,
    required String description,
    required String buttonText,
    required VoidCallback onPressed,
    bool locked = false,
  }) {
    return Card(
      elevation: 3,
      margin: const EdgeInsets.only(bottom: 18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  child: Icon(
                    icon,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (locked)
                  const Icon(
                    Icons.lock,
                    size: 22,
                  ),
              ],
            ),
            const SizedBox(height: 15),
            Text(
              description,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.grey,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: onPressed,
                icon: Icon(
                  locked
                      ? Icons.lock_open
                      : Icons.arrow_forward,
                ),
                label: Text(buttonText),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Social9 Products'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'My Subscription',
            icon: const Icon(Icons.workspace_premium),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const SubscriptionScreen(),
                ),
              ).then((_) {
                loadSubscriptionStatus();
              });
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: loadSubscriptionStatus,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),

              const Icon(
                Icons.auto_awesome,
                size: 65,
              ),

              const SizedBox(height: 15),

              const Text(
                'Welcome to Social9',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 10),

              const Text(
                'Powerful AI and analytics tools to help '
                'you manage, understand and grow your '
                'social media presence.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey,
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 25),

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        hasActiveSubscription
                            ? Icons.verified
                            : Icons.lock_outline,
                        size: 30,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          hasActiveSubscription
                              ? 'Your subscription is active'
                              : 'Choose a plan to unlock Social9 features',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 25),

              productCard(
                icon: Icons.analytics_outlined,
                title: 'Advanced Analytics',
                description:
                    'Understand your social media performance '
                    'with engagement metrics, post analytics '
                    'and performance insights.',
                buttonText: hasActiveSubscription
                    ? 'Open Analytics'
                    : 'Unlock Analytics',
                locked: !hasActiveSubscription,
                onPressed: () {
                  openPaidFeature(
                    screen: const AnalyticsScreen(),
                    featureName: 'Advanced Analytics',
                  );
                },
              ),

              productCard(
                icon: Icons.post_add,
                title: 'Create Post',
                description:
                    'Create and manage social media posts '
                    'from Social9. This feature becomes '
                    'available after your subscription is active.',
                buttonText: hasActiveSubscription
                    ? 'Create Post'
                    : 'Unlock Create Post',
                locked: !hasActiveSubscription,
                onPressed: () {
                  openPaidFeature(
                    screen: const CreatePostScreen(),
                    featureName: 'Create Post',
                  );
                },
              ),

              const SizedBox(height: 10),

              Card(
                elevation: 3,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.workspace_premium,
                        size: 50,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Social9 Plans',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Choose the Social9 plan that fits '
                        'your social media needs.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.price_check),
                          label: const Text('View Plans & Pricing'),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const PlansScreen(),
                              ),
                            ).then((_) {
                              loadSubscriptionStatus();
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 25),

              OutlinedButton.icon(
                icon: const Icon(Icons.dashboard),
                label: const Text('Go to Dashboard'),
                onPressed: () {
                  Navigator.pop(context);
                },
              ),

              const SizedBox(height: 20),

              const Text(
                'Social9 — AI-powered social media management',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
