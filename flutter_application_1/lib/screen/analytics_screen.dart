import 'package:flutter/material.dart';

import 'analytics_service.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  late Future<Map<String, dynamic>> analytics;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  void refresh() => setState(() {
    analytics = AnalyticsService.performance();
  });

  String metricValue(Map<String, dynamic> metrics, String key) {
    final value = metrics[key];
    return value == null ? '—' : value.toString();
  }

  Widget metricCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 30),
            const SizedBox(height: 10),
            Text(
              value,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(title, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Performance Analytics'),
        actions: [
          IconButton(onPressed: refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: analytics,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(snapshot.error.toString()),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: refresh,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final data = snapshot.data!;
          final available = data['available'] == true;
          final metrics = data['metrics'] as Map<String, dynamic>;
          final reason = data['reason']?.toString();
          return RefreshIndicator(
            onRefresh: () async => refresh(),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Row(
                  children: [
                    const Icon(Icons.work, color: Colors.blue),
                    const SizedBox(width: 8),
                    Text(
                      'LinkedIn post performance',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: available
                        ? Colors.green.withValues(alpha: 0.12)
                        : Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(available ? Icons.cloud_done : Icons.lock_outline),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          available
                              ? 'Live lifetime metrics from LinkedIn.'
                              : reason ?? 'LinkedIn analytics is unavailable.',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: MediaQuery.sizeOf(context).width > 700
                      ? 4
                      : 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.25,
                  children: [
                    metricCard(
                      'Impressions',
                      metricValue(metrics, 'impressions'),
                      Icons.visibility,
                      Colors.indigo,
                    ),
                    metricCard(
                      'Members Reached',
                      metricValue(metrics, 'members_reached'),
                      Icons.people_alt,
                      Colors.deepPurple,
                    ),
                    metricCard(
                      'Reactions',
                      metricValue(metrics, 'reactions'),
                      Icons.thumb_up_alt,
                      Colors.blue,
                    ),
                    metricCard(
                      'Comments',
                      metricValue(metrics, 'comments'),
                      Icons.comment,
                      Colors.teal,
                    ),
                    metricCard(
                      'Reshares',
                      metricValue(metrics, 'reshares'),
                      Icons.repeat,
                      Colors.orange,
                    ),
                    metricCard(
                      'Post Saves',
                      metricValue(metrics, 'post_saves'),
                      Icons.bookmark,
                      Colors.pink,
                    ),
                    metricCard(
                      'Post Sends',
                      metricValue(metrics, 'post_sends'),
                      Icons.send,
                      Colors.green,
                    ),
                    metricCard(
                      'Link Clicks',
                      metricValue(metrics, 'link_clicks'),
                      Icons.ads_click,
                      Colors.redAccent,
                    ),
                  ],
                ),
                if (!available) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Values are intentionally shown as — until LinkedIn grants '
                    'analytics access. vCueSocial9 does not display estimated or '
                    'fabricated engagement numbers.',
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

