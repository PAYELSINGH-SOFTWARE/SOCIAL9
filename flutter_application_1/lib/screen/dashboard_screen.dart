
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_client.dart';
import '../core/workspace_session.dart';
import '../widgets/brand_switcher.dart';
import 'brand_profile_screen.dart';
import 'agency_screen.dart';
import 'action_center_screen.dart';
import 'analytics_screen.dart';
import 'analytics_service.dart';
import 'calendar_screen.dart';
import 'create_post_screen.dart';
import 'login_screen.dart';
import 'posts_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';
import 'subscription_screen.dart';
import 'templates_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<Map<String, dynamic>> summary;
  String name = 'there';
  final scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    refresh();
    WorkspaceSession.brandId.addListener(refresh);
    _loadName();
  }

  @override
  void dispose() {
    WorkspaceSession.brandId.removeListener(refresh);
    super.dispose();
  }

  Future<void> _loadName() async {
    final saved = (await SharedPreferences.getInstance()).getString(
      'user_name',
    );
    if (mounted && saved != null && saved.trim().isNotEmpty) {
      setState(() => name = saved.split(' ').first);
    }
  }

  void refresh() {
    if (mounted) {
      setState(() {
        summary = AnalyticsService.summary();
      });
    }
  }

  Future<void> logout() async {
    await WorkspaceSession.clear();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  Future<void> open(Widget page) async {
    scaffoldKey.currentState?.closeDrawer();
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    refresh();
  }

  @override
  Widget build(BuildContext context) {
    final dashboardTheme = Theme.of(context).copyWith(
      cardTheme: const CardThemeData(
        elevation: 6,
        shadowColor: Color(0x33000000),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
        ),
      ),
    );

    return Theme(
      data: dashboardTheme,
      child: Scaffold(
        key: scaffoldKey,
        appBar: AppBar(
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(48),
            child: BrandSwitcher(),
          ),
          title: Row(
            children: [
              Image.asset(
                'assets/images/social9-web-mark.png',
                width: 34,
                height: 34,
              ),
              const SizedBox(width: 9),
              const Text(
                'Social9',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: refresh,
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: 'Profile',
              onPressed: () => open(const ProfileScreen()),
              icon: const Icon(Icons.account_circle_outlined),
            ),
          ],
        ),
        drawer: _WorkspaceDrawer(onOpen: open, onLogout: logout),
        bottomNavigationBar: NavigationBar(
          height: 72,
          elevation: 12,
          shadowColor: const Color(0x33000000),
          selectedIndex: 0,
          onDestinationSelected: (index) {
            switch (index) {
              case 0:
                // Home is already open.
                break;
              case 1:
                open(const CreatePostScreen());
                break;
              case 2:
                open(const CalendarScreen());
                break;
              case 3:
                open(const ActionCenterScreen());
                break;
              case 4:
                open(const ProfileScreen());
                break;
            }
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.add_box_outlined),
              label: 'Create Post',
            ),
            NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined),
              label: 'Calendar',
            ),
            NavigationDestination(
              icon: Icon(Icons.bolt_outlined),
              label: 'Action Center',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              label: 'Profile',
            ),
          ],
        ),
        body: FutureBuilder<Map<String, dynamic>>(
          future: summary,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) return _error(snapshot.error);
            return _dashboard(snapshot.data!);
          },
        ),
      ),
    );
  }

  Widget _dashboard(Map<String, dynamic> data) {
    final overview = Map<String, dynamic>.from(data['overview'] as Map? ?? {});
    final consistency = Map<String, dynamic>.from(
      data['consistency'] as Map? ?? {},
    );
    final upcoming = (data['upcoming_posts'] as List? ?? []).cast<Map>();
    final suggestions = (data['suggestions'] as List? ?? []).cast<Map>();

    return RefreshIndicator(
      onRefresh: () async => refresh(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Good to see you, $name.',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Your content, schedule, and insights—together in one workspace.',
                ),
                const SizedBox(height: 22),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth > 760
                        ? (constraints.maxWidth - 36) / 4
                        : (constraints.maxWidth - 12) / 2;

                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _MetricCard(
                          width: width,
                          label: 'Published',
                          value: overview['published'] ?? 0,
                          icon: Icons.check_circle_outline,
                          color: const Color(0xFF16855A),
                        ),
                        _MetricCard(
                          width: width,
                          label: 'Scheduled',
                          value: overview['scheduled'] ?? 0,
                          icon: Icons.schedule,
                          color: const Color(0xFF6D4AFF),
                        ),
                        _MetricCard(
                          width: width,
                          label: 'Drafts',
                          value: overview['drafts'] ?? 0,
                          icon: Icons.edit_note,
                          color: const Color(0xFF596170),
                        ),
                        _MetricCard(
                          width: width,
                          label: 'Connected',
                          value: overview['connected_accounts'] ?? 0,
                          icon: Icons.link,
                          color: const Color(0xFFFF6A4D),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth > 760;
                    final focus = _FocusCard(
                      consistency: consistency,
                      overview: overview,
                      onOpen: () => open(const CalendarScreen()),
                    );
                    final quick = _QuickActions(onOpen: open);

                    return wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 3, child: focus),
                              const SizedBox(width: 14),
                              Expanded(flex: 2, child: quick),
                            ],
                          )
                        : Column(
                            children: [
                              focus,
                              const SizedBox(height: 14),
                              quick,
                            ],
                          );
                  },
                ),
                if (suggestions.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  _heading('For you', 'Recommendations'),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 155,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: suggestions.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 10),
                      itemBuilder: (context, index) {
                        final item = suggestions[index];

                        return SizedBox(
                          width: 280,
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.auto_awesome,
                                    color: Color(0xFF6D4AFF),
                                    size: 20,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    item['title'].toString(),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Expanded(
                                    child: Text(
                                      item['body'].toString(),
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                _heading('Coming up', 'Next scheduled posts'),
                const SizedBox(height: 10),
                Card(
                  child: upcoming.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(22),
                          child: Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Nothing scheduled yet. Give your next idea a time slot.',
                                ),
                              ),
                              TextButton(
                                onPressed: () => open(const CreatePostScreen()),
                                child: const Text('Schedule a post'),
                              ),
                            ],
                          ),
                        )
                      : Column(
                          children: upcoming
                              .take(3)
                              .map(
                                (post) => ListTile(
                                  leading: const CircleAvatar(
                                    child: Icon(
                                      Icons.calendar_today_outlined,
                                      size: 18,
                                    ),
                                  ),
                                  title: Text(
                                    post['caption'].toString(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    (post['platforms'] as List).join(' + '),
                                  ),
                                  trailing: const Chip(
                                    label: Text('Scheduled'),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _heading(String eyebrow, String title) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        eyebrow.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w800,
          color: Color(0xFF6D4AFF),
        ),
      ),
      Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      ),
    ],
  );

  Widget _error(Object? error) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off, size: 52),
          const SizedBox(height: 12),
          const Text(
            'We could not open your workspace.',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            error is ApiException ? error.message : error.toString(),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          FilledButton(onPressed: refresh, child: const Text('Try again')),
        ],
      ),
    ),
  );
}

