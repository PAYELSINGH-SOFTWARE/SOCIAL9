import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/api_client.dart';
import '../core/export_file.dart';
import '../core/workspace_session.dart';
import '../widgets/workspace_widgets.dart';
import 'posts_screen.dart';

class AgencyScreen extends StatefulWidget {
  const AgencyScreen({super.key});
  @override
  State<AgencyScreen> createState() => _AgencyScreenState();
}

class _AgencyScreenState extends State<AgencyScreen> {
  late Future<List<dynamic>> data;
  int? workspace;
  bool busy = false;
  String get base => '/agency/$workspace';
  @override
  void initState() {
    super.initState();
    workspace = WorkspaceSession.brandId.value;
    load();
  }

  void load() {
    setState(() {
      data = _load();
    });
  }

  Future<List<dynamic>> _load() async {
    final workspaces = (await ApiClient.get('/agency/workspaces') as List)
        .cast<Map>();
    if (!workspaces.any((w) => w['id'] == workspace && w['accepted'] == true)) {
      workspace =
          workspaces.where((w) => w['accepted'] == true).firstOrNull?['id']
              as int?;
    }
    return [workspaces, workspace == null ? null : await ApiClient.get(base)];
  }

  Future<void> mutate(String path, {Map? body, String method = 'POST'}) async {
    setState(() => busy = true);
    try {
      if (method == 'DELETE') {
        await ApiClient.delete('$base$path');
      } else if (method == 'PATCH') {
        await ApiClient.patch('$base$path', body: body);
      } else {
        await ApiClient.post('$base$path', body: body);
      }
      if (mounted) {
        load();
        showMessage(context, 'Saved successfully.');
      }
    } catch (error) {
      if (mounted) showMessage(context, error);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> form(
    String title,
    String path,
    Map<String, String> fields, {
    Map<String, List<String>> choices = const {},
    Map<String, dynamic> extra = const {},
    String method = 'POST',
  }) async {
    final values = await askFields(context, title, fields, choices: choices);
    if (values != null) {
      await mutate(path, body: {...values, ...extra}, method: method);
    }
  }

  Future<void> confirmDelete(String path, String label) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove $label?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (yes == true) await mutate(path, method: 'DELETE');
  }

  Future<void> benchmark(Map competitor) async {
    final values = await askFields(context, 'Record a public observation', {
      'followers': '',
      'posts': '',
      'views': '',
      'note': '',
    });
    if (values == null) return;
    await mutate(
      '/competitors/${competitor['id']}/benchmark',
      body: {
        'revision': competitor['revision'],
        'observed_at': DateTime.now().toUtc().toIso8601String(),
        'note': values['note'],
        for (final key in ['followers', 'posts', 'views'])
          key: int.tryParse(values[key] ?? ''),
      },
    );
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 4,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Agency workspace'),
        actions: [IconButton(onPressed: load, icon: const Icon(Icons.refresh))],
        bottom: const TabBar(
          isScrollable: true,
          tabs: [
            Tab(text: 'Competitors'),
            Tab(text: 'Approvals'),
            Tab(text: 'Reports'),
            Tab(text: 'Team & roles'),
          ],
        ),
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
          final workspaces = (snapshot.data![0] as List).cast<Map>();
          final details = snapshot.data![1] as Map?;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Column(
                  children: [
                    DropdownButton<int>(
                      isExpanded: true,
                      value: workspace,
                      hint: const Text('Choose a workspace'),
                      items: workspaces
                          .where((w) => w['accepted'] == true)
                          .map(
                            (w) => DropdownMenuItem(
                              value: w['id'] as int,
                              child: Text('${w['name']} • ${w['role']}'),
                            ),
                          )
                          .toList(),
                      onChanged: busy
                          ? null
                          : (id) {
                              workspace = id;
                              load();
                            },
                    ),
                    for (final invite in workspaces.where(
                      (w) => w['accepted'] != true,
                    ))
                      TextButton(
                        onPressed: busy
                            ? null
                            : () async {
                                workspace = invite['id'] as int;
                                await mutate('/accept');
                              },
                        child: Text('Accept invitation to ${invite['name']}'),
                      ),
                  ],
                ),
              ),
              if (busy) const LinearProgressIndicator(),
              if (details == null)
                const Expanded(
                  child: Center(
                    child: Text('Choose a brand or accept a team invitation.'),
                  ),
                )
              else
                Expanded(
                  child: AbsorbPointer(
                    absorbing: busy,
                    child: TabBarView(
                      children: [
                        _competitors(details),
                        _approvals(details),
                        _reports(details),
                        _team(details),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
  Widget _competitors(Map details) {
    final items = (details['competitors'] as List? ?? []).cast<Map>();
    final owner = details['role'] == 'owner';
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        SectionCard(
          title: 'Compare public profiles',
          children: [
            Text(
              '${items.length} / ${(details['features'] as Map?)?['competitor_limit'] ?? 0} tracked profiles',
            ),
            const SizedBox(height: 10),
            if (owner)
              FilledButton.icon(
                onPressed: () => form(
                  'Track a competitor',
                  '/competitors',
                  {'name': '', 'provider': 'instagram', 'handle': ''},
                  choices: {
                    'provider': [
                      'instagram',
                      'facebook',
                      'linkedin',
                      'threads',
                      'youtube',
                      'twitter',
                      'pinterest',
                    ],
                  },
                ),
                icon: const Icon(Icons.add),
                label: const Text('Add profile'),
              ),
          ],
        ),
        for (final item in items)
          SectionCard(
            title: item['name'].toString(),
            children: [
              Text('${item['provider']} • ${item['handle']}'),
              const SizedBox(height: 10),
              if ((item['snapshots'] as List? ?? []).isEmpty)
                const Text('No observations yet.'),
              for (final snapshot
                  in (item['snapshots'] as List? ?? [])
                      .cast<Map>()
                      .reversed
                      .take(3))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Followers: ${snapshot['followers'] ?? 'Unavailable'} • Posts: ${snapshot['posts'] ?? 'Unavailable'} • Views: ${snapshot['views'] ?? 'Unavailable'}',
                      ),
                      Text(
                        '${snapshot['source']} • ${snapshot['observed_at']}',
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 12,
                        ),
                      ),
                      if (snapshot['note'] != null)
                        Text(snapshot['note'].toString()),
                    ],
                  ),
                ),
              if (owner)
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: () => benchmark(item),
                      child: const Text('Record benchmark'),
                    ),
                    TextButton(
                      onPressed: () =>
                          mutate('/competitors/${item['id']}/refresh'),
                      child: const Text('Refresh API data'),
                    ),
                    IconButton(
                      tooltip: 'Remove competitor',
                      onPressed: () => confirmDelete(
                        '/competitors/${item['id']}',
                        item['name'].toString(),
                      ),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
            ],
          ),
      ],
    );
  }

  Widget _approvals(Map details) {
    final role = details['role'];
    final canWrite = role == 'owner' || role == 'editor';
    final enabled = (details['features'] as Map?)?['teams'] == true;
    final drafts = (details['drafts'] as List? ?? []).cast<Map>();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (!enabled)
          const SectionCard(
            title: 'Content approvals',
            children: [
              Text('Agency unlocks team drafts and review workflows.'),
            ],
          ),
        if (enabled && canWrite)
          FilledButton.icon(
            onPressed: () => form(
              'Create a team draft',
              '/drafts',
              {'caption': '', 'platform': 'linkedin'},
              choices: {
                'platform': ['linkedin', 'facebook', 'threads', 'twitter'],
              },
            ),
            icon: const Icon(Icons.add),
            label: const Text('New team draft'),
          ),
        const SizedBox(height: 14),
        if (drafts.isEmpty) const Text('The review queue is empty.'),
        for (final draft in drafts)
          SectionCard(
            title: '${draft['platform']} • ${draft['state']}',
            children: [
              Text(draft['caption'].toString()),
              const SizedBox(height: 8),
              Text(
                'Version ${draft['revision']}',
                style: const TextStyle(color: Colors.black54),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (canWrite && draft['state'] != 'transferred')
                    TextButton(
                      onPressed: () => form(
                        'Edit draft',
                        '/drafts/${draft['id']}',
                        {
                          'caption': draft['caption'].toString(),
                          'platform': draft['platform'].toString(),
                        },
                        choices: {
                          'platform': [
                            'linkedin',
                            'facebook',
                            'threads',
                            'twitter',
                          ],
                        },
                        extra: {'revision': draft['revision']},
                        method: 'PATCH',
                      ),
                      child: const Text('Edit'),
                    ),
                  if (canWrite &&
                      ['draft', 'changes_requested'].contains(draft['state']))
                    _reviewButton(draft, 'submit', 'Submit for review'),
                  if ((role == 'owner' || role == 'reviewer') &&
                      draft['state'] == 'pending') ...[
                    _reviewButton(draft, 'approve', 'Approve'),
                    _reviewButton(draft, 'reject', 'Request changes'),
                  ],
                  if (role == 'owner' && draft['state'] == 'approved')
                    _reviewButton(draft, 'transfer', 'Move to library'),
                  if (role != 'viewer' && draft['state'] != 'transferred')
                    _reviewButton(draft, 'comment', 'Comment'),
                  if (draft['post_id'] != null)
                    TextButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const PostsScreen()),
                      ),
                      child: const Text('Open content library'),
                    ),
                ],
              ),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Review history'),
                children: (draft['history'] as List? ?? [])
                    .cast<Map>()
                    .map(
                      (h) => ListTile(
                        title: Text('${h['actor']} • ${h['action']}'),
                        subtitle: Text('${h['comment']}\n${h['at']}'),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
      ],
    );
  }

  Widget _reviewButton(Map draft, String action, String label) => TextButton(
    onPressed: () async {
      var comment = '';
      if (action == 'comment' || action == 'reject') {
        final values = await askFields(context, label, {'comment': ''});
        if (values == null) return;
        comment = values['comment']!;
      }
      await mutate(
        '/drafts/${draft['id']}/review',
        body: {
          'revision': draft['revision'],
          'action': action,
          'comment': comment,
        },
      );
    },
    child: Text(label),
  );
  Widget _reports(Map details) {
    final reports = (details['reports'] as List? ?? []).cast<Map>();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if ((details['features'] as Map?)?['reports'] == true &&
            details['role'] == 'owner')
          FilledButton.icon(
            onPressed: () => form('Create a publishing report', '/reports', {
              'title': '',
              'start': DateFormat(
                'yyyy-MM-dd',
              ).format(DateTime.now().subtract(const Duration(days: 30))),
              'end': DateFormat('yyyy-MM-dd').format(DateTime.now()),
              'summary': '',
            }),
            icon: const Icon(Icons.summarize_outlined),
            label: const Text('Create report'),
          )
        else
          const Text(
            'Your plan or workspace role does not include report creation.',
          ),
        const SizedBox(height: 14),
        for (final report in reports)
          SectionCard(
            title: report['title'].toString(),
            children: [
              Text(
                '${report['brand']} • ${report['start']} – ${report['end']}',
              ),
              const SizedBox(height: 8),
              Text('${report['published_posts']} published posts'),
              Text(report['summary']?.toString() ?? ''),
              if (report['note'] != null) Text(report['note'].toString()),
              TextButton.icon(
                onPressed: () => exportCsv(
                  'social9-report-${report['id']}.csv',
                  [
                    ['Caption', 'Platforms', 'Published at'],
                    ...(report['posts'] as List? ?? []).cast<Map>().map(
                      (p) => [p['caption'], p['platforms'], p['published_at']],
                    ),
                  ],
                ),
                icon: const Icon(Icons.download_outlined),
                label: const Text('Export CSV'),
              ),
            ],
          ),
        if (reports.isEmpty) const Text('No reports yet.'),
      ],
    );
  }

  Widget _team(Map details) {
    final enabled = (details['features'] as Map?)?['teams'] == true;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (!enabled)
          const Text('Team collaboration requires the Agency plan.'),
        if (enabled && details['role'] == 'owner')
          FilledButton.icon(
            onPressed: () => form(
              'Invite a team member',
              '/members',
              {'email': '', 'role': 'editor'},
              choices: {
                'role': ['editor', 'reviewer', 'viewer'],
              },
            ),
            icon: const Icon(Icons.person_add_outlined),
            label: const Text('Invite member'),
          ),
        const SizedBox(height: 14),
        for (final member in (details['members'] as List? ?? []).cast<Map>())
          Card(
            child: ListTile(
              title: Text(
                member['name']?.toString() ??
                    member['email']?.toString() ??
                    'Member',
              ),
              subtitle: Text(
                '${member['role']} • ${member['accepted'] == true ? 'Active' : 'Invited'}',
              ),
              trailing: details['role'] == 'owner' && member['role'] != 'owner'
                  ? IconButton(
                      tooltip: 'Remove member',
                      onPressed: () => confirmDelete(
                        '/members/${member['id']}',
                        'this member',
                      ),
                      icon: const Icon(Icons.person_remove_outlined),
                    )
                  : null,
            ),
          ),
      ],
    );
  }
}
