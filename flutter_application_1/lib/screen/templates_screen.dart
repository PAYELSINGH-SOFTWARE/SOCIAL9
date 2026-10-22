import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/api_client.dart';
import '../widgets/workspace_widgets.dart';
import 'account_service.dart';
import 'brand_service.dart';
import 'brand_profile_screen.dart';
import 'create_post_screen.dart';

class TemplatesScreen extends StatefulWidget {
  const TemplatesScreen({super.key});
  @override
  State<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends State<TemplatesScreen> {
  late Future<List<dynamic>> data;
  String goal = 'All';
  String search = '';
  @override
  void initState() {
    super.initState();
    load();
  }

  void load() => setState(() {
    data = Future.wait([
      rootBundle
          .loadString('assets/content_templates.json')
          .then((text) => jsonDecode(text)),
      ApiClient.get('/ai/brand-profile'),
      AccountService.list(),
      BrandService.list(),
    ]);
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Templates'),
      actions: [
        IconButton(
          tooltip: 'Brand context',
          onPressed: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BrandProfileScreen()),
            );
            if (mounted) load();
          },
          icon: const Icon(Icons.tune),
        ),
      ],
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
        final profile = snapshot.data![1] as Map;
        final channels = (snapshot.data![2] as List)
            .cast<Map>()
            .where((a) => a['status'] == 'connected')
            .map((a) => a['provider'].toString())
            .toSet();
        final items = (snapshot.data![0] as List)
            .cast<Map>()
            .where(
              (item) =>
                  (goal == 'All' || item['goal'] == goal) &&
                  '${item['title']} ${item['caption']} ${item['industry']}'
                      .toLowerCase()
                      .contains(search.toLowerCase()),
            )
            .toList();
        items.sort(
          (a, b) => _score(
            b,
            profile,
            channels,
          ).compareTo(_score(a, profile, channels)),
        );
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 60),
          children: [
            Text(
              'Ideas shaped for your brand.',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'The same 26 templates as Social9 web, ranked by your industry, goals, and connected channels.',
            ),
            const SizedBox(height: 16),
            TextField(
              decoration: const InputDecoration(
                hintText: 'Search templates',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (text) => setState(() => search = text),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children:
                    [
                          'All',
                          'Promotion',
                          'Engagement',
                          'Awareness',
                          'Trust',
                          'Education',
                        ]
                        .map(
                          (value) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(value),
                              selected: goal == value,
                              onSelected: (_) => setState(() => goal = value),
                            ),
                          ),
                        )
                        .toList(),
              ),
            ),
            const SizedBox(height: 16),
            if (items.isEmpty) const Text('No templates match this search.'),
            for (final item in items)
              SectionCard(
                title: item['title'].toString(),
                children: [
                  Text(
                    '${item['goal']} • ${item['format']} • ${item['industry']}',
                    style: const TextStyle(color: Color(0xFF6D4AFF)),
                  ),
                  const SizedBox(height: 10),
                  Text(item['caption'].toString()),
                  const SizedBox(height: 8),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Creative brief'),
                    children: [
                      ListTile(
                        title: const Text('Visual'),
                        subtitle: Text(item['visual'].toString()),
                      ),
                      ListTile(
                        title: const Text('Call to action'),
                        subtitle: Text(item['cta'].toString()),
                      ),
                      ListTile(
                        title: const Text('Timing idea'),
                        subtitle: Text(item['bestTime'].toString()),
                      ),
                    ],
                  ),
                  Text(
                    (item['hashtags'] as List).join(' '),
                    style: const TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children:
                        (item['platform'] == 'both'
                                ? ['instagram', 'linkedin', 'facebook']
                                : [item['platform'].toString()])
                            .map(
                              (channel) => OutlinedButton(
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => CreatePostScreen(
                                      initialCaption:
                                          '${item['caption']}\n\n${item['cta']}\n\n${(item['hashtags'] as List).join(' ')}',
                                      initialPlatform: channel,
                                    ),
                                  ),
                                ),
                                child: Text('Use for ${fieldLabel(channel)}'),
                              ),
                            )
                            .toList(),
                  ),
                ],
              ),
          ],
        );
      },
    ),
  );
  int _score(Map template, Map profile, Set<String> channels) =>
      (template['industry'] == profile['industry']
          ? 8
          : template['industry'] == 'Any business'
          ? 2
          : 0) +
      (channels.contains(template['platform']) || template['platform'] == 'both'
          ? 3
          : 0) +
      (profile['goal'].toString().toLowerCase().contains(
            template['goal'].toString().toLowerCase(),
          )
          ? 5
          : 0);
}
