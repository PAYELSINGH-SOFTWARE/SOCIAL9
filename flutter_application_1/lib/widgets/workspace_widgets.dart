import 'package:flutter/material.dart';

class WorkspaceError extends StatelessWidget {
  const WorkspaceError({super.key, required this.error, required this.retry});
  final Object? error;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 42),
          const SizedBox(height: 12),
          Text(error.toString(), textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: retry, child: const Text('Try again')),
        ],
      ),
    ),
  );
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    ),
  );
}

Future<Map<String, String>?> askFields(
  BuildContext context,
  String title,
  Map<String, String> fields, {
  Map<String, List<String>> choices = const {},
}) async {
  final controllers = {
    for (final field in fields.entries)
      field.key: TextEditingController(text: field.value),
  };
  return showDialog<Map<String, String>>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: fields.keys
                .map(
                  (key) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: choices.containsKey(key)
                        ? DropdownButtonFormField<String>(
                            isExpanded: true,
                            initialValue: controllers[key]!.text.isEmpty
                                ? choices[key]!.first
                                : controllers[key]!.text,
                            decoration: InputDecoration(
                              labelText: fieldLabel(key),
                            ),
                            items: choices[key]!
                                .map(
                                  (value) => DropdownMenuItem(
                                    value: value,
                                    child: Text(value),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) =>
                                controllers[key]!.text = value ?? '',
                          )
                        : TextField(
                            controller: controllers[key],
                            maxLines:
                                key.contains('caption') ||
                                    key.contains('description') ||
                                    key == 'summary' ||
                                    key == 'comment'
                                ? 4
                                : 1,
                            decoration: InputDecoration(
                              labelText: fieldLabel(key),
                            ),
                          ),
                  ),
                )
                .toList(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(context, {
              for (final entry in controllers.entries)
                entry.key: entry.value.text.trim(),
            });
          },
          child: const Text('Continue'),
        ),
      ],
    ),
  );
}

String fieldLabel(String value) => value
    .split('_')
    .map(
      (part) =>
          part.isEmpty ? '' : '${part[0].toUpperCase()}${part.substring(1)}',
    )
    .join(' ');

void showMessage(BuildContext context, Object message) => ScaffoldMessenger.of(
  context,
).showSnackBar(SnackBar(content: Text(message.toString())));
