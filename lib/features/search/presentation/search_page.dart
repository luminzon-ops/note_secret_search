import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:note_secret_search/features/ai_models/application/model_selection_providers.dart';
import 'package:note_secret_search/features/search/application/semantic_quality_policy.dart';
import 'package:note_secret_search/features/search/application/search_providers.dart';
import 'package:note_secret_search/features/search/domain/embedding_engine.dart';
import 'package:note_secret_search/features/search/domain/search_result_item.dart';
import 'package:note_secret_search/features/search/domain/semantic_search_result.dart';
import 'package:note_secret_search/features/search/presentation/search_result_explanation.dart';
import 'package:note_secret_search/features/search/presentation/search_status_summary.dart';
import 'package:note_secret_search/features/search/presentation/detail_search_hit_target.dart';

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
    final readinessAsync = ref.watch(semanticSearchReadinessProvider);
    final indexStatusAsync = ref.watch(searchIndexStatusProvider);
    final refreshSession = ref.watch(searchRefreshSessionProvider);
    final refreshFeedback = ref.watch(searchRefreshFeedbackProvider);
    final pendingReindexHandoff = ref.watch(searchPendingReindexHandoffProvider);
    final query = ref.watch(searchQueryProvider).trim();

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
          if (pendingReindexHandoff.visible)
            _SearchPendingReindexHandoffCard(handoff: pendingReindexHandoff)
          else
            const SizedBox.shrink(),
          const SizedBox(height: 16),
          readinessAsync.when(
            data: (readiness) => indexStatusAsync.when(
              data: (status) => _SearchStatusCard(
                summary: buildSearchStatusSummary(readiness: readiness, status: status),
                refreshSession: refreshSession,
              ),
              loading: () => const SizedBox.shrink(),
              error: (error, stackTrace) => Text(error.toString()),
            ),
            loading: () => const SizedBox.shrink(),
            error: (error, stackTrace) => Text(error.toString()),
          ),
          const SizedBox(height: 16),
          if (_shouldShowRefreshFeedback(
            query: query,
            feedback: refreshFeedback,
            refreshSession: refreshSession,
          ))
            _SearchRefreshFeedbackCard(feedback: refreshFeedback)
          else
            const SizedBox.shrink(),
          const SizedBox(height: 16),
          if (unifiedResultsAsync.hasValue && semanticResultsAsync.hasValue)
            _SearchFeedbackCard(
              query: query,
              readiness: readinessAsync.valueOrNull,
              unifiedResults: unifiedResultsAsync.requireValue,
              semanticResults: semanticResultsAsync.requireValue,
            )
          else
            const SizedBox.shrink(),
          const SizedBox(height: 16),
          if (unifiedResultsAsync.hasValue && semanticResultsAsync.hasValue)
            _SearchPipelineSummaryCard(
              unifiedResults: unifiedResultsAsync.requireValue,
              semanticResults: semanticResultsAsync.requireValue,
            )
          else
            const SizedBox.shrink(),
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

  bool _shouldShowRefreshFeedback({
    required String query,
    required SearchRefreshFeedbackState feedback,
    required SearchRefreshSessionState refreshSession,
  }) {
    if (refreshSession.refreshing || !feedback.visible) {
      return false;
    }

    if (feedback.queryAtRefresh == null) {
      return false;
    }

    return feedback.queryAtRefresh == query;
  }
}

class _SearchStatusCard extends ConsumerWidget {
  const _SearchStatusCard({required this.summary, required this.refreshSession});

  final SearchStatusSummary summary;
  final SearchRefreshSessionState refreshSession;

