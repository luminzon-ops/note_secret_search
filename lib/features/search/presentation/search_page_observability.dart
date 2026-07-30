part of 'search_page.dart';

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
      EmbeddingRuntimeStatus.missing ||
      EmbeddingRuntimeStatus.notInstalled => '当前语义模型文件缺失或尚未安装，本次仅能依赖关键词检索。',
      EmbeddingRuntimeStatus.ready ||
      null => '本次未找到匹配结果，建议检查检索范围、查询词，或刷新索引后再试。',
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
      return AppDestination.searchSettings;
    }
    return AppDestination.models;
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
    required this.fusionDiagnostics,
  });

  static const _qualityPolicy = SemanticQualityPolicy.conservativeMvp();

  final List<SearchResultItem> unifiedResults;
  final List<SemanticSearchResult> semanticResults;
  final SearchFusionDiagnostics? fusionDiagnostics;

  @override
  Widget build(BuildContext context) {
    final topSummary = buildSearchPipelineTopSummary(
      unifiedResults: unifiedResults,
      semanticResults: semanticResults,
      fusionDiagnostics: fusionDiagnostics,
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
  State<_SearchObservabilitySummaryBlock> createState() =>
      _SearchObservabilitySummaryBlockState();
}

class _SearchObservabilitySummaryBlockState
    extends State<_SearchObservabilitySummaryBlock> {
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
            if (summary.semanticVersionBreakdown != null) ...[
              const SizedBox(height: 6),
              Text(summary.semanticVersionBreakdown!),
            ],
            if (summary.dominantFieldHint != null) ...[
              const SizedBox(height: 6),
              Text(summary.dominantFieldHint!),
            ],
          ],
          const SizedBox(height: 6),
          TextButton(
            onPressed: () => setState(() => _expanded = !_expanded),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 0),
            ),
            child: Text(_expanded ? '收起观测详情' : '展开更多观测'),
          ),
          if (_expanded &&
              summary.dominantFieldHint == null &&
              summary.semanticFieldBreakdown == null) ...[
            const SizedBox(height: 6),
            const SizedBox.shrink(),
          ],
        ],
      ),
    );
  }
}

class _SearchSemanticQualityHintBlock extends StatelessWidget {
  const _SearchSemanticQualityHintBlock({
    required this.show,
    required this.qualityHint,
  });

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
        Text(
          '下方“语义匹配”区块展示的是当前语义召回明细。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
