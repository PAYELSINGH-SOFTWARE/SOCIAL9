import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../core/api_client.dart';
import 'post_service.dart';
import 'account_service.dart';
import 'settings_screen.dart';
import 'photo_editor_screen.dart';
import '../core/media_images.dart';

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({
    super.key,
    this.initialCaption,
    this.initialPlatform,
    this.initialSchedule,
    this.editingPost,
  });

  final String? initialCaption;
  final String? initialPlatform;
  final DateTime? initialSchedule;
  final Map<String, dynamic>? editingPost;

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  late final TextEditingController captionController;
  late final Set<String> platforms;
  final selectedMedia = <PlatformFile>[];
  DateTime? scheduledFor;
  bool saving = false;
  bool assisting = false;
  List<Map<String, dynamic>> accounts = [];
  String postType = 'post';
  int? facebookAccountId;
  Map<String, dynamic>? savedPost;
  String? accountError;

  @override
  void initState() {
    super.initState();
    captionController = TextEditingController(
      text:
          widget.editingPost?['caption']?.toString() ??
          widget.initialCaption ??
          '',
    );
    platforms = widget.editingPost == null
        ? {widget.initialPlatform ?? 'linkedin'}
        : (widget.editingPost!['platforms'] as List).cast<String>().toSet();
    scheduledFor =
        widget.initialSchedule ??
        DateTime.tryParse(
          widget.editingPost?['scheduled_for']?.toString() ?? '',
        )?.toLocal();
    postType = widget.editingPost?['post_type']?.toString() ?? 'post';
    facebookAccountId = widget.editingPost?['facebook_account_id'] as int?;
    loadAccounts();
  }

  Future<void> loadAccounts() async {
    try {
      final result = await AccountService.list();
      if (mounted) {
        setState(() {
          accounts = result.where((a) => a['status'] == 'connected').toList();
          accountError = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => accountError = error.toString());
    }
  }

  Future<void> pasteCaption() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (text == null || text.isEmpty) return;
    captionController.text = text;
    captionController.selection = TextSelection.collapsed(offset: text.length);
  }

  Future<void> pickMedia() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const [
        'jpg',
        'jpeg',
        'png',
        'webp',
        'gif',
        'mp4',
        'mov',
      ],
      allowMultiple: true,
      withData: true,
    );
    if (result == null || !mounted) return;
    final available = result.files
        .where((file) => file.bytes != null && file.size <= 25 * 1024 * 1024)
        .take(10)
        .toList();
    if (available.length < result.files.length) {
      _message('Choose up to 10 files, each no larger than 25 MB.');
    }
    setState(() {
      selectedMedia
        ..clear()
        ..addAll(available);
    });
  }

  Future<void> pickSchedule() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      initialDate:
          scheduledFor != null &&
              scheduledFor!.isAfter(now) &&
              scheduledFor!.isBefore(now.add(const Duration(days: 365)))
          ? scheduledFor!
          : now,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: scheduledFor == null
          ? TimeOfDay.now()
          : TimeOfDay.fromDateTime(scheduledFor!),
    );
    if (time == null) return;
    setState(() {
      scheduledFor = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> editPhoto(PlatformFile file) async {
    final edited = await Navigator.push<Uint8List>(
      context,
      MaterialPageRoute(builder: (_) => PhotoEditorScreen(bytes: file.bytes!)),
    );
    if (edited == null || !mounted) return;
    final index = selectedMedia.indexOf(file);
    if (index >= 0) {
      setState(
        () => selectedMedia[index] = PlatformFile(
          name: '${file.name.split('.').first}-edited.png',
          size: edited.length,
          bytes: edited,
        ),
      );
    }
  }

  Future<void> makeCollage() async {
    final photos = selectedMedia
        .where((f) => !['mp4', 'mov'].contains(f.extension?.toLowerCase()))
        .toList();
    if (photos.length < 2) return;
    try {
      final bytes = await imageCollage(photos.map((f) => f.bytes!).toList());
      if (mounted) {
        setState(() {
          selectedMedia.removeWhere((f) => photos.contains(f));
          selectedMedia.insert(
            0,
            PlatformFile(
              name: 'social9-collage.png',
              size: bytes.length,
              bytes: bytes,
            ),
          );
        });
      }
    } catch (error) {
      if (mounted) _message(error.toString());
    }
  }

  Future<void> runAssistant(String action) async {
    final source = captionController.text.trim();
    if (source.length < 2 && selectedMedia.isEmpty) {
      _message('Add a topic or draft first.');
      return;
    }
    setState(() => assisting = true);
    try {
      final result = await PostService.assist(
        action: action,
        topic: source,
        platform: platforms.length > 1 ? 'both' : platforms.first,
        images: selectedMedia
            .where((f) => !['mp4', 'mov'].contains(f.extension?.toLowerCase()))
            .map(
              (f) =>
                  'data:image/${f.extension == 'jpg' ? 'jpeg' : f.extension};base64,${base64Encode(f.bytes!)}',
            )
            .toList(),
      );
      final content = result['content']?.toString() ?? '';
      if (action == 'hashtags') {
        captionController.text = '$source\n\n$content';
      } else {
        captionController.text = content;
      }
      captionController.selection = TextSelection.collapsed(
        offset: captionController.text.length,
      );
    } on ApiException catch (error) {
      _message(error.message);
    } finally {
      if (mounted) setState(() => assisting = false);
    }
  }

  Future<void> save({required bool schedule, bool publishNow = false}) async {
    if (captionController.text.trim().isEmpty || platforms.isEmpty) {
      _message('Add a caption and select at least one channel.');
      return;
    }
    if (schedule && scheduledFor == null) {
      await pickSchedule();
      if (scheduledFor == null) return;
    }
    if (schedule && !scheduledFor!.isAfter(DateTime.now())) {
      _message('Choose a future date and time.');
      return;
    }
    if ((schedule || publishNow) &&
        platforms.any((p) => !accounts.any((a) => a['provider'] == p))) {
      _message('Connect the selected channels in Accounts first.');
      return;
    }
    if ((schedule || publishNow) &&
        platforms.contains('instagram') &&
        selectedMedia.isEmpty &&
        (widget.editingPost?['media_urls'] as List? ?? []).isEmpty) {
      _message('Instagram requires a photo or video.');
      return;
    }
    setState(() => saving = true);
    try {
      final created = savedPost != null || widget.editingPost != null
          ? await PostService.update(
              (savedPost ?? widget.editingPost!)['id'] as int,
              caption: captionController.text.trim(),
              platforms: platforms.toList(),
              scheduledFor: schedule ? scheduledFor : null,
              facebookAccountId: facebookAccountId,
              networkOptions: Map<String, dynamic>.from(
                (savedPost ?? widget.editingPost)?['network_options'] as Map? ??
                    {},
              ),
            )
          : await PostService.create(
              caption: captionController.text.trim(),
              platforms: platforms.toList(),
              media: selectedMedia
                  .map(
                    (file) => {
                      'name': file.name,
                      'data': base64Encode(file.bytes!),
                    },
                  )
                  .toList(),
              scheduledFor: schedule ? scheduledFor : null,
              postType: postType,
              facebookAccountId: facebookAccountId,
            );
      savedPost = created;
      if (publishNow) {
        final published = await PostService.publish(created['id'] as int);
        if (published['status'] != 'published') {
          throw ApiException(
            published['publish_error']?.toString() ??
                'Publishing is ${published['status']}. Review it in your content library.',
          );
        }
      }
      if (!mounted) return;
      _message(
        publishNow
            ? 'Post published.'
            : schedule
            ? 'Post scheduled.'
            : 'Draft saved.',
      );
      Navigator.pop(context, true);
    } on ApiException catch (error) {
      if (mounted) _message(error.message);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  void _message(String value) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(value)));

  @override
  void dispose() {
    captionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create post')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Create your next post.',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Write once, choose your channels, then publish now or schedule it.',
                ),
                const SizedBox(height: 22),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: captionController,
                          minLines: 7,
                          maxLines: 14,
                          maxLength: 3000,
                          decoration: const InputDecoration(
                            labelText: 'Caption or idea',
                            hintText: 'What do you want your audience to know?',
                            alignLabelWithHint: true,
                          ),
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            TextButton.icon(
                              onPressed: pasteCaption,
                              icon: const Icon(Icons.content_paste, size: 18),
                              label: const Text('Paste'),
                            ),
                            for (final action in const {
                              'caption': 'Generate',
                              'improve': 'Improve',
                              'shorten': 'Shorten',
                              'hashtags': 'Hashtags',
                            }.entries)
                              ActionChip(
                                avatar: action.key == 'caption'
                                    ? const Icon(Icons.auto_awesome, size: 17)
                                    : null,
                                label: Text(action.value),
                                onPressed: assisting
                                    ? null
                                    : () => runAssistant(action.key),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Channels',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          children: [
                            _channelChip(
                              'instagram',
                              'Instagram',
                              Icons.camera_alt_outlined,
                            ),
                            _channelChip(
                              'linkedin',
                              'LinkedIn',
                              Icons.work_outline,
                            ),
                            _channelChip(
                              'facebook',
                              'Facebook',
                              Icons.facebook,
                            ),
                          ],
                        ),
                        if (accountError != null)
                          TextButton(
                            onPressed: loadAccounts,
                            child: const Text('Retry connected accounts'),
                          ),
                        TextButton.icon(
                          onPressed: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const SettingsScreen(),
                              ),
                            );
                            loadAccounts();
                          },
                          icon: const Icon(Icons.link),
                          label: const Text('Manage connected channels'),
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          initialValue: postType,
                          decoration: const InputDecoration(
                            labelText: 'Post format',
                          ),
                          items: ['post', 'reel', 'story', 'video']
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(value.toUpperCase()),
                                ),
                              )
                              .toList(),
                          onChanged: widget.editingPost != null
                              ? null
                              : (value) =>
                                    setState(() => postType = value ?? 'post'),
                        ),
                        if (platforms.contains('facebook') &&
                            accounts
                                .where((a) => a['provider'] == 'facebook')
                                .isNotEmpty) ...[
                          const SizedBox(height: 12),
                          DropdownButtonFormField<int>(
                            initialValue: facebookAccountId,
                            decoration: const InputDecoration(
                              labelText: 'Facebook Page',
                            ),
                            items: accounts
                                .where((a) => a['provider'] == 'facebook')
                                .map(
                                  (a) => DropdownMenuItem(
                                    value: a['id'] as int,
                                    child: Text(a['account_name'].toString()),
                                  ),
                                )
                                .toList(),
                            onChanged: (id) =>
                                setState(() => facebookAccountId = id),
                          ),
                        ],
                        const SizedBox(height: 20),
                        Text(
                          'Media',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed:
                              saving ||
                                  widget.editingPost != null ||
                                  savedPost != null
                              ? null
                              : pickMedia,
                          icon: const Icon(Icons.add_photo_alternate_outlined),
                          label: Text(
                            selectedMedia.isEmpty
                                ? 'Add photos or videos'
                                : 'Change media',
                          ),
                        ),
                        if (selectedMedia.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: selectedMedia
                                .map(
                                  (file) => Chip(
                                    label: Text(
                                      file.name,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    onDeleted: () => setState(
                                      () => selectedMedia.remove(file),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                        const SizedBox(height: 20),
                        if (selectedMedia.any(
                          (f) => ![
                            'mp4',
                            'mov',
                          ].contains(f.extension?.toLowerCase()),
                        )) ...[
                          TextButton.icon(
                            onPressed: makeCollage,
                            icon: const Icon(Icons.grid_view),
                            label: const Text('Make a photo collage'),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 160,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: selectedMedia
                                  .where(
                                    (f) => ![
                                      'mp4',
                                      'mov',
                                    ].contains(f.extension?.toLowerCase()),
                                  )
                                  .map(
                                    (f) => Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: InkWell(
                                        onTap: () => editPhoto(f),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          child: Image.memory(
                                            f.bytes!,
                                            width: 160,
                                            height: 160,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, _, _) =>
                                                const Icon(
                                                  Icons.broken_image_outlined,
                                                ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                        ],
                        Text(
                          'Schedule',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 10),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.calendar_month_outlined),
                          title: Text(
                            scheduledFor == null
                                ? 'Choose date and time'
                                : DateFormat(
                                    'EEE, d MMM • h:mm a',
                                  ).format(scheduledFor!),
                          ),
                          trailing: scheduledFor == null
                              ? const Icon(Icons.chevron_right)
                              : IconButton(
                                  tooltip: 'Clear schedule',
                                  onPressed: () =>
                                      setState(() => scheduledFor = null),
                                  icon: const Icon(Icons.close),
                                ),
                          onTap: pickSchedule,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: saving ? null : () => save(schedule: false),
                      child: const Text('Save draft'),
                    ),
                    OutlinedButton.icon(
                      onPressed: saving ? null : () => save(schedule: true),
                      icon: const Icon(Icons.schedule_send_outlined),
                      label: const Text('Schedule'),
                    ),
                    FilledButton.icon(
                      onPressed: saving
                          ? null
                          : () => save(schedule: false, publishNow: true),
                      icon: saving
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_outlined),
                      label: const Text('Publish now'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _channelChip(String value, String label, IconData icon) {
    final selected = platforms.contains(value);
    return FilterChip(
      selected: selected,
      avatar: Icon(icon, size: 18),
      label: Text(label),
      onSelected: (enabled) => setState(() {
        if (enabled) {
          platforms.add(value);
        } else if (platforms.length > 1) {
          platforms.remove(value);
        }
      }),
    );
  }
}
