import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'subscription_screen.dart';

class PlansScreen extends StatelessWidget {
  const PlansScreen({super.key});

  Future<void> activatePlan(
    BuildContext context,
    String planName,
  ) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool(
      'has_active_subscription',
      true,
    );

    await prefs.setString(
      'subscription_plan',
      planName,
    );

    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$planName plan activated for testing.',
        ),
      ),
    );

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => const SubscriptionScreen(),
      ),
    );
  }

  Widget planCard({
    required BuildContext context,
    required String name,
    required String price,
    required String description,
    required List<String> features,
    required bool recommended,
  }) {
    return Card(
      elevation: recommended ? 6 : 3,
      margin: const EdgeInsets.only(bottom: 20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: recommended
              ? Theme.of(context).colorScheme.primary
              : Colors.transparent,
          width: recommended ? 2 : 0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (recommended)
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'RECOMMENDED',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),

            if (recommended)
              const SizedBox(height: 15),

            Icon(
              name == 'Pro'
                  ? Icons.workspace_premium
                  : Icons.business_center,
              size: 50,
            ),

            const SizedBox(height: 12),

            Text(
              name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              price,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 10),

            Text(
              description,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.grey,
                height: 1.4,
              ),
            ),

            const SizedBox(height: 20),

            ...features.map(
              (feature) => Padding(
                padding: const EdgeInsets.only(
                  bottom: 10,
                ),
                child: Row(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.check_circle,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(feature),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 10),

            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: () {
                  activatePlan(
                    context,
                    name,
                  );
                },
                child: Text(
                  'Choose $name',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Social9 Plans',
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),

            const Icon(
              Icons.workspace_premium,
              size: 70,
            ),

            const SizedBox(height: 15),

            const Text(
              'Choose Your Social9 Plan',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 10),

            const Text(
              'Unlock powerful tools to manage, analyze '
              'and grow your social media presence.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey,
                fontSize: 15,
                height: 1.5,
              ),
            ),

            const SizedBox(height: 30),

            planCard(
              context: context,
              name: 'Pro',
              price: '₹499 / month',
              description:
                  'For creators and growing social media accounts.',
              recommended: true,
              features: const [
                'Advanced Analytics',
                'Create Post',
                'Engagement Forecasting',
                'Caption AI',
                'Social media insights',
              ],
            ),

            planCard(
              context: context,
              name: 'Business',
              price: '₹999 / month',
              description:
                  'For businesses managing a larger social media presence.',
              recommended: false,
              features: const [
                'Everything in Pro',
                'Advanced Analytics',
                'Engagement Forecasting',
                'Caption AI',
                'Content planning',
                'Business-focused insights',
              ],
            ),

            const SizedBox(height: 10),

            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Development mode: selecting a plan activates '
                  'a local test subscription. Real payment '
                  'verification can be connected later.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 13,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            OutlinedButton.icon(
              icon: const Icon(
                Icons.workspace_premium,
              ),
              label: const Text(
                'View My Subscription',
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const SubscriptionScreen(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}