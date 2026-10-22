import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/api_client.dart';
import '../core/checkout.dart';
import '../widgets/workspace_widgets.dart';
import 'billing_service.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});
  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  late Future<List<dynamic>> data;
  String duration = 'monthly';
  bool working = false;
  final coupon = TextEditingController();
  @override
  void initState() {
    super.initState();
    load();
  }

  void load() => setState(() {
    data = Future.wait([
      BillingService.subscription(),
      ApiClient.get('/billing/razorpay/config'),
      ApiClient.get('/billing/public-plans'),
    ]);
  });
  Future<void> subscribe(Map plan, Map config, bool mock) async {
    setState(() => working = true);
    try {
      final body = {
        'plan_code': plan['code'],
        'coupon_code': coupon.text.trim().isEmpty ? null : coupon.text.trim(),
      };
      final quote =
          await ApiClient.post('/billing/coupons/quote', body: body) as Map;
      final amount =
          quote['amount_minor'] ??
          quote['final_amount_minor'] ??
          (plan['total_price_inr'] as num) * 100;
      if (!mounted) return;
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Choose ${plan['name']}?'),
          content: Text(
            '${plan['commitment']} access for ₹${(amount as num) / 100}. ${config['test_mode'] == true ? 'Test checkout is enabled.' : ''}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (approved != true) return;
      final request = {
        ...body,
        'expected_amount_minor': (amount as num).toInt(),
      };
      if (amount == 0 && coupon.text.trim().isNotEmpty) {
        await ApiClient.post('/billing/coupons/redeem', body: request);
      } else if (mock) {
        await ApiClient.post('/billing/mock/subscribe', body: request);
      } else {
        final session =
            await ApiClient.post('/billing/razorpay/checkout', body: request)
                as Map;
        final response = await openCheckout(session);
        if (response == null) return;
        final subscription =
            await ApiClient.post('/billing/razorpay/verify', body: response)
                as Map;
        if (mounted) {
          showMessage(
            context,
            subscription['is_paid'] == true
                ? 'Your plan is active.'
                : 'Payment verified. Activation is awaiting confirmation.',
          );
        }
      }
      if (mounted) load();
    } catch (error) {
      if (mounted) showMessage(context, error);
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  @override
  void dispose() {
    coupon.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Plans & billing'),
      actions: [IconButton(onPressed: load, icon: const Icon(Icons.refresh))],
    ),
    body: FutureBuilder<List<dynamic>>(
      future: data,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return WorkspaceError(error: snapshot.error, retry: load);
        }
        final subscription = snapshot.data![0] as Map;
        final config = snapshot.data![1] as Map;
        final plans = ((snapshot.data![2] as Map)['plans'] as List)
            .cast<Map>()
            .where((p) => p['duration'] == duration)
            .toList();
        final end = DateTime.tryParse(
          subscription['current_period_end']?.toString() ?? '',
        );
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 60),
          children: [
            SectionCard(
              title: 'Your ${subscription['plan']} plan',
              children: [
                Text('Status: ${subscription['status']}'),
                if (end != null)
                  Text(
                    'Current period ends ${DateFormat('d MMM yyyy').format(end.toLocal())}',
                  ),
                const SizedBox(height: 10),
                Text(
                  subscription['is_paid'] == true
                      ? 'Paid features are active for your account.'
                      : 'Compare plans to unlock AI planning, growth insights, and collaboration.',
                ),
              ],
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'monthly', label: Text('Monthly')),
                  ButtonSegment(value: 'annual', label: Text('Annual')),
                  ButtonSegment(value: 'three_year', label: Text('3 years')),
                ],
                selected: {duration},
                onSelectionChanged: (values) =>
                    setState(() => duration = values.first),
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: coupon,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Coupon code (optional)',
                prefixIcon: Icon(Icons.local_offer_outlined),
              ),
            ),
            const SizedBox(height: 16),
            if (working) const LinearProgressIndicator(),
            LayoutBuilder(
              builder: (context, constraints) => Wrap(
                spacing: 12,
                runSpacing: 12,
                children: plans.map((plan) {
                  final features = plan['features'] as Map? ?? {};
                  return SizedBox(
                    width: constraints.maxWidth > 850
                        ? (constraints.maxWidth - 24) / 3
                        : constraints.maxWidth,
                    child: SectionCard(
                      title: plan['name'].toString(),
                      children: [
                        if (plan['badge'] != null)
                          Text(
                            plan['badge'].toString(),
                            style: const TextStyle(
                              color: Color(0xFF6D4AFF),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        Text(
                          '₹${plan['total_price_inr']}',
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '${plan['commitment']} • ₹${plan['monthly_equivalent_inr']} / month equivalent',
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '${features['brand_limit'] ?? 'Unlimited'} brands',
                        ),
                        Text(
                          '${features['competitor_limit'] ?? 0} competitor profiles',
                        ),
                        if (features['ai_assistant'] == true)
                          const Text(
                            'AI caption assistant and content planning',
                          ),
                        if (features['growth_projection'] == true)
                          const Text(
                            'Growth planning and engagement forecasting',
                          ),
                        if (features['publishing_reports'] == true)
                          const Text('Client publishing reports'),
                        if (features['team_workspace'] == true)
                          const Text('Team workspace and content approvals'),
                        if ((plan['savings_percent'] as num? ?? 0) > 0)
                          Text('Save ${plan['savings_percent']}%'),
                        const SizedBox(height: 18),
                        FilledButton(
                          onPressed:
                              working ||
                                  (config['enabled'] != true &&
                                      subscription['mock_mode'] != true)
                              ? null
                              : () => subscribe(
                                  plan,
                                  config,
                                  subscription['mock_mode'] == true,
                                ),
                          child: const Text('Choose plan'),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
            if (config['enabled'] != true && subscription['mock_mode'] != true)
              TextButton(
                onPressed: () => launchUrl(
                  Uri.parse(
                    'mailto:visionarycue.informatics@gmail.com?subject=Social9%20plan%20access',
                  ),
                ),
                child: const Text('Contact Social9 for plan access'),
              ),
            if (subscription['mock_mode'] == true &&
                subscription['is_paid'] == true)
              OutlinedButton(
                onPressed: working
                    ? null
                    : () async {
                        await BillingService.mockCancel();
                        if (mounted) load();
                      },
                child: const Text('Cancel test subscription'),
              ),
            Wrap(
              children: [
                TextButton(
                  onPressed: () =>
                      launchUrl(Uri.parse('https://www.social9.io/refunds')),
                  child: const Text('Refund policy'),
                ),
                TextButton(
                  onPressed: () =>
                      launchUrl(Uri.parse('https://www.social9.io/terms')),
                  child: const Text('Terms'),
                ),
                TextButton(
                  onPressed: () =>
                      launchUrl(Uri.parse('https://www.social9.io/privacy')),
                  child: const Text('Privacy'),
                ),
              ],
            ),
          ],
        );
      },
    ),
  );
}
