import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:note_secret_search/app/di/bootstrap_provider.dart';
import 'package:note_secret_search/features/notes/application/note_providers.dart';

class NoteListPage extends ConsumerWidget {
  const NoteListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final noteListAsync = ref.watch(noteListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('私密笔记')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _NoteListSection(
            noteListAsync: noteListAsync,
            cryptoService: ref.read(cryptoServiceProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/notes/item/new'),
        icon: const Icon(Icons.note_add_outlined),
        label: const Text('新增笔记'),
      ),
    );
  }
}

class _NoteListSection extends StatelessWidget {
  const _NoteListSection({
    required this.noteListAsync,
    required this.cryptoService,
  });

  final AsyncValue<List> noteListAsync;
  final dynamic cryptoService;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: noteListAsync.when(
        data: (items) {
          if (items.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('私密笔记'),
                  SizedBox(height: 8),
                  Text('还没有保存的笔记，点击右下角开始新增。'),
                ],
              ),
            );
          }

          return Column(
            children: [
              for (final item in items.cast<dynamic>())
                ListTile(
                  title: Text(item.title as String),
                  subtitle: Text(
                    cryptoService.decryptNullable(item.summaryCacheCiphertext as List<int>?) as String,
                  ),
                  leading: Icon(
                    (item.favorite as bool) ? Icons.star_rounded : Icons.note_outlined,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/notes/item/${item.id}'),
                ),
            ],
          );
        },
        loading: () => const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (error, stackTrace) => Padding(
          padding: const EdgeInsets.all(16),
          child: Text(error.toString()),
        ),
      ),
    );
  }
}
