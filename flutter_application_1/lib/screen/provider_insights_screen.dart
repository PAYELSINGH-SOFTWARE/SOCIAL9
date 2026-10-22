import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/api_client.dart';
import '../core/export_file.dart';
import '../widgets/workspace_widgets.dart';
import 'analytics_service.dart';
import 'brand_profile_screen.dart';

class ProviderInsightsScreen extends StatefulWidget {
  const ProviderInsightsScreen({super.key});
  @override
  State<ProviderInsightsScreen> createState() => _ProviderInsightsScreenState();
}

class _ProviderInsightsScreenState extends State<ProviderInsightsScreen> {
  late Future<Map<String, dynamic>> data;
  int days = 30;
  String provider = 'instagram';
  String metric = 'reach';
  String contentType = 'all';
  int? pageId;
  Map? projection;
  bool working = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  void load() {
    setState(() {
      data = AnalyticsService.summary(days: days);
    });
  }

  Future<void> project(bool forecast) async {
    final fields = await askFields(
      context,
      forecast ? 'Forecast engagement' : 'Plan growth scenarios',
      forecast
          ? {'forecast_days': '7'}
          : {
              'current_monthly_reach': '10000',
              'current_engagement_rate': '4',
              'target_posts_per_week': '4',
              'horizon_days': '30',
            },
      choices: forecast
          ? {
              'forecast_days': ['7', '14', '30'],
            }
          : {
              'horizon_days': ['30', '90'],
            },
    );
    if (fields == null) return;
    setState(() => working = true);
    try {
      final result =
          await ApiClient.post(
                forecast
                    ? '/analytics/engagement-forecast'
                    : '/analytics/growth-projection',
                body: {
                  for (final field in fields.entries)
                    field.key: num.tryParse(field.value) ?? field.value,
                },
              )
              as Map;
      if (mounted) setState(() => projection = result);
    } catch (error) {
      if (mounted) showMessage(context, error);
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Social insights'),
      actions: [IconButton(onPressed: load, icon: const Icon(Icons.refresh))],
    ),
    body: FutureBuilder<Map<String, dynamic>>(
      future: data,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return WorkspaceError(error: snapshot.error, retry: load);
        }
        final summary = snapshot.data!;
        final all = summary['provider_metrics'] as Map? ?? {};
        final root = all[provider] as Map?;
        final pages = (root?['pages'] as List? ?? []).cast<Map>();
        final active =
            pages.where((page) => page['account_id'] == pageId).firstOrNull ??
            root;
        final daily = (active?['daily'] as List? ?? []).cast<Map>();
        final content =
            (active?['content'] as List? ?? active?['top_media'] as List? ?? [])
                .cast<Map>()
                .where(
                  (item) =>
                      contentType == 'all' || item['media_type'] == contentType,
                )
                .toList();
        final available = (active?['available_metrics'] as List?)
            ?.cast<String>();
        final keys = provider == 'instagram'
            ? [
                'followers',
                'reach',
                'impressions',
                'interactions',
                'likes',
                'comments',
                'shares',
                'saves',
                'engagement_rate',
              ]
            : [
                'followers',
                'views',
                'unique_viewers',
                'engagements',
                'followers_gained',
                'net_followers',
              ];
        final trendMetrics = provider == 'instagram'
            ? ['reach', 'impressions', 'interactions', 'followers_gained']
            : ['views', 'unique_viewers', 'engagements', 'followers_gained'];
        final selectedMetric = trendMetrics.contains(metric)
            ? metric
            : trendMetrics.first;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 60),
          children: [
            Wrap(
              spacing: 8,
              children: ['instagram', 'facebook', 'linkedin']
                  .map(
                    (value) => ChoiceChip(
                      label: Text(
                        value == 'linkedin' ? 'LinkedIn' : fieldLabel(value),
                      ),
                      selected: provider == value,
                      onSelected: (_) => setState(() {
                        provider = value;
                        pageId = null;
                        contentType = 'all';
                      }),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
            SegmentedButton<int>(
              segments: [
                for (final d in [7, 30, 90])
                  ButtonSegment(value: d, label: Text('$d days')),
              ],
              selected: {days},
              onSelectionChanged: (value) {
                days = value.first;
                load();
              },
            ),
            const SizedBox(height: 18),
            if (provider == 'linkedin')
              const SectionCard(
                title: 'LinkedIn analytics',
                children: [
                  Text(
                    'LinkedIn requires separate analytics approval. Publishing and account connections are available; metrics appear when the provider grants access.',
                  ),
                ],
              )
            else if (active == null || active['available'] == false)
              SectionCard(
                title: 'Connect performance to your plan',
                children: [
                  Text(
                    (summary['provider_metrics_reasons'] as Map?)?[provider]
                            ?.toString() ??
                        summary['provider_metrics_reason']?.toString() ??
                        'Connect your account and grant insight permissions.',
                  ),
                ],
              )
            else ...[
              if (pages.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: DropdownButtonFormField<int>(
                    initialValue: pageId,
                    decoration: const InputDecoration(
                      labelText: 'Facebook Page',
                    ),
                    items: [
                      const DropdownMenuItem<int>(
                        value: null,
                        child: Text('All Pages'),
                      ),
                      ...pages.map(
                        (page) => DropdownMenuItem(
                          value: page['account_id'] as int,
                          child: Text(page['account_name'].toString()),
                        ),
                      ),
                    ],
                    onChanged: (id) => setState(() => pageId = id),
                  ),
                ),
              LayoutBuilder(
                builder: (context, constraints) => Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: keys.map((key) {
                    final missing =
                        available != null &&
                        !available.contains(
                          key == 'interactions' ? 'total_interactions' : key,
                        );
                    return SizedBox(
                      width: constraints.maxWidth > 650
                          ? (constraints.maxWidth - 30) / 4
                          : (constraints.maxWidth - 10) / 2,
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                missing || active[key] == null
                                    ? 'Unavailable'
                                    : '${active[key]}${key == 'engagement_rate' ? '%' : ''}',
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                fieldLabel(key),
                                style: const TextStyle(color: Colors.black54),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 16),
              if (daily.isNotEmpty)
                SectionCard(
                  title: 'Performance over time',
                  children: [
                    DropdownButton<String>(
                      isExpanded: true,
                      value: selectedMetric,
                      items: trendMetrics
                          .map(
                            (key) => DropdownMenuItem(
                              value: key,
                              child: Text(fieldLabel(key)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setState(() => metric = value!),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      height: 180,
                      child: BarChart(
                        BarChartData(
                          gridData: const FlGridData(show: false),
                          borderData: FlBorderData(show: false),
                          titlesData: const FlTitlesData(show: false),
                          barGroups: [
                            for (var i = 0; i < daily.length; i++)
                              BarChartGroupData(
                                x: i,
                                barRods: [
                                  BarChartRodData(
                                    toY:
                                        (daily[i][selectedMetric] as num?)
                                            ?.toDouble() ??
                                        0,
                                    color: const Color(0xFF6D4AFF),
                                    width: 8,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text('${daily.first['date']} – ${daily.last['date']}'),
                    TextButton.icon(
                      onPressed: () =>
                          exportCsv('social9-$provider-$days-days.csv', [
                            ['Date', ...trendMetrics],
                            ...daily.map(
                              (row) => [
                                row['date'],
                                ...trendMetrics.map((key) => row[key]),
                              ],
                            ),
                          ]),
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('Export CSV'),
                    ),
                  ],
                ),
              SectionCard(
                title: 'Content performance',
                children: [
                  if (provider == 'instagram')
                    DropdownButton<String>(
                      value: contentType,
                      isExpanded: true,
                      items: [
                        const DropdownMenuItem(
                          value: 'all',
                          child: Text('All formats'),
                        ),
                        ...((active['content'] as List? ??
                                active['top_media'] as List? ??
                                [])
                            .cast<Map>()
                            .map((p) => p['media_type']?.toString())
                            .whereType<String>()
                            .toSet()
                            .map(
                              (type) => DropdownMenuItem(
                                value: type,
                                child: Text(type),
                              ),
                            )),
                      ],
                      onChanged: (value) =>
                          setState(() => contentType = value!),
                    ),
                  if (content.isEmpty)
                    const Text('No content metrics are available.'),
                  for (final item in content.take(20))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        item['caption']?.toString() ?? 'Social post',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${item['interactions'] ?? 'Unavailable'} interactions • ${item['published_at'] ?? ''}',
                      ),
                      trailing: item['permalink'] == null
                          ? null
                          : IconButton(
                              tooltip: 'View post',
                              onPressed: () => launchUrl(
                                Uri.parse(item['permalink'].toString()),
                                mode: LaunchMode.externalApplication,
                              ),
                              icon: const Icon(Icons.open_in_new),
                            ),
                    ),
                ],
              ),
            ],
            SectionCard(
              title: 'Growth planning',
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: working ? null : () => project(false),
                      child: const Text('Calculate scenarios'),
                    ),
                    OutlinedButton(
                      onPressed: working ? null : () => project(true),
                      child: const Text('Forecast engagement'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const BrandProfileScreen(),
                        ),
                      ),
                      child: const Text('Edit brand context'),
                    ),
                  ],
                ),
                if (working) const LinearProgressIndicator(),
                if (projection != null) ...[
                  const SizedBox(height: 12),
                  if (projection!['scenarios'] is List)
                    for (final scenario
                        in (projection!['scenarios'] as List).cast<Map>())
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(scenario['name'].toString()),
                        subtitle: Text(
                          'Reach ${scenario['projected_reach']} • Engagement ${scenario['projected_engagement_rate']}% • Interactions ${scenario['projected_interactions']}',
                        ),
                      ),
                  if (projection!['predictions'] is List) ...[
                    Text(
                      'Average predicted engagement: ${projection!['average_predicted_engagement']}',
                    ),
                    for (final prediction
                        in (projection!['predictions'] as List).cast<Map>())
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(prediction['date'].toString()),
                        trailing: Text('${prediction['predicted_engagement']}'),
                      ),
                  ],
                  Text(
                    projection!['methodology']?.toString() ??
                        projection!['disclaimer']?.toString() ??
                        '',
                  ),
                ],
              ],
            ),
          ],
        );
      },
    ),
  );
}
