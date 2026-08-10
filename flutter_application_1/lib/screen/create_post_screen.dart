import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'post_service.dart';

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final captionController = TextEditingController();
  final platforms = <String>{'linkedin'};
  final selectedMedia = <PlatformFile>[];
  DateTime? scheduledFor;
  bool isLoading = false;

  Future<void> pasteCaption() async {
    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    final text = clipboard?.text;
    if (text == null || text.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('The clipboard does not contain text')),
        );
      }
      return;
    }
    final selection = captionController.selection;
    final start = selection.isValid
        ? selection.start
        : captionController.text.length;
    final end = selection.isValid
        ? selection.end
        : captionController.text.length;
    final updated = captionController.text.replaceRange(start, end, text);
    captionController.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: start + text.length),
    );
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
    final available = result.files.where((file) => file.bytes != null).toList();
    setState(() {
      selectedMedia
        ..clear()
        ..addAll(available.take(10));
    });
    if (available.length > 10 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only the first 10 files were selected')),
      );
    }
  }

  Future<void> pickSchedule() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      initialDate: now,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (time == null) return;
    setState(
      () => scheduledFor = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ),
    );
  }

  Future<void> save({required bool schedule, bool publishNow = false}) async {
    if (captionController.text.trim().isEmpty || platforms.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a caption and select a platform')),
      );
      return;
    }
    if (schedule && scheduledFor == null) {
      await pickSchedule();
      if (scheduledFor == null) return;
    }
    setState(() => isLoading = true);
    try {
      final response = await PostService.create(
        caption: captionController.text.trim(),
        platforms: platforms.toList(),
        media: selectedMedia
            .map(
              (file) => {'name': file.name, 'data': base64Encode(file.bytes!)},
            )
            .toList(),
        scheduledFor: schedule ? scheduledFor : null,
        publishNow: publishNow,
      );
      if (!mounted) return;
      if (response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              publishNow
                  ? 'Published on LinkedIn'
                  : schedule
                  ? 'Post scheduled'
                  : 'Draft saved',
            ),
          ),
        );
        Navigator.pop(context, true);
      } else {
        final body = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(body['detail']?.toString() ?? 'Could not save post'),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Connection error: $error')));
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  void dispose() {
    captionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Post')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: captionController,
              maxLines: 6,
              maxLength: 3000,
              keyboardType: TextInputType.multiline,
              decoration: const InputDecoration(
                labelText: 'Caption',
                hintText: 'Write here or paste content from WhatsApp...',
                border: OutlineInputBorder(),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: pasteCaption,
                icon: const Icon(Icons.content_paste),
                label: const Text('Paste from clipboard'),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: isLoading ? null : pickMedia,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(
                selectedMedia.isEmpty
                    ? 'Upload photos or videos'
                    : 'Change selected media',
              ),
            ),
            if (selectedMedia.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: selectedMedia
                    .map(
                      (file) => Chip(
                        avatar: Icon(
                          file.extension == 'mp4' || file.extension == 'mov'
                              ? Icons.videocam
                              : Icons.image,
                          size: 18,
                        ),
                        label: Text(file.name),
                        onDeleted: () =>
                            setState(() => selectedMedia.remove(file)),
                      ),
                    )
                    .toList(),
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              'Platforms',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            CheckboxListTile(
              title: const Text('Instagram'),
              value: platforms.contains('instagram'),
              onChanged: (value) => setState(
                () => value == true
                    ? platforms.add('instagram')
                    : platforms.remove('instagram'),
              ),
            ),
            CheckboxListTile(
              title: const Text('LinkedIn'),
              value: platforms.contains('linkedin'),
              onChanged: (value) => setState(
                () => value == true
                    ? platforms.add('linkedin')
                    : platforms.remove('linkedin'),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule),
              title: Text(
                scheduledFor == null
                    ? 'Choose schedule'
                    : scheduledFor.toString(),
              ),
              trailing: const Icon(Icons.edit_calendar),
              onTap: pickSchedule,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: isLoading ? null : () => save(schedule: false),
                    child: const Text('Save Draft'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isLoading ? null : () => save(schedule: true),
                    icon: const Icon(Icons.schedule_send),
                    label: const Text('Schedule'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isLoading
                    ? null
                    : () => save(schedule: false, publishNow: true),
                icon: const Icon(Icons.send),
                label: Text(isLoading ? 'Publishing...' : 'Publish Now'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

