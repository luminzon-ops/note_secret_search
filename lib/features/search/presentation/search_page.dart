import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:note_secret_search/features/search/application/search_providers.dart';
import 'package:note_secret_search/features/search/domain/search_result_item.dart';
import 'package:note_secret_search/features/search/domain/semantic_search_result.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final unifiedResultsAsync = ref.watch(unifiedSearchResultsProvider);
    final semanticResultsAsync = ref.watch(semanticSearchResultsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('搜索'),
        actions: [
          IconButton(
            tooltip: '搜索设置与索引',
            onPressed: () => context.push('/search/settings'),
            icon: const Icon(Icons.tune_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SearchBar(
            controller: _controller,
            hintText: '搜索密码、标签、笔记或语义描述',
            leading: const Icon(Icons.search),
            onChanged: (value) => ref.read(searchQueryProvider.notifier).state = value,
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: const Icon(Icons.tune_outlined),
              title: const Text('搜索设置与索引'),
              subtitle: const Text('调整检索范围、语义索引策略与隐私控制'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/search/settings'),
            ),
          ),
          const SizedBox(height: 16),
          unifiedResultsAsync.when(
            data: (results) => _SearchResultSection(results: results),
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, stackTrace) => Text(error.toString()),
          ),
          const SizedBox(height: 16),
          semanticResultsAsync.when(
            data: (results) => _SemanticSearchSection(results: results),
            loading: () => const SizedBox.shrink(),
            error: (error, stackTrace) => Text(error.toString()),
          ),
        ],
      ),
    );
  }
}

class _SemanticSearchSection extends StatelessWidget {
  const _SemanticSearchSection({required this.results});

  final List<SemanticSearchResult> results;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('占位语义匹配', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '当前基于占位 embedding 引擎和已构建 chunks 返回近似结果，仅用于打通流程，不代表真实语义质量。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            for (final result in results)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  result.item.type == SearchResultType.secret
                      ? Icons.psychology_alt_outlined
                      : Icons.auto_awesome_outlined,
                ),
                title: Text(result.item.title),
                subtitle: Text(
                  '${result.item.preview.isEmpty ? '无预览内容' : result.item.preview}\n相似度 ${(result.score * 100).toStringAsFixed(1)}%',
                ),
                isThreeLine: true,
              ),
          ],
        ),
      ),
    );
  }
}

class _SearchResultSection extends StatelessWidget {
  const _SearchResultSection({required this.results});

  final List<SearchResultItem> results;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('暂无搜索结果。'),
        ),
      );
    }

    return Card(
      child: Column(
        children: [
          for (final item in results)
            ListTile(
              leading: Icon(
                item.type == SearchResultType.secret ? Icons.lock_outline : Icons.note_outlined,
              ),
              title: Text(item.title),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final source in item.matchSources)
                        Chip(
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          label: Text(_matchSourceLabel(source)),
                        ),
                      if (item.semanticScore != null)
                        Chip(
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          label: Text('语义 ${(item.semanticScore! * 100).toStringAsFixed(0)}%'),
                        ),
                      if (item.semanticHitField != null)
                        Chip(
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          label: Text(_semanticFieldLabel(item.semanticHitField!)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(item.preview.isEmpty ? '无预览内容' : item.preview),
                  if (_rankingReasonLines(item).isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '排序依据',
                            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          for (final line in _rankingReasonLines(item))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Text(
                                '• $line',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  if (item.semanticHitSummary != null && item.semanticHitSummary!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '语义命中',
                            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          for (final line in _semanticExplanationLines(item.semanticHitSummary!))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Text(
                                '• $line',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  if (item.tags.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: item.tags
                          .map(
                            (tag) => Chip(
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                              label: Text(tag),
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ],
                ],
              ),
              trailing: const Icon(Icons.chevron_right),
              isThreeLine: true,
              onTap: () {
                if (item.type == SearchResultType.secret) {
                  context.push('/vault/secret/${item.id}');
                } else {
                  context.push('/notes/item/${item.id}');
                }
              },
            ),
        ],
      ),
    );
  }

  String _matchSourceLabel(SearchMatchSource source) {
    switch (source) {
      case SearchMatchSource.keyword:
        return '关键词';
      case SearchMatchSource.semantic:
        return '语义';
    }
  }

  String _semanticFieldLabel(SemanticHitField field) {
    switch (field) {
      case SemanticHitField.title:
        return '标题命中';
      case SemanticHitField.username:
        return '账号命中';
      case SemanticHitField.url:
        return '网址命中';
      case SemanticHitField.secretNote:
        return '附注命中';
      case SemanticHitField.summary:
        return '摘要命中';
      case SemanticHitField.noteBody:
        return '正文命中';
      case SemanticHitField.tags:
        return '标签命中';
    }
  }

  List<String> _semanticExplanationLines(String summary) {
    return summary
        .split('；')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
  }

  List<String> _rankingReasonLines(SearchResultItem item) {
    final lines = <String>[];

    final hasKeyword = item.matchSources.contains(SearchMatchSource.keyword);
    final hasSemantic = item.matchSources.contains(SearchMatchSource.semantic);
    if (hasKeyword && hasSemantic) {
      lines.add('强信号：同时命中关键词与语义检索');
    } else if (hasSemantic) {
      lines.add('中信号：命中语义检索');
    } else if (hasKeyword) {
      lines.add('中信号：命中关键词检索');
    }

    final semanticFieldReason = _semanticFieldPriorityReason(item.semanticHitField);
    if (semanticFieldReason != null) {
      lines.add(semanticFieldReason);
    }

    return lines;
  }

  String? _semanticFieldPriorityReason(SemanticHitField? field) {
    switch (field) {
      case SemanticHitField.title:
        return '强信号：标题属于高优先级语义命中';
      case SemanticHitField.username:
        return '强信号：账号属于高优先级语义命中';
      case SemanticHitField.summary:
        return '强信号：摘要属于高优先级语义命中';
      case SemanticHitField.url:
        return '中信号：网址提供中优先级语义命中';
      case SemanticHitField.secretNote:
        return '中信号：附注提供中优先级语义命中';
      case SemanticHitField.tags:
        return '辅助信号：标签提供辅助语义命中';
      case SemanticHitField.noteBody:
        return '辅助信号：正文提供辅助语义命中';
      case null:
        return null;
    }
  }
}
