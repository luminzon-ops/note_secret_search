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
import 'package:note_secret_search/features/search/presentation/detail_search_hit_target.dart';

class NoteDetailPage extends ConsumerWidget {
  const NoteDetailPage({
    required this.noteId,
    this.searchQuery,
    this.searchSource,
    this.searchContext,
    super.key,
  });

  final String noteId;
  final String? searchQuery;
  final String? searchSource;
  final String? searchContext;

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
            searchQuery: searchQuery,
            searchSource: searchSource,
            searchContext: searchContext,
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

class _NoteDetailBody extends StatefulWidget {
  const _NoteDetailBody({
    required this.note,
    required this.cryptoService,
    this.searchQuery,
    this.searchSource,
    this.searchContext,
  });

  final NoteItem note;
  final dynamic cryptoService;
  final String? searchQuery;
  final String? searchSource;
  final String? searchContext;

  @override
  State<_NoteDetailBody> createState() => _NoteDetailBodyState();
}

class _NoteDetailBodyState extends State<_NoteDetailBody> {
  bool _didScrollToHit = false;

  @override
  Widget build(BuildContext context) {
    final note = widget.note;
    final cryptoService = widget.cryptoService;
    final searchQuery = widget.searchQuery;
    final searchSource = widget.searchSource;
    final searchContext = widget.searchContext;
    final searchFocusHint = resolveNoteDetailSearchFocusHint(searchContext);
    final searchHitExplanation = resolveNoteDetailHitExplanation(searchContext) ?? searchContext;
    final semanticOnlyHandoffHint = _semanticOnlyHandoffHint(searchSource);
    final hitTarget = resolveNoteDetailSearchHitTarget(searchContext);
    final titleKey = hitTarget == NoteDetailSearchHitTarget.title ? GlobalKey() : null;
    final summaryKey = hitTarget == NoteDetailSearchHitTarget.summary ? GlobalKey() : null;
    final tagsKey = hitTarget == NoteDetailSearchHitTarget.tags ? GlobalKey() : null;
    final contentKey = hitTarget == NoteDetailSearchHitTarget.content ? GlobalKey() : null;

    final scrollTargetKey = switch (hitTarget) {
      NoteDetailSearchHitTarget.title => titleKey,
      NoteDetailSearchHitTarget.summary => summaryKey,
      NoteDetailSearchHitTarget.tags => tagsKey,
      NoteDetailSearchHitTarget.content => contentKey,
      NoteDetailSearchHitTarget.none => null,
    };

    if (!_didScrollToHit && scrollTargetKey?.currentContext != null) {
      _didScrollToHit = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final targetContext = scrollTargetKey?.currentContext;
        if (targetContext != null && mounted) {
          Scrollable.ensureVisible(
            targetContext,
            duration: const Duration(milliseconds: 180),
            alignment: 0.18,
            curve: Curves.easeOut,
          );
        }
      });
    }

    final summary = cryptoService.decryptNullable(note.summaryCacheCiphertext) as String;
    final content = cryptoService.decryptNullable(note.contentCiphertext) as String;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if ((searchSource ?? '').isNotEmpty || (searchQuery ?? '').isNotEmpty || (searchContext ?? '').isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('来自搜索'),
                    if ((searchSource ?? '').isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('命中方式：${_searchSourceLabel(searchSource)}'),
                    ],
                    if ((searchQuery ?? '').isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('查询词：$searchQuery'),
                    ],
                    if ((searchContext ?? '').isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('命中说明：$searchHitExplanation'),
                    ],
                    if (searchFocusHint != null) ...[
                      const SizedBox(height: 8),
                      Text('优先查看：$searchFocusHint'),
                    ],
                    if (semanticOnlyHandoffHint != null) ...[
                      const SizedBox(height: 8),
                      Text('承接说明：$semanticOnlyHandoffHint'),
                    ],
                  ],
                ),
              ),
          ),
        if ((searchSource ?? '').isNotEmpty || (searchQuery ?? '').isNotEmpty || (searchContext ?? '').isNotEmpty)
          const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _wrapHighlightedSection(
                  context,
                  key: titleKey,
                  markerKey: hitTarget == NoteDetailSearchHitTarget.title
                      ? const ValueKey('note-hit-title')
                      : null,
                  child: Text(note.title, style: Theme.of(context).textTheme.headlineSmall),
                ),
                if (summary.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _wrapHighlightedSection(
                    context,
                    key: summaryKey,
                    markerKey: hitTarget == NoteDetailSearchHitTarget.summary
                        ? const ValueKey('note-hit-summary')
                        : null,
                    child: Text(summary, style: Theme.of(context).textTheme.bodyMedium),
                  ),
                ],
                const SizedBox(height: 16),
                _wrapHighlightedSection(
                  context,
                  key: tagsKey,
                  markerKey: hitTarget == NoteDetailSearchHitTarget.tags
                      ? const ValueKey('note-hit-tags')
                      : null,
                  child: Text('标签：${note.tags.join(', ')}'),
                ),
                const SizedBox(height: 16),
                _wrapHighlightedSection(
                  context,
                  key: contentKey,
                  markerKey: hitTarget == NoteDetailSearchHitTarget.content
                      ? const ValueKey('note-hit-content')
                      : null,
                  child: Text(content),
                ),
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

  String _searchSourceLabel(String? source) {
    switch (source) {
      case 'keyword_semantic':
        return '双命中';
      case 'semantic':
        return '语义命中';
      case 'keyword':
      default:
        return '关键词优先';
    }
  }

  String? _semanticOnlyHandoffHint(String? source) {
    if (source != 'semantic') {
      return null;
    }

    return '该结果以语义命中进入详情页，建议结合命中字段与正文继续确认。';
  }

  Widget _wrapHighlightedSection(
    BuildContext context, {
    required Widget child,
    required GlobalKey? key,
    required Key? markerKey,
  }) {
    final highlight = markerKey != null;
    return Container(
      key: key,
      width: double.infinity,
      padding: highlight ? const EdgeInsets.all(8) : EdgeInsets.zero,
      decoration: highlight
          ? BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(12),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (markerKey != null) SizedBox(key: markerKey, width: 0, height: 0),
          child,
        ],
      ),
    );
  }
}
