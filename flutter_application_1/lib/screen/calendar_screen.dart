import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api_client.dart';
import '../core/workspace_session.dart';
import '../widgets/workspace_widgets.dart';
import 'create_post_screen.dart';
import 'post_service.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime selectedDay = DateTime.now();
  late Future<List<dynamic>> data;
  bool generating = false;
  List<Map> generated = [];
  String get planKey => 'social9_ai_plan_${WorkspaceSession.brandId.value}';
  String day(DateTime value) => DateFormat('yyyy-MM-dd').format(value);
  @override
  void initState() {
    super.initState();
    refresh();
    restorePlan();
  }

  Future<void> restorePlan() async {
    final saved = (await SharedPreferences.getInstance()).getString(planKey);
    if (saved != null && mounted) {
      try {
        setState(() => generated = (jsonDecode(saved) as List).cast<Map>());
      } catch (_) {}
    }
  }

  void refresh() => setState(() {
    data = Future.wait([
      PostService.list(from: month, to: DateTime(month.year, month.month + 1)),
      PostService.list(status: 'draft'),
      ApiClient.get(
        '/content-plan?date_from=${day(month)}&date_to=${day(DateTime(month.year, month.month + 1, 0))}',
      ),
    ]);
  });
  void changeMonth(int amount) {
    month = DateTime(month.year, month.month + amount);
    selectedDay = month;
    refresh();
  }

  Future<void> generatePlan() async {
    final fields = await askFields(
      context,
      'Generate a daily content plan',
      {
        'topic': '',
        'platform': 'both',
        'start_date': day(DateTime.now()),
        'description': '',
        'audience': '',
        'goals': '',
        'tone': 'Professional and friendly',
        'posts_per_day': '1',
        'use_current_trends': 'false',
        'trend_country': 'IN',
      },
      choices: {
        'platform': ['both', 'instagram', 'linkedin', 'facebook'],
        'posts_per_day': ['1', '2', '3'],
        'use_current_trends': ['false', 'true'],
        'trend_country': ['IN', 'US', 'GB', 'CA', 'AU'],
      },
    );
    if (fields == null) return;
    setState(() => generating = true);
    try {
      final result =
          await ApiClient.post(
                '/content-plan/ai',
                body: {
                  'topic': fields['topic'],
                  'platform': fields['platform'],
                  'start_date': fields['start_date'],
                  'posts_per_day':
                      int.tryParse(fields['posts_per_day'] ?? '') ?? 1,
                  'use_current_trends': fields['use_current_trends'] == 'true',
                  'trend_country': fields['trend_country'],
                  if ((fields['description'] ?? '').isNotEmpty)
                    'business': {
                      'description': fields['description'],
                      'audience': fields['audience'],
                      'goals': fields['goals'],
                      'tone': fields['tone'],
                    },
                },
              )
              as Map;
      final items = (result['items'] as List? ?? []).cast<Map>();
      await (await SharedPreferences.getInstance()).setString(
        planKey,
        jsonEncode(items),
      );
      if (mounted) {
        setState(() => generated = items);
        showMessage(context, 'Your content plan is ready.');
      }
    } catch (error) {
      if (mounted) showMessage(context, error);
    } finally {
      if (mounted) setState(() => generating = false);
    }
  }

  Future<void> openPost(Map post) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            CreatePostScreen(editingPost: Map<String, dynamic>.from(post)),
      ),
    );
    if (mounted) refresh();
  }

  Future<void> useIdea(Map idea) async {
    final schedule = DateTime.tryParse(
      '${idea['date']}T${idea['suggested_time'] ?? '10:00'}',
    );
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreatePostScreen(
          initialCaption: idea['caption_prompt']?.toString(),
          initialPlatform: (idea['platforms'] as List?)?.firstOrNull
              ?.toString(),
          initialSchedule: schedule != null && schedule.isAfter(DateTime.now())
              ? schedule
              : null,
        ),
      ),
    );
    if (mounted) refresh();
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Calendar'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Calendar'),
            Tab(text: 'Daily plan'),
            Tab(text: 'Drafts'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CreatePostScreen()),
          );
          if (mounted) refresh();
        },
        icon: const Icon(Icons.add),
        label: const Text('Create post'),
      ),
      body: FutureBuilder<List<dynamic>>(
        future: data,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return WorkspaceError(error: snapshot.error, retry: refresh);
          }
          final posts = (snapshot.data![0] as List).cast<Map>();
          final drafts = (snapshot.data![1] as List).cast<Map>();
          final plan = snapshot.data![2] as Map;
          final ideas = [
            ...(plan['items'] as List? ?? []).cast<Map>(),
            ...generated,
          ];
          return TabBarView(
            children: [
              ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => changeMonth(-1),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Expanded(
                        child: Text(
                          DateFormat('MMMM yyyy').format(month),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => changeMonth(1),
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                  _monthGrid(posts),
                  const SizedBox(height: 18),
                  Text(
                    DateFormat('EEEE, d MMMM').format(selectedDay),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (!posts.any(
                    (p) =>
                        p['scheduled_for'] != null &&
                        day(
                              DateTime.parse(
                                p['scheduled_for'].toString(),
                              ).toLocal(),
                            ) ==
                            day(selectedDay),
                  ))
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No posts scheduled for this day.'),
                    ),
                  for (final post in posts.where(
                    (p) =>
                        p['scheduled_for'] != null &&
                        day(
                              DateTime.parse(
                                p['scheduled_for'].toString(),
                              ).toLocal(),
                            ) ==
                            day(selectedDay),
                  ))
                    _post(post),
                  for (final idea
                      in ideas
                          .where((i) => i['date'] == day(selectedDay))
                          .take(3))
                    _idea(idea),
                ],
              ),
              ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                children: [
                  FilledButton.icon(
                    onPressed: generating ? null : generatePlan,
                    icon: const Icon(Icons.auto_awesome),
                    label: Text(
                      generating
                          ? 'Generating your plan…'
                          : 'Generate AI content plan',
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (plan['upgrade_message'] != null)
                    Text(plan['upgrade_message'].toString()),
                  if (ideas.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'No ideas in this date range. Change the month or generate a plan.',
                      ),
                    ),
                  for (final idea in ideas) _idea(idea),
                ],
              ),
              ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                children: [
                  if (drafts.isEmpty) const Text('No drafts waiting.'),
                  for (final post in drafts) _post(post),
                ],
              ),
            ],
          );
        },
      ),
    ),
  );

  Widget _monthGrid(List<Map> posts) {
    final offset = month.weekday - 1;
    final days = DateTime(month.year, month.month + 1, 0).day;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Row(
              children: ['M', 'T', 'W', 'T', 'F', 'S', 'S']
                  .map(
                    (d) => Expanded(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            d,
                            style: const TextStyle(color: Colors.black54),
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
              ),
              itemCount: ((offset + days) / 7).ceil() * 7,
              itemBuilder: (context, index) {
                final number = index - offset + 1;
                if (number < 1 || number > days) return const SizedBox();
                final date = DateTime(month.year, month.month, number);
                final count = posts
                    .where(
                      (p) =>
                          p['scheduled_for'] != null &&
                          day(
                                DateTime.parse(
                                  p['scheduled_for'].toString(),
                                ).toLocal(),
                              ) ==
                              day(date),
                    )
                    .length;
                return InkWell(
                  onTap: () => setState(() => selectedDay = date),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: day(date) == day(selectedDay)
                          ? const Color(0xFF6D4AFF)
                          : null,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$number',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: day(date) == day(selectedDay)
                                ? Colors.white
                                : null,
                          ),
                        ),
                        if (count > 0)
                          Icon(
                            Icons.circle,
                            size: 5,
                            color: day(date) == day(selectedDay)
                                ? Colors.white
                                : const Color(0xFF6D4AFF),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _post(Map post) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Card(
      child: ListTile(
        title: Text(
          post['caption'].toString(),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${(post['platforms'] as List).join(' + ')} • ${post['status']}',
        ),
        trailing: IconButton(
          tooltip: 'Edit or reschedule',
          icon: const Icon(Icons.edit_calendar_outlined),
          onPressed: () => openPost(post),
        ),
      ),
    ),
  );
  Widget _idea(Map idea) => Padding(
    padding: const EdgeInsets.only(bottom: 10, top: 6),
    child: SectionCard(
      title: idea['title']?.toString() ?? 'Content idea',
      children: [
        Text('${idea['date']} • ${idea['suggested_time']} • ${idea['format']}'),
        const SizedBox(height: 8),
        Text(idea['caption_prompt']?.toString() ?? ''),
        if (idea['why_it_works'] != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              idea['why_it_works'].toString(),
              style: const TextStyle(color: Colors.black54),
            ),
          ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: () => useIdea(idea),
          child: const Text('Create this post'),
        ),
      ],
    ),
  );
}
