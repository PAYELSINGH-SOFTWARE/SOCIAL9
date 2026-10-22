import 'package:flutter/material.dart';
import '../core/workspace_session.dart';
import '../screen/brand_service.dart';

class BrandSwitcher extends StatefulWidget {
  const BrandSwitcher({super.key});
  @override
  State<BrandSwitcher> createState() => _BrandSwitcherState();
}

class _BrandSwitcherState extends State<BrandSwitcher> {
  late Future<List<Map<String, dynamic>>> brands;
  @override
  void initState() {
    super.initState();
    brands = BrandService.list();
  }

  Future<void> addBrand() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add a brand'),
        content: TextField(
          controller: controller,
          maxLength: 120,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Brand name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(context, controller.text.trim());
              }
            },
            child: const Text('Create brand'),
          ),
        ],
      ),
    );
    if (name == null) return;
    try {
      await BrandService.create(name);
      if (mounted) {
        setState(() {
          brands = BrandService.list();
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<List<Map<String, dynamic>>>(
        future: brands,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return TextButton.icon(
              onPressed: () => setState(() {
                brands = BrandService.list();
              }),
              icon: const Icon(Icons.business_outlined),
              label: Text(
                snapshot.hasError ? 'Retry workspace' : 'Loading workspace…',
              ),
            );
          }
          final items = snapshot.data!;
          return Row(
            children: [
              const SizedBox(width: 18),
              const Icon(Icons.business_outlined, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: ValueListenableBuilder<int?>(
                  valueListenable: WorkspaceSession.brandId,
                  builder: (context, id, _) => DropdownButton<int>(
                    value: items.any((b) => b['id'] == id) ? id : null,
                    isExpanded: true,
                    underline: const SizedBox(),
                    hint: const Text('Choose a brand'),
                    items: items
                        .map(
                          (b) => DropdownMenuItem<int>(
                            value: b['id'] as int,
                            child: Text(
                              b['name'].toString(),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (id) {
                      if (id != null) WorkspaceSession.selectBrand(id);
                    },
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Add brand',
                onPressed: addBrand,
                icon: const Icon(Icons.add_circle_outline),
              ),
              const SizedBox(width: 8),
            ],
          );
        },
      );
}