  Future<void> _handleIndexAction(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(searchIndexControllerProvider).indexPendingAndRefresh();
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已开始构建索引，请稍后刷新搜索结果。')),
      );
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('索引触发失败，请稍后重试。')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(summary.headline, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(summary.description),
            if (summary.pendingCount > 0) ...[
              const SizedBox(height: 8),
              Text('待索引内容：${summary.pendingCount} 项'),
            ],
            if (summary.lastResultSummary != null) ...[
              const SizedBox(height: 8),
              Text(summary.lastResultSummary!, style: Theme.of(context).textTheme.bodySmall),
            ],
            if (refreshSession.refreshing && refreshSession.message != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(refreshSession.message!)),
                ],
              ),
            ],
            if (summary.errorText != null) ...[
              const SizedBox(height: 8),
              Text(summary.errorText!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            if (summary.primaryAction != SearchStatusPrimaryAction.none &&
                summary.primaryActionLabel != null) ...[
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: refreshSession.refreshing
                    ? null
                    : () {
                        switch (summary.primaryAction) {
                          case SearchStatusPrimaryAction.openModelManagement:
                            context.push('/models');
                            break;
                          case SearchStatusPrimaryAction.triggerIndex:
                            _handleIndexAction(context, ref);
                            break;
                          case SearchStatusPrimaryAction.none:
                            break;
                        }
                      },
                icon: refreshSession.refreshing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        summary.primaryAction == SearchStatusPrimaryAction.openModelManagement
                            ? Icons.memory_outlined
                            : Icons.auto_fix_high_outlined,
                      ),
                label: Text(summary.primaryActionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SearchFeedbackCard extends StatelessWidget {
  const _SearchFeedbackCard({
    required this.query,
    required this.readiness,
    required this.unifiedResults,
    required this.semanticResults,
  });

  final String query;
  final SemanticSearchReadiness? readiness;
  final List<SearchResultItem> unifiedResults;
  final List<SemanticSearchResult> semanticResults;

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('输入关键词、标签或语义描述后，这里会开始展示检索结果。'),
              SizedBox(height: 8),
              Text('你也可以先前往“搜索设置与索引”调整检索范围或索引策略。'),
            ],
          ),
        ),
      );
    }

    if (unifiedResults.isNotEmpty || semanticResults.isNotEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('当前查询暂无命中结果。'),
            const SizedBox(height: 8),
            Text(_emptyResultHint()),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: () => context.push(_emptyResultActionRoute()),
              icon: Icon(_emptyResultActionIcon()),
              label: Text(_emptyResultActionLabel()),
            ),
          ],
        ),
      ),
    );
  }

  String _emptyResultHint() {
    final currentReadiness = readiness;
    if (currentReadiness == null || currentReadiness.ready) {
      return '本次未找到匹配结果，建议检查检索范围、查询词，或刷新索引后再试。';
    }

    return switch (currentReadiness.runtimeStatus) {
      EmbeddingRuntimeStatus.installedUnverified =>
        '当前语义模型已安装但尚未完成运行时校验，本次还无法参与语义检索。',
      EmbeddingRuntimeStatus.degraded =>
        '当前语义模型存在运行时异常，本次无法稳定参与语义检索，建议先前往模型管理排查。',
      EmbeddingRuntimeStatus.corrupted =>
        '当前语义模型文件校验失败或已损坏，本次无法参与语义检索，建议前往模型管理重新下载或修复。',
      EmbeddingRuntimeStatus.missing || EmbeddingRuntimeStatus.notInstalled =>
        '当前语义模型文件缺失或尚未安装，本次仅能依赖关键词检索。',
      EmbeddingRuntimeStatus.ready || null => '本次未找到匹配结果，建议检查检索范围、查询词，或刷新索引后再试。',
    };
  }

  String _emptyResultActionLabel() {
    final currentReadiness = readiness;
    if (currentReadiness == null || currentReadiness.ready) {
      return '前往搜索设置与索引';
    }
    return '前往模型管理';
  }

  String _emptyResultActionRoute() {
    final currentReadiness = readiness;
    if (currentReadiness == null || currentReadiness.ready) {
      return '/search/settings';
    }
    return '/models';
  }

  IconData _emptyResultActionIcon() {
    final currentReadiness = readiness;
    if (currentReadiness == null || currentReadiness.ready) {
      return Icons.tune_outlined;
    }
    return Icons.memory_outlined;
  }
}

class _SearchPipelineSummaryCard extends StatelessWidget {
  const _SearchPipelineSummaryCard({
    required this.unifiedResults,
    required this.semanticResults,
  });

  static const _qualityPolicy = SemanticQualityPolicy.conservativeMvp();

  final List<SearchResultItem> unifiedResults;
  final List<SemanticSearchResult> semanticResults;

  @override
  Widget build(BuildContext context) {
    final topSummary = buildSearchPipelineTopSummary(
      unifiedResults: unifiedResults,
      semanticResults: semanticResults,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('当前检索链路', style: Theme.of(context).textTheme.titleMedium),
            _SearchPipelinePrimarySummary(
              summaryText: topSummary.summaryText,
              explanation: topSummary.explanation,
              keywordCount: topSummary.keywordCount,
              semanticResultCount: topSummary.semanticResultCount,
            ),
            const SizedBox(height: 12),
            _SearchObservabilitySummaryBlock(summary: topSummary.observability),
            _SearchSemanticQualityHintBlock(
              show: topSummary.showSemanticQualityHint,
              qualityHint: _qualityPolicy.searchPageQualityHint,
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchPipelinePrimarySummary extends StatelessWidget {
  const _SearchPipelinePrimarySummary({
    required this.summaryText,
    required this.explanation,
    required this.keywordCount,
    required this.semanticResultCount,
  });

  final String summaryText;
  final SearchResultExplanationSummary explanation;
  final int keywordCount;
  final int semanticResultCount;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(summaryText),
        const SizedBox(height: 8),
        Text(explanation.headline),
        const SizedBox(height: 8),
        Text('结果构成：$keywordCount 条关键词结果，$semanticResultCount 条语义结果。'),
        const SizedBox(height: 8),
        Text(explanation.breakdown),
        if (explanation.semanticTierBreakdown != null) ...[
          const SizedBox(height: 8),
          Text(explanation.semanticTierBreakdown!),
        ],
      ],
    );
  }
}

class _SearchObservabilitySummaryBlock extends StatefulWidget {
  const _SearchObservabilitySummaryBlock({required this.summary});