class _WorkspaceDrawer extends StatelessWidget {
  const _WorkspaceDrawer({required this.onOpen, required this.onLogout});

  final Future<void> Function(Widget) onOpen;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final entries = <(String, IconData, Widget)>[
      ('Agency workspace', Icons.groups_outlined, const AgencyScreen()),
      ('Brand context', Icons.business_outlined, const BrandProfileScreen()),
      ('Accounts', Icons.link, const SettingsScreen()),
      ('Create post', Icons.add_box_outlined, const CreatePostScreen()),
      (
        'Templates',
        Icons.auto_awesome_mosaic_outlined,
        const TemplatesScreen(),
      ),
      ('Content library', Icons.article_outlined, const PostsScreen()),
      ('Calendar', Icons.calendar_month_outlined, const CalendarScreen()),
      ('Action center', Icons.bolt_outlined, const ActionCenterScreen()),
      ('Analytics', Icons.analytics_outlined, const AnalyticsScreen()),
      (
        'Plans & billing',
        Icons.credit_card_outlined,
        const SubscriptionScreen(),
      ),
      ('Profile', Icons.person_outline, const ProfileScreen()),
    ];

    return NavigationDrawer(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 18),
          child: Row(
            children: [
              Image.asset(
                'assets/images/social9-web-mark.png',
                width: 40,
                height: 40,
              ),
              const SizedBox(width: 10),
              const Text(
                'Social9',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, 10),
          child: Text(
            'YOUR WORKSPACE',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w700,
              color: Colors.black45,
            ),
          ),
        ),
        for (final entry in entries)
          ListTile(
            leading: Icon(entry.$2),
            title: Text(entry.$1),
            onTap: () => onOpen(entry.$3),
          ),
        const Divider(height: 30),
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('Sign out'),
          onTap: onLogout,
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.width,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

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
        padding: const EdgeInsets.all(17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 13),
            Text(
              '$value',
              style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
            ),
            Text(label, style: const TextStyle(color: Colors.black54)),
          ],
        ),
      ),
    ),
  );
}

class _FocusCard extends StatelessWidget {
  const _FocusCard({
    required this.consistency,
    required this.overview,
    required this.onOpen,
  });

  final Map<String, dynamic> consistency;
  final Map<String, dynamic> overview;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final score =
        (((overview['connected_accounts'] as num?) ?? 0) * 15 +
                ((overview['published'] as num?) ?? 0) * 6 +
                ((overview['scheduled'] as num?) ?? 0) * 5)
            .round()
            .clamp(0, 100);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 76,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: score / 100,
                    strokeWidth: 8,
                    backgroundColor: const Color(0xFFEAE7F2),
                  ),
                  Text(
                    '$score',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'WORKSPACE MOMENTUM',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF6D4AFF),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    consistency['message']?.toString() ??
                        'Your next publishing streak starts here.',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextButton(
                    onPressed: onOpen,
                    child: const Text('Open calendar →'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.onOpen});

  final Future<void> Function(Widget) onOpen;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          _action(
            'Write a post',
            Icons.edit_outlined,
            () => onOpen(const CreatePostScreen()),
          ),
          _action(
            'Open calendar',
            Icons.calendar_month_outlined,
            () => onOpen(const CalendarScreen()),
          ),
          _action(
            'Find an idea',
            Icons.auto_awesome_outlined,
            () => onOpen(const TemplatesScreen()),
          ),
        ],
      ),
    ),
  );

  Widget _action(String label, IconData icon, VoidCallback action) => ListTile(
    leading: Icon(icon),
    title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
    trailing: const Icon(Icons.arrow_forward, size: 18),
    onTap: action,
  );
}