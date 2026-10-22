import 'package:flutter/material.dart';
import 'dart:async';
import 'package:url_launcher/url_launcher.dart';

import '../core/api_client.dart';
import '../core/oauth_window.dart';
import 'account_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  late Future<_AccountData> data;
  String? workingProvider;
  OAuthWindow? oauthWindow;
  Timer? connectionTimer;
  int pollCount = 0;
  bool polling = false;
  List<Map<String, dynamic>> lastAccounts = [];
  String? authorizationUrl;
  bool openedManually = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    refresh();
  }

  @override
  void dispose() {
    connectionTimer?.cancel();
    oauthWindow?.close();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  void refresh() => setState(() {
    data = Future.wait([
      AccountService.list(),
      AccountService.providerStatus(),
    ]).then((values) => _AccountData(values[0], values[1]));
  });

  Future<void> connect(String provider) async {
    // Reserve the browser window while the user gesture is still active.
    final window = reserveOAuthWindow();
    if (window == null) {
      _message('Allow pop-ups for Social9, then tap Connect again.');
      return;
    }
    oauthWindow = window;
    setState(() => workingProvider = provider);
    try {
      final baseline = lastAccounts
          .where((a) => a['provider'] == provider)
          .map((a) => '${a['id']}:${a['expires_at']}:${a['status']}')
          .toSet();
      final url = await AccountService.authorizationUrl(provider);
      if (mounted) setState(() => authorizationUrl = url);
      if (!mounted) {
        window.close();
        return;
      }
      await window.navigate(url);
      pollCount = 0;
      connectionTimer?.cancel();
      connectionTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
        if (polling || !mounted) return;
        polling = true;
        try {
          final accounts = await AccountService.list();
          final connected = accounts.any(
            (a) =>
                a['provider'] == provider &&
                a['status'] == 'connected' &&
                !baseline.contains(
                  '${a['id']}:${a['expires_at']}:${a['status']}',
                ),
          );
          if (connected) {
            _finishConnection();
            if (mounted) {
              refresh();
              _message('${_title(provider)} connected successfully.');
            }
          } else if ((!openedManually && window.closed) || ++pollCount >= 100) {
            _finishConnection();
            if (mounted) {
              refresh();
              _message('Connection was not completed. You can try again.');
            }
          }
        } catch (_) {
          if (++pollCount >= 100) _finishConnection();
        } finally {
          polling = false;
        }
      });
    } catch (error) {
      _finishConnection();
      if (mounted) _message(error.toString());
    }
  }

  void _finishConnection() {
    connectionTimer?.cancel();
    oauthWindow?.close();
    oauthWindow = null;
    authorizationUrl = null;
    openedManually = false;
    if (mounted) setState(() => workingProvider = null);
  }

  Future<void> disconnect(Map<String, dynamic> account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Disconnect ${account['account_name']}?'),
        content: const Text(
          'Scheduled posts for this channel may no longer publish.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await AccountService.disconnect(account['id'] as int);
      refresh();
    } on ApiException catch (error) {
      if (mounted) _message(error.message);
    }
  }

  void _message(String value) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(value)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Accounts'),
        actions: [
          IconButton(onPressed: refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: FutureBuilder<_AccountData>(
        future: data,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) return _error(snapshot.error.toString());
          final accountData = snapshot.data!;
          lastAccounts = accountData.accounts;
          return RefreshIndicator(
            onRefresh: () async => refresh(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 60),
              children: [
                Text(
                  'Connect your channels.',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Publish and schedule from Social9. Your provider credentials remain protected by the backend.',
                ),
                const SizedBox(height: 22),
                if (workingProvider != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Complete ${_title(workingProvider!)} authorization in the browser. Return here when finished; Social9 will detect the connection automatically.',
                          ),
                          if (authorizationUrl != null)
                            FilledButton.tonalIcon(
                              onPressed: () {
                                openedManually = true;
                                launchUrl(
                                  Uri.parse(authorizationUrl!),
                                  mode: LaunchMode.externalApplication,
                                  webOnlyWindowName: '_blank',
                                );
                              },
                              icon: const Icon(Icons.open_in_new),
                              label: Text(
                                'Continue to ${_title(workingProvider!)}',
                              ),
                            ),
                          TextButton(
                            onPressed: _finishConnection,
                            child: const Text('Cancel connection'),
                          ),
                        ],
                      ),
                    ),
                  ),
                for (final provider in accountData.providers)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _providerCard(provider, accountData.accounts),
                  ),
                if (accountData.accounts.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text(
                    'Connected profiles',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final account in accountData.accounts)
                    Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 8,
                        ),
                        leading: CircleAvatar(
                          child: Icon(_icon(account['provider'].toString())),
                        ),
                        title: Text(
                          account['account_name']?.toString() ??
                              account['provider'].toString(),
                        ),
                        subtitle: Text(
                          '${account['provider']} • ${account['status']}',
                        ),
                        trailing: IconButton(
                          tooltip: 'Disconnect',
                          onPressed: () => disconnect(account),
                          icon: const Icon(Icons.link_off),
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

  Widget _providerCard(
    Map<String, dynamic> provider,
    List<Map<String, dynamic>> accounts,
  ) {
    final name = provider['provider'].toString();
    final configured = provider['configured'] == true;
    final preview = provider['mode'] == 'preview';
    final comingSoon = [
      'threads',
      'youtube',
      'twitter',
      'pinterest',
    ].contains(name);
    final connected = accounts.any(
      (item) => item['provider'] == name && item['status'] == 'connected',
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            CircleAvatar(radius: 25, child: Icon(_icon(name))),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _title(name),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    connected
                        ? 'Connected and ready'
                        : configured
                        ? (preview
                              ? 'Preview connection available'
                              : 'Ready to connect')
                        : 'Provider setup required',
                    style: const TextStyle(color: Colors.black54),
                  ),
                ],
              ),
            ),
            FilledButton(
              onPressed: configured && workingProvider == null && !comingSoon
                  ? () => connect(name)
                  : null,
              child: workingProvider == name
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      comingSoon
                          ? 'Coming soon'
                          : connected
                          ? 'Reconnect'
                          : 'Connect',
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _error(String message) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
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
    ),
  );

  static IconData _icon(String provider) => switch (provider) {
    'instagram' => Icons.camera_alt_outlined,
    'facebook' => Icons.facebook,
    'linkedin' => Icons.work_outline,
    _ => Icons.public,
  };
  static String _title(String value) =>
      const {
        'instagram': 'Instagram',
        'linkedin': 'LinkedIn',
        'facebook': 'Facebook',
        'threads': 'Threads',
        'youtube': 'YouTube',
        'twitter': 'X',
        'pinterest': 'Pinterest',
      }[value] ??
      value;
}

class _AccountData {
  const _AccountData(this.accounts, this.providers);
  final List<Map<String, dynamic>> accounts;
  final List<Map<String, dynamic>> providers;
}