  final SearchObservabilitySummary summary;

  @override
  State<_SearchObservabilitySummaryBlock> createState() => _SearchObservabilitySummaryBlockState();
}

class _SearchObservabilitySummaryBlockState extends State<_SearchObservabilitySummaryBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final summary = widget.summary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('搜索观测摘要', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Text(summary.hitBreakdown),
          const SizedBox(height: 6),
          Text(summary.dominantSignalHint),
          if (summary.reminderHint != null) ...[
            const SizedBox(height: 6),
            Text(summary.reminderHint!),
          ],
          if (_expanded) ...[
            const SizedBox(height: 6),
            Text(summary.semanticTierBreakdown),
            if (summary.semanticOnlyFilteringBreakdown != null) ...[
              const SizedBox(height: 6),
              Text(summary.semanticOnlyFilteringBreakdown!),
            ],
            if (summary.semanticOnlyFilteringReason != null) ...[
              const SizedBox(height: 6),
              Text(summary.semanticOnlyFilteringReason!),
            ],
            if (summary.semanticFieldBreakdown != null) ...[
              const SizedBox(height: 6),
              Text(summary.semanticFieldBreakdown!),
            ],
            if (summary.dominantFieldHint != null) ...[
              const SizedBox(height: 6),
              Text(summary.dominantFieldHint!),
            ],
          ],
          const SizedBox(height: 6),
          TextButton(
            onPressed: () => setState(() => _expanded = !_expanded),
            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
            child: Text(_expanded ? '收起观测详情' : '展开更多观测'),
          ),
          if (_expanded && summary.dominantFieldHint == null && summary.semanticFieldBreakdown == null) ...[
            const SizedBox(height: 6),
            const SizedBox.shrink(),
          ],
        ],
      ),
    );
  }
}

class _SearchSemanticQualityHintBlock extends StatelessWidget {
  const _SearchSemanticQualityHintBlock({required this.show, required this.qualityHint});

  final bool show;
  final String qualityHint;

  @override
  Widget build(BuildContext context) {
    if (!show) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(qualityHint, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        Text('下方“占位语义匹配”区块展示的是当前语义召回明细。', style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _SearchRefreshFeedbackCard extends StatelessWidget {
  const _SearchRefreshFeedbackCard({required this.feedback});

  final SearchRefreshFeedbackState feedback;

  @override
  Widget build(BuildContext context) {
    final icon = feedback.changed == true ? Icons.check_circle_outline : Icons.info_outline;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (feedback.headline != null)
                    Text(feedback.headline!, style: Theme.of(context).textTheme.titleMedium),
                  if (feedback.headline != null && feedback.message != null)
                    const SizedBox(height: 8),
                  if (feedback.message != null) Text(feedback.message!),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchPendingReindexHandoffCard extends ConsumerWidget {
  const _SearchPendingReindexHandoffCard({required this.handoff});

  final SearchPendingReindexHandoffState handoff;

  Future<void> _handleRefresh(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(searchIndexControllerProvider).indexPendingAndRefresh();
      ref.read(searchPendingReindexHandoffProvider.notifier).state =
          const SearchPendingReindexHandoffState.hidden();
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('索引触发失败，请稍后重试。')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('设置已保存，但语义结果还没刷新', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(handoff.message ?? '你刚保存了会影响语义索引的设置。刷新索引后，再判断当前语义结果会更准确。'),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: () => _handleRefresh(context, ref),
              icon: const Icon(Icons.auto_fix_high_outlined),
              label: const Text('立即刷新索引'),
            ),
          ],
        ),
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

    final secretResults = results
        .where((item) => item.type == SearchResultType.secret)
        .toList(growable: false);
    final noteResults = results.where((item) => item.type == SearchResultType.note).toList(growable: false);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('结果概览：共 ${results.length} 条，密码 ${secretResults.length} 条，笔记 ${noteResults.length} 条。'),
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
      leading: Icon(item.type == SearchResultType.secret ? Icons.lock_outline : Icons.note_outlined),
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
          if (cardExplanation != null) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(cardExplanation, style: Theme.of(context).textTheme.bodySmall),
            ),
          ],
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
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  for (final line in _rankingReasonLines(item))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text('• $line', style: Theme.of(context).textTheme.bodySmall),
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
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  for (final line in _semanticExplanationLines(item.semanticHitSummary!))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text('• $line', style: Theme.of(context).textTheme.bodySmall),
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
        final query = Uri.encodeQueryComponent(item.title);
        final contextValue = Uri.encodeQueryComponent(item.semanticHitSummary ?? item.preview);
        if (item.type == SearchResultType.secret) {
          context.push('/vault/secret/${item.id}?query=$query&source=$source&context=$contextValue');
        } else {
          context.push('/notes/item/${item.id}?query=$query&source=$source&context=$contextValue');
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

    final semanticFieldReason = _semanticFieldPriorityReason(item.semanticHitField);
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
