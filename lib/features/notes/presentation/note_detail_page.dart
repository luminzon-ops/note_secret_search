import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:note_secret_search/app/di/bootstrap_provider.dart';
import 'package:note_secret_search/features/ai_models/application/model_selection_providers.dart';
import 'package:note_secret_search/features/notes/application/note_providers.dart';
import 'package:note_secret_search/features/notes/domain/note_item.dart';
import 'package:note_secret_search/features/search/application/search_index_settings_providers.dart';
import 'package:note_secret_search/features/search/application/search_providers.dart';

class NoteDetailPage extends ConsumerWidget {
  const NoteDetailPage({required this.noteId, super.key});

  final String noteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final noteAsync = ref.watch(noteDetailProvider(noteId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('笔记详情'),
        actions: [
          IconButton(
            onPressed: () => context.push('/notes/item/$noteId/edit'),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            onPressed: () => _delete(context, ref),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: noteAsync.when(
        data: (note) {
          if (note == null) {
            return const Center(child: Text('笔记不存在或已删除'));
          }
          return _NoteDetailBody(
            note: note,
            cryptoService: ref.read(cryptoServiceProvider),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text(error.toString())),
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    await ref.read(noteRepositoryProvider).softDelete(noteId);
    ref.invalidate(noteListProvider);
    ref.invalidate(noteDetailProvider(noteId));
    ref.invalidate(searchIndexStatusProvider);
    ref.invalidate(semanticSearchResultsProvider);
    ref.invalidate(unifiedSearchResultsProvider);

    final activeModel = await ref.read(activeEmbeddingModelProvider.future);
    final indexSettings = await ref.read(searchIndexSettingsProvider.future);
    if (activeModel != null && indexSettings.autoIndexEnabled) {
      await ref.read(searchIndexControllerProvider).indexPending();
      ref.invalidate(searchIndexStatusProvider);
      ref.invalidate(semanticSearchResultsProvider);
      ref.invalidate(unifiedSearchResultsProvider);
    }

    if (context.mounted) {
      context.pop();
    }
  }
}

class _NoteDetailBody extends StatelessWidget {
  const _NoteDetailBody({
    required this.note,
    required this.cryptoService,
  });

  final NoteItem note;
  final dynamic cryptoService;

  @override
  Widget build(BuildContext context) {
    final summary = cryptoService.decryptNullable(note.summaryCacheCiphertext) as String;
    final content = cryptoService.decryptNullable(note.contentCiphertext) as String;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(note.title, style: Theme.of(context).textTheme.headlineSmall),
                if (summary.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(summary, style: Theme.of(context).textTheme.bodyMedium),
                ],
                const SizedBox(height: 16),
                Text('标签：${note.tags.join(', ')}'),
                const SizedBox(height: 16),
                Text(content),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: content.isEmpty
                      ? null
                      : () async {
                          final messenger = ScaffoldMessenger.of(context);
                          await Clipboard.setData(ClipboardData(text: content));
                          messenger.showSnackBar(const SnackBar(content: Text('笔记正文已复制')));
                        },
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('复制正文'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
