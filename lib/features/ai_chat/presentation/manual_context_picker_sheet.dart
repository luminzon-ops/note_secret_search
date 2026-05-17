import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/features/ai_chat/application/ai_chat_providers.dart';

class ManualContextPickerSheet extends ConsumerStatefulWidget {
  const ManualContextPickerSheet({required this.initialIds, super.key});

  final Set<String> initialIds;

  @override
  ConsumerState<ManualContextPickerSheet> createState() => _ManualContextPickerSheetState();
}

class _ManualContextPickerSheetState extends ConsumerState<ManualContextPickerSheet> {
  late Set<String> _selectedIds;

  @override
  void initState() {
    super.initState();
    _selectedIds = {...widget.initialIds};
  }

  @override
  Widget build(BuildContext context) {
    final candidatesAsync = ref.watch(manualContextCandidatesProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: candidatesAsync.when(
          data: (items) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('手动选择私密内容', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: items
                      .map(
                        (item) => CheckboxListTile(
                          value: _selectedIds.contains(item.id),
                          title: Text(item.title),
                          subtitle: Text(item.preview),
                          onChanged: (selected) {
                            setState(() {
                              if (selected == true) {
                                _selectedIds.add(item.id);
                              } else {
                                _selectedIds.remove(item.id);
                              }
                            });
                          },
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () {
                    final selectedItems = items
                        .where((item) => _selectedIds.contains(item.id))
                        .toList(growable: false);
                    Navigator.of(context).pop(selectedItems);
                  },
                  child: const Text('完成'),
                ),
              ),
            ],
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => Text(error.toString()),
        ),
      ),
    );
  }
}
