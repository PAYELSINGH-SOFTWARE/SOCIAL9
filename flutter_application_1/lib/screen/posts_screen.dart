import 'dart:convert';

import 'package:flutter/material.dart';

import 'create_post_screen.dart';
import 'post_service.dart';

class PostsScreen extends StatefulWidget {
  const PostsScreen({super.key});

  @override
  State<PostsScreen> createState() => _PostsScreenState();
}

class _PostsScreenState extends State<PostsScreen> {
  late Future<List<dynamic>> posts;
  int? publishingId;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  void refresh() => setState(() {
    posts = PostService.list().then((response) {
      if (response.statusCode != 200) throw Exception('Could not load posts');
      return jsonDecode(response.body) as List<dynamic>;
    });
  });

  Future<void> remove(int id) async {
    final response = await PostService.delete(id);
    if (response.statusCode == 204) refresh();
  }

  Future<void> publish(int id) async {
    setState(() => publishingId = id);
    try {
      final response = await PostService.publish(id);
      if (!mounted) return;
      final body = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Published on LinkedIn')));
        refresh();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(body['detail']?.toString() ?? 'Publishing failed'),
          ),
        );
        refresh();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Connection error: $error')));
      }
    } finally {
      if (mounted) setState(() => publishingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Your Posts')),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CreatePostScreen()),
          );
          refresh();
        },
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<List<dynamic>>(
        future: posts,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text(snapshot.error.toString()));
          }
          final items = snapshot.data ?? [];
          if (items.isEmpty) {
            return const Center(
              child: Text('No posts yet. Create your first post!'),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => refresh(),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final post = items[index] as Map<String, dynamic>;
                final id = post['id'] as int;
                final status = post['status']?.toString() ?? 'draft';
                final error = post['publish_error']?.toString();
                final canPublish = status == 'draft' || status == 'failed';
                return Card(
                  child: ListTile(
                    title: Text(post['caption']?.toString() ?? ''),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${(post['platforms'] as List).join(' + ')} • $status',
                        ),
                        if (error != null && error.isNotEmpty)
                          Text(
                            error,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (canPublish)
                          IconButton(
                            tooltip: 'Publish now',
                            onPressed: publishingId == id
                                ? null
                                : () => publish(id),
                            icon: publishingId == id
                                ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.send),
                          ),
                        IconButton(
                          tooltip: 'Delete',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => remove(id),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
