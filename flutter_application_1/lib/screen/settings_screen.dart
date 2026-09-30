import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'account_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  late Future<List<dynamic>> accounts;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  void refresh() {
    setState(() {
      accounts = AccountService.list();
    });
  }

  Future<void> connect(String provider) async {
    try {
      final url = Uri.parse(await AccountService.authorizationUrl(provider));
      final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!opened) throw Exception('Could not open the authorization page');
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connected Accounts'),
        actions: [
          IconButton(onPressed: refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: FutureBuilder<List<dynamic>>(
        future: accounts,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text(snapshot.error.toString()));
          }
          return RefreshIndicator(
            onRefresh: () async => refresh(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: (snapshot.data ?? []).map((item) {
                final account = item as Map<String, dynamic>;
                final provider = account['provider'] as String;
                final configured = account['configured'] == true;
                final connected = account['connected'] == true;
                return Card(
                  child: ListTile(
                    leading: Icon(
                      provider == 'instagram' ? Icons.camera_alt : Icons.work,
                    ),
                    title: Text(
                      provider == 'instagram' ? 'Instagram' : 'LinkedIn',
                    ),
                    subtitle: Text(
                      connected
                          ? account['display_name'] ?? 'Connected'
                          : configured
                          ? 'Ready to connect'
                          : 'Developer credentials required',
                    ),
                    trailing: connected
                        ? const Chip(label: Text('Connected'))
                        : ElevatedButton(
                            onPressed: configured
                                ? () => connect(provider)
                                : null,
                            child: const Text('Connect'),
                          ),
                  ),
                );
              }).toList(),
            ),
          );
        },
      ),
    );
  }
}

