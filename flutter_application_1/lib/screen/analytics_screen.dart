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
    analytics = AnalyticsService.summary();
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
          final metrics = data;
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
                      'Publishing performance',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.cloud_done),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Post activity across your connected accounts.',
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
                      'Total Posts',
                      metricValue(metrics, 'total_posts'),
                      Icons.visibility,
                      Colors.indigo,
                    ),
                    metricCard(
                      'Drafts',
                      metricValue(metrics, 'drafts'),
                      Icons.people_alt,
                      Colors.deepPurple,
                    ),
                    metricCard(
                      'Scheduled',
                      metricValue(metrics, 'scheduled'),
                      Icons.thumb_up_alt,
                      Colors.blue,
                    ),
                    metricCard(
                      'Published',
                      metricValue(metrics, 'published'),
                      Icons.comment,
                      Colors.teal,
                    ),
                    metricCard(
                      'Failed',
                      metricValue(metrics, 'failed'),
                      Icons.repeat,
                      Colors.orange,
                    ),
                    metricCard(
                      'Publishing',
                      metricValue(metrics, 'publishing'),
                      Icons.bookmark,
                      Colors.pink,
                    ),
                    metricCard(
                      'Provider Published',
                      metricValue(metrics, 'provider_published'),
                      Icons.send,
                      Colors.green,
                    ),
                    metricCard(
                      'Preview Published',
                      metricValue(metrics, 'preview_published'),
                      Icons.ads_click,
                      Colors.redAccent,
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
