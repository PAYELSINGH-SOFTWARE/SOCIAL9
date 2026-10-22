import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/api_client.dart';
import 'create_post_screen.dart';
import 'post_service.dart';

class PostsScreen extends StatefulWidget {
  const PostsScreen({super.key});

  @override
  State<PostsScreen> createState() => _PostsScreenState();
}

class _PostsScreenState extends State<PostsScreen> {
  final searchController = TextEditingController();
  late Future<List<Map<String, dynamic>>> posts;
  String status = 'all';
  String platform = 'all';
  int? workingId;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  void refresh() => setState(() {
    posts = PostService.list(
      status: status,
      platform: platform,
      search: searchController.text,
    );
  });

  Future<void> perform(
    int id,
    Future<void> Function() action,
    String success,
  ) async {
    setState(() => workingId = id);
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(success)));
      }
      refresh();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => workingId = null);
    }
  }

  Future<void> remove(Map<String, dynamic> post) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this post?'),
        content: const Text(
          'The Social9 record will be removed. Posts already live on a social network remain there.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await perform(
        post['id'] as int,
        () => PostService.delete(post['id'] as int),
        'Post deleted.',
      );
    }
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Content library'),
        actions: [
          IconButton(onPressed: refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CreatePostScreen()),
          );
          refresh();
        },
        icon: const Icon(Icons.add),
        label: const Text('Create post'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Everything you have created, scheduled, and published.',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: searchController,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => refresh(),
                      decoration: InputDecoration(
                        hintText: 'Search captions',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: IconButton(
                          onPressed: refresh,
                          icon: const Icon(Icons.arrow_forward),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final item in const [
                            'all',
                            'draft',
                            'scheduled',
                            'published',
                            'failed',
                          ])
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(
                                  item == 'all' ? 'All statuses' : _title(item),
                                ),
                                selected: status == item,
                                onSelected: (_) {
                                  status = item;
                                  refresh();
                                },
                              ),
                            ),
                          const SizedBox(width: 8),
                          for (final item in const [
                            'all',
                            'instagram',
                            'linkedin',
                            'facebook',
                          ])
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: FilterChip(
                                label: Text(
                                  item == 'all' ? 'All channels' : _title(item),
                                ),
                                selected: platform == item,
                                onSelected: (_) {
                                  platform = item;
                                  refresh();
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: posts,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return _EmptyState(
                        icon: Icons.cloud_off,
                        title: 'Could not load your content',
                        action: refresh,
                      );
                    }
                    final items = snapshot.data ?? [];
                    if (items.isEmpty) {
                      return _EmptyState(
                        icon: Icons.article_outlined,
                        title: 'No matching posts',
                        action: () {
                          searchController.clear();
                          status = 'all';
                          platform = 'all';
                          refresh();
                        },
                      );
                    }
                    return RefreshIndicator(
                      onRefresh: () async => refresh(),
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 110),
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) =>
                            _postCard(items[index]),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _postCard(Map<String, dynamic> post) {
    final id = post['id'] as int;
    final state = post['status']?.toString() ?? 'draft';
    final channels = (post['platforms'] as List? ?? []).join(' + ');
    final scheduled = DateTime.tryParse(
      post['scheduled_for']?.toString() ?? '',
    )?.toLocal();
    final busy = workingId == id;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 10, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    post['caption']?.toString() ?? '',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _StatusChip(state: state),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '$channels${scheduled == null ? '' : ' • ${DateFormat('d MMM, h:mm a').format(scheduled)}'}',
              style: const TextStyle(color: Colors.black54),
            ),
            if ((post['publish_error']?.toString() ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                post['publish_error'].toString(),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                if (busy)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else ...[
                  if (state == 'draft' ||
                      state == 'failed' ||
                      state == 'scheduled')
                    IconButton(
                      tooltip: 'Edit post',
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CreatePostScreen(editingPost: post),
                          ),
                        );
                        if (mounted) refresh();
                      },
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  if (state == 'draft' || state == 'failed')
                    IconButton(
                      tooltip: 'Publish now',
                      onPressed: () => perform(id, () async {
                        final result = await PostService.publish(id);
                        if (result['status'] != 'published') {
                          throw ApiException(
                            result['publish_error']?.toString() ??
                                'Publishing is ${result['status']}.',
                          );
                        }
                      }, 'Post published.'),
                      icon: const Icon(Icons.send_outlined),
                    ),
                  IconButton(
                    tooltip: 'Duplicate',
                    onPressed: () => perform(id, () async {
                      await PostService.duplicate(id);
                    }, 'Draft duplicated.'),
                    icon: const Icon(Icons.copy_outlined),
                  ),
                  if (state == 'scheduled')
                    IconButton(
                      tooltip: 'Move to drafts',
                      onPressed: () => perform(id, () async {
                        await PostService.moveToDraft(id);
                      }, 'Moved to drafts.'),
                      icon: const Icon(Icons.undo),
                    ),
                  IconButton(
                    tooltip: 'Delete',
                    onPressed: () => remove(post),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _title(String value) =>
      '${value[0].toUpperCase()}${value.substring(1)}';
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.state});
  final String state;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      'published' => const Color(0xFF16855A),
      'scheduled' => const Color(0xFF5B49D6),
      'failed' => const Color(0xFFC33E43),
      _ => const Color(0xFF596170),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        state.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.action,
  });
  final IconData icon;
  final String title;
  final VoidCallback action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 52, color: Colors.black38),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: action,
            child: const Text('Reset and retry'),
          ),
        ],
      ),
    ),
  );
}
