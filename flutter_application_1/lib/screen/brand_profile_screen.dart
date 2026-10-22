import 'package:flutter/material.dart';
import '../core/api_client.dart';
import '../widgets/workspace_widgets.dart';

class BrandProfileScreen extends StatefulWidget {
  const BrandProfileScreen({super.key});
  @override
  State<BrandProfileScreen> createState() => _BrandProfileScreenState();
}

class _BrandProfileScreenState extends State<BrandProfileScreen> {
  late Future<Map> profile;
  final fields = {
    for (final name in ['description', 'audience', 'voice', 'goal'])
      name: TextEditingController(),
  };
  String industry = '';
  bool saving = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  void load() {
    setState(() {
      profile = ApiClient.get('/ai/brand-profile').then((value) {
        final data = value as Map;
        for (final entry in fields.entries) {
          entry.value.text = data[entry.key]?.toString() ?? '';
        }
        industry = data['industry']?.toString() ?? '';
        return data;
      });
    });
  }

  Future<void> save() async {
    setState(() => saving = true);
    try {
      await ApiClient.put(
        '/ai/brand-profile',
        body: {
          'industry': industry,
          for (final entry in fields.entries)
            entry.key: entry.value.text.trim(),
        },
      );
      if (mounted) showMessage(context, 'Brand context saved.');
    } catch (error) {
      if (mounted) showMessage(context, error);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  void dispose() {
    for (final controller in fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Brand context')),
    body: FutureBuilder<Map>(
      future: profile,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return WorkspaceError(error: snapshot.error, retry: load);
        }
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Help Social9 tailor captions, templates, and your daily plan to your business.',
            ),
            const SizedBox(height: 18),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: industry,
              decoration: const InputDecoration(labelText: 'Industry'),
              items:
                  [
                        '',
                        'Restaurant',
                        'Retail',
                        'Salon',
                        'Fitness',
                        'Professional services',
                        'Any business',
                      ]
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(
                            value.isEmpty ? 'Choose industry' : value,
                          ),
                        ),
                      )
                      .toList(),
              onChanged: (value) => industry = value ?? '',
            ),
            const SizedBox(height: 14),
            for (final entry in fields.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: TextField(
                  controller: entry.value,
                  maxLines: entry.key == 'description' ? 4 : 2,
                  maxLength: entry.key == 'description'
                      ? 800
                      : entry.key == 'audience'
                      ? 500
                      : entry.key == 'voice'
                      ? 200
                      : 300,
                  decoration: InputDecoration(labelText: fieldLabel(entry.key)),
                ),
              ),
            FilledButton(
              onPressed: saving ? null : save,
              child: Text(saving ? 'Saving…' : 'Save brand context'),
            ),
          ],
        );
      },
    ),
  );
}
