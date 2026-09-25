import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() =>
      _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  bool isActive = false;
  String planName = 'No Active Plan';

  @override
  void initState() {
    super.initState();
    loadSubscription();
  }

  Future<void> loadSubscription() async {
    final prefs = await SharedPreferences.getInstance();

    final active =
        prefs.getBool('has_active_subscription') ?? false;

    final plan =
        prefs.getString('subscription_plan') ?? 'No Active Plan';

    if (!mounted) return;

    setState(() {
      isActive = active;
      planName = plan;
    });
  }

  Future<void> activateDemoSubscription(String plan) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool(
      'has_active_subscription',
      true,
    );

    await prefs.setString(
      'subscription_plan',
      plan,
    );

    if (!mounted) return;

    setState(() {
      isActive = true;
      planName = plan;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$plan plan activated for testing.',
        ),
      ),
    );
  }

  Future<void> cancelSubscription() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool(
      'has_active_subscription',
      false,
    );

    await prefs.remove('subscription_plan');

    if (!mounted) return;

    setState(() {
      isActive = false;
      planName = 'No Active Plan';
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Subscription cancelled.',
        ),
      ),
    );
  }

  Widget infoRow(
    IconData icon,
    String title,
    String value,
  ) {
    return ListTile(
      leading: CircleAvatar(
        child: Icon(icon),
      ),
      title: Text(title),
      subtitle: Text(value),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'My Subscription',
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.stretch,
          children: [
            const Icon(
              Icons.workspace_premium,
              size: 75,
            ),
            const SizedBox(height: 15),
            Text(
              isActive
                  ? 'Subscription Active'
                  : 'No Active Subscription',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isActive
                  ? 'Your Social9 paid features are unlocked.'
                  : 'Choose a plan to unlock paid Social9 features.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 30),
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  children: [
                    infoRow(
                      Icons.card_membership,
                      'Current Plan',
                      planName,
                    ),
                    const Divider(),
                    infoRow(
                      Icons.verified,
                      'Status',
                      isActive
                          ? 'Active'
                          : 'Inactive',
                    ),
                    const Divider(),
                    infoRow(
                      Icons.auto_graph,
                      'Engagement Forecasting',
                      isActive
                          ? 'Unlocked'
                          : 'Locked',
                    ),
                    const Divider(),
                    infoRow(
                      Icons.auto_awesome,
                      'Caption AI',
                      isActive
                          ? 'Unlocked'
                          : 'Locked',
                    ),
                    const Divider(),
                    infoRow(
                      Icons.post_add,
                      'Create Post',
                      isActive
                          ? 'Unlocked'
                          : 'Locked',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 25),
            if (!isActive) ...[
              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  icon: const Icon(
                    Icons.workspace_premium,
                  ),
                  label: const Text(
                    'Choose a Plan',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                  },
                ),
              ),
              const SizedBox(height: 15),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Payment integration will be connected '
                    'after the UI is working correctly.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
            if (isActive) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Text(
                        'Subscription Features',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 15),
                      const Text(
                        'Create Post',
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Engagement Forecasting',
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Caption AI',
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Advanced Analytics',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                icon: const Icon(
                  Icons.cancel_outlined,
                ),
                label: const Text(
                  'Cancel Subscription',
                ),
                onPressed: () async {
                  await cancelSubscription();
                },
              ),
            ],
            const SizedBox(height: 30),
            const Divider(),
            const SizedBox(height: 10),
            const Text(
              'Development Testing',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'The buttons below are temporary local '
              'testing controls. Real payment verification '
              'will be connected through the backend later.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 15),
            OutlinedButton(
              onPressed: () {
                activateDemoSubscription('Pro');
              },
              child: const Text(
                'Activate Pro for Testing',
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () {
                activateDemoSubscription('Business');
              },
              child: const Text(
                'Activate Business for Testing',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
