import 'package:flutter/material.dart';

import 'analytics_service.dart';
import 'create_post_screen.dart';
import 'posts_screen.dart';
import 'settings_screen.dart';
import 'calendar_screen.dart';

class ActionCenterScreen extends StatefulWidget {
  const ActionCenterScreen({super.key});

  @override
  State<ActionCenterScreen> createState() => _ActionCenterScreenState();
}

class _ActionCenterScreenState extends State<ActionCenterScreen> {
  late Future<Map<String, dynamic>> actions;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  void refresh() {
    if (mounted) {
      setState(() {
        actions = AnalyticsService.actions();
      });
    }
  }

  void open(String href) {
    final Widget screen = href.startsWith('/accounts')
        ? const SettingsScreen()
        : href.startsWith('/create-post')
        ? const CreatePostScreen()
        : href.startsWith('/calendar')
        ? const CalendarScreen()
        : const PostsScreen();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => screen),
    ).then((_) => refresh());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Action center'),
      actions: [
        IconButton(onPressed: refresh, icon: const Icon(Icons.refresh)),
      ],
    ),
    body: FutureBuilder<Map<String, dynamic>>(
      future: actions,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: OutlinedButton(
              onPressed: refresh,
              child: const Text('Try again'),
            ),
          );
        }
        final data = snapshot.data!;
        final items = (data['actions'] as List? ?? []).cast<Map>();
        final summary = Map<String, dynamic>.from(
          data['summary'] as Map? ?? {},
        );
        return RefreshIndicator(
          onRefresh: () async => refresh(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 60),
            children: [
              Text(
                'Your next best moves.',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Social9 watches publishing, connections, and your near-term schedule.',
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _Summary(
                    label: 'Urgent',
                    value: summary['urgent'] ?? 0,
                    color: const Color(0xFFC33E43),
                  ),
                  _Summary(
                    label: 'Recommended',
                    value: summary['recommended'] ?? 0,
                    color: const Color(0xFFFF6A4D),
                  ),
                  _Summary(
                    label: 'This week',
                    value: summary['scheduled_this_week'] ?? 0,
                    color: const Color(0xFF6D4AFF),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 5,
                            height: 72,
                            decoration: BoxDecoration(
                              color: _priority(item['priority'].toString()),
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item['category'].toString().toUpperCase(),
                                  style: TextStyle(
                                    color: _priority(
                                      item['priority'].toString(),
                                    ),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  item['title'].toString(),
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(item['description'].toString()),
                                const SizedBox(height: 10),
                                TextButton.icon(
                                  onPressed: () =>
                                      open(item['href'].toString()),
                                  icon: const Icon(
                                    Icons.arrow_forward,
                                    size: 18,
                                  ),
                                  label: Text(item['action_label'].toString()),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );

  Color _priority(String value) => switch (value) {
    'urgent' => const Color(0xFFC33E43),
    'warning' => const Color(0xFFFF6A4D),
    'success' => const Color(0xFF16855A),
    _ => const Color(0xFF6D4AFF),
  };
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final Object value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Text(
      '$value  $label',
      style: TextStyle(color: color, fontWeight: FontWeight.w700),
    ),
  );
}
