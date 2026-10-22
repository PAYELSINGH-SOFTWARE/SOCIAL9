import 'package:flutter/material.dart';

import 'analytics_service.dart';
import 'provider_insights_screen.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  late Future<Map<String, dynamic>> analytics;
  int days = 30;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  void refresh() {
    setState(() {
      analytics = AnalyticsService.summary(days: days);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics'),
        actions: [
          IconButton(
            tooltip: 'Social insights',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProviderInsightsScreen()),
            ),
            icon: const Icon(Icons.insights_outlined),
          ),
          IconButton(onPressed: refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: analytics,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) return _error(snapshot.error.toString());
          final data = snapshot.data!;
          final overview = Map<String, dynamic>.from(
            data['overview'] as Map? ?? {},
          );
          final consistency = Map<String, dynamic>.from(
            data['consistency'] as Map? ?? {},
          );
          final channels = (data['channels'] as List? ?? []).cast<Map>();
          final suggestions = (data['suggestions'] as List? ?? []).cast<Map>();
          return RefreshIndicator(
            onRefresh: () async => refresh(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 60),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Know what is moving.',
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Real publishing results and provider data—never fabricated reach.',
                          ),
                        ],
                      ),
                    ),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 7, label: Text('7d')),
                        ButtonSegment(value: 30, label: Text('30d')),
                        ButtonSegment(value: 90, label: Text('90d')),
                      ],
                      selected: {days},
                      onSelectionChanged: (value) {
                        days = value.first;
                        refresh();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth > 720
                        ? (constraints.maxWidth - 36) / 4
                        : (constraints.maxWidth - 12) / 2;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _Metric(
                          width,
                          'Published',
                          overview['published'] ?? 0,
                          Icons.check_circle_outline,
                          const Color(0xFF16855A),
                        ),
                        _Metric(
                          width,
                          'Scheduled',
                          overview['scheduled'] ?? 0,
                          Icons.schedule_outlined,
                          const Color(0xFF5B49D6),
                        ),
                        _Metric(
                          width,
                          'Drafts',
                          overview['drafts'] ?? 0,
                          Icons.edit_note_outlined,
                          const Color(0xFF596170),
                        ),
                        _Metric(
                          width,
                          'Success rate',
                          '${overview['publish_success_rate'] ?? 0}%',
                          Icons.trending_up,
                          const Color(0xFFFF6A4D),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        _Score(value: _momentum(overview, consistency)),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Workspace momentum',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                consistency['message']?.toString() ??
                                    'Keep building a consistent publishing rhythm.',
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${consistency['current_streak'] ?? 0} week streak • ${consistency['days_remaining'] ?? 0} days left this week',
                                style: const TextStyle(color: Colors.black54),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  'Channel health',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                for (final channel in channels)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 8,
                        ),
                        leading: CircleAvatar(
                          child: Icon(
                            channel['provider'] == 'instagram'
                                ? Icons.camera_alt_outlined
                                : Icons.work_outline,
                          ),
                        ),
                        title: Text(_title(channel['provider'].toString())),
                        subtitle: Text(
                          '${channel['post_count']} posts • ${channel['published']} published • ${channel['scheduled']} scheduled',
                        ),
                        trailing: Icon(
                          channel['connected'] == true
                              ? Icons.check_circle
                              : Icons.link_off,
                          color: channel['connected'] == true
                              ? Colors.green
                              : Colors.black38,
                        ),
                      ),
                    ),
                  ),
                if (suggestions.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    'What to improve next',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final suggestion in suggestions)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.auto_awesome,
                                color: Color(0xFF6D4AFF),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      suggestion['title'].toString(),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(suggestion['body'].toString()),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  int _momentum(
    Map<String, dynamic> overview,
    Map<String, dynamic> consistency,
  ) {
    final connected = (overview['connected_accounts'] as num?)?.toInt() ?? 0;
    final published = (overview['published'] as num?)?.toInt() ?? 0;
    final scheduled = (overview['scheduled'] as num?)?.toInt() ?? 0;
    final streak = (consistency['current_streak'] as num?)?.toInt() ?? 0;
    return (connected * 15 + published * 6 + scheduled * 5 + streak * 10).clamp(
      0,
      100,
    );
  }

  Widget _error(String message) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.cloud_off, size: 48),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: refresh, child: const Text('Try again')),
      ],
    ),
  );

  static String _title(String value) =>
      '${value[0].toUpperCase()}${value.substring(1)}';
}

class _Metric extends StatelessWidget {
  const _Metric(this.width, this.label, this.value, this.icon, this.color);
  final double width;
  final String label;
  final Object value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 14),
            Text(
              '$value',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            Text(label, style: const TextStyle(color: Colors.black54)),
          ],
        ),
      ),
    ),
  );
}

class _Score extends StatelessWidget {
  const _Score({required this.value});
  final int value;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 82,
    child: Stack(
      alignment: Alignment.center,
      children: [
        CircularProgressIndicator(
          value: value / 100,
          strokeWidth: 8,
          backgroundColor: const Color(0xFFEAE7F2),
        ),
        Text(
          '$value',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}
