import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../core/media_images.dart';
import '../widgets/workspace_widgets.dart';

class PhotoEditorScreen extends StatefulWidget {
  const PhotoEditorScreen({super.key, required this.bytes});
  final Uint8List bytes;
  @override
  State<PhotoEditorScreen> createState() => _PhotoEditorScreenState();
}

class _PhotoEditorScreenState extends State<PhotoEditorScreen> {
  double? ratio;
  int turns = 0;
  bool saving = false;
  Future<void> save() async {
    setState(() => saving = true);
    try {
      final bytes = await prepareImage(
        widget.bytes,
        aspectRatio: ratio,
        turns: turns,
      );
      if (mounted) Navigator.pop(context, bytes);
    } catch (error) {
      if (mounted) showMessage(context, error);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Edit photo')),
    body: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: ratio ?? 1,
                child: ClipRect(
                  child: RotatedBox(
                    quarterTurns: turns,
                    child: Image.memory(widget.bytes, fit: BoxFit.cover),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            children: [
              for (final entry in {
                'Original': null,
                'Square': 1.0,
                'Portrait': 0.8,
                'Landscape': 1.91,
              }.entries)
                ChoiceChip(
                  label: Text(entry.key),
                  selected: ratio == entry.value,
                  onSelected: (_) => setState(() => ratio = entry.value),
                ),
              IconButton(
                tooltip: 'Rotate photo',
                onPressed: () => setState(() => turns = (turns + 1) % 4),
                icon: const Icon(Icons.rotate_right),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: saving ? null : save,
            child: Text(saving ? 'Preparing image…' : 'Apply changes'),
          ),
        ],
      ),
    ),
  );
}
