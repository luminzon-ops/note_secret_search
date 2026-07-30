part of 'search_page.dart';

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
            Text('语义匹配', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '结果已通过字段级相似度门槛，并按命中字段与排序分综合排列。',
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
                  '${result.item.preview.isEmpty ? '无预览内容' : result.item.preview}\n'
                  '相似度 ${((result.primaryRawSimilarity ?? 0).clamp(0, 1) * 100).toStringAsFixed(1)}%'
                  ' · 排序分 ${result.score.toStringAsFixed(3)}',
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
        child: Padding(padding: EdgeInsets.all(16), child: Text('暂无搜索结果。')),
      );
    }

    final secretResults = results
        .where((item) => item.type == SearchResultType.secret)
        .toList(growable: false);
    final noteResults = results
        .where((item) => item.type == SearchResultType.note)
        .toList(growable: false);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '结果概览：共 ${results.length} 条，密码 ${secretResults.length} 条，笔记 ${noteResults.length} 条。',
            ),
            if (secretResults.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('密码结果', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final item in secretResults) _buildResultTile(context, item),
            ],
            if (noteResults.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('笔记结果', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final item in noteResults) _buildResultTile(context, item),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResultTile(BuildContext context, SearchResultItem item) {
    final cardExplanation = buildSearchResultCardExplanation(item);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        item.type == SearchResultType.secret
            ? Icons.lock_outline
            : Icons.note_outlined,
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
              Chip(
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                label: Text(resolveSearchResultHitLabel(item)),
              ),
              for (final source in item.matchSources)
                Chip(
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  label: Text(_matchSourceLabel(source)),
                ),
              if (item.semanticRawSimilarity != null)
                Chip(
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  label: Text(
                    '相似度 ${(item.semanticRawSimilarity!.clamp(0, 1) * 100).toStringAsFixed(0)}%',
                  ),
                ),
              if (item.semanticScore != null)
                Chip(
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  label: Text('排序分 ${item.semanticScore!.toStringAsFixed(3)}'),
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
          if (cardExplanation != null) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.secondaryContainer.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                cardExplanation,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
          if (_rankingReasonLines(item).isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primaryContainer.withValues(alpha: 0.55),
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
          if (item.semanticHitSummary != null &&
              item.semanticHitSummary!.isNotEmpty) ...[
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
                  for (final line in _semanticExplanationLines(
                    item.semanticHitSummary!,
                  ))
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
        final source = _searchSourceValue(item.matchSources);
        final query = item.title;
        final contextValue = item.semanticHitSummary ?? item.preview;
        if (item.type == SearchResultType.secret) {
          context.push(
            AppDestination.secretDetail(
              item.id,
              query: query,
              source: source,
              context: contextValue,
            ),
          );
        } else {
          context.push(
            AppDestination.noteDetail(
              item.id,
              query: query,
              source: source,
              context: contextValue,
            ),
          );
        }
      },
    );
  }

  String _searchSourceValue(Set<SearchMatchSource> matchSources) {
    final hasKeyword = matchSources.contains(SearchMatchSource.keyword);
    final hasSemantic = matchSources.contains(SearchMatchSource.semantic);
    if (hasKeyword && hasSemantic) {
      return 'keyword_semantic';
    }
    if (hasSemantic) {
      return 'semantic';
    }
    return 'keyword';
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

    final semanticFieldReason = _semanticFieldPriorityReason(
      item.semanticHitField,
    );
    if (semanticFieldReason != null) {
      lines.add(semanticFieldReason);
    }

    final semanticTierReason = resolveSemanticTierReason(item);
    if (semanticTierReason != null) {
      lines.add(semanticTierReason);
    }

    return lines;
  }

  String? _semanticFieldPriorityReason(SemanticHitField? field) {
    final mappedField = switch (field) {
      SemanticHitField.title => SemanticLikeField.title,
      SemanticHitField.username => SemanticLikeField.username,
      SemanticHitField.url => SemanticLikeField.website,
      SemanticHitField.secretNote => SemanticLikeField.note,
      SemanticHitField.summary => SemanticLikeField.summary,
      SemanticHitField.noteBody => SemanticLikeField.content,
      SemanticHitField.tags => SemanticLikeField.tags,
      null => null,
    };

    final hint = resolveSemanticFieldFocusHint(mappedField);
    if (hint == null) {
      return null;
    }

    return '优先查看$hint';
  }
}
