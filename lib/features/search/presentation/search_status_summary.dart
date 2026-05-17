import 'package:note_secret_search/features/ai_models/application/model_selection_providers.dart';
import 'package:note_secret_search/features/search/domain/embedding_engine.dart';
import 'package:note_secret_search/features/search/domain/search_index_status.dart';

enum SearchStatusPhase { blocked, needsInitialIndex, needsRefresh, lastRunFailed, ready }

enum SearchStatusPrimaryAction { openModelManagement, triggerIndex, none }

class SearchStatusSummary {
  const SearchStatusSummary({
    required this.phase,
    required this.headline,
    required this.description,
    required this.pendingCount,
    required this.lastResultSummary,
    required this.errorText,
    required this.primaryActionLabel,
    required this.primaryAction,
  });

  final SearchStatusPhase phase;
  final String headline;
  final String description;
  final int pendingCount;
  final String? lastResultSummary;
  final String? errorText;
  final String? primaryActionLabel;
  final SearchStatusPrimaryAction primaryAction;
}

SearchStatusSummary buildSearchStatusSummary({
  required SemanticSearchReadiness readiness,
  required SearchIndexStatus status,
}) {
  final lastSummary = _lastResultSummary(status.taskState);

  if (!status.readyForIndexing) {
    final actionLabel = switch (readiness.runtimeStatus) {
      EmbeddingRuntimeStatus.installedUnverified => '前往模型管理完成校验',
      EmbeddingRuntimeStatus.degraded => '前往模型管理排查',
      EmbeddingRuntimeStatus.corrupted => '前往模型管理重新下载',
      EmbeddingRuntimeStatus.missing || EmbeddingRuntimeStatus.notInstalled => '前往模型管理',
      EmbeddingRuntimeStatus.ready || null => '前往模型管理',
    };

    return SearchStatusSummary(
      phase: SearchStatusPhase.blocked,
      headline: '本地语义链路未就绪',
      description: readiness.reason,
      pendingCount: status.pendingItems.length,
      lastResultSummary: lastSummary,
      errorText: status.taskState.lastError,
      primaryActionLabel: actionLabel,
      primaryAction: SearchStatusPrimaryAction.openModelManagement,
    );
  }

  if (status.taskState.lastError != null) {
    return SearchStatusSummary(
      phase: SearchStatusPhase.lastRunFailed,
      headline: '最近一次索引失败',
      description: '索引任务未成功完成，建议先重试索引再判断语义检索效果。',
      pendingCount: status.pendingItems.length,
      lastResultSummary: lastSummary,
      errorText: status.taskState.lastError,
      primaryActionLabel: '重试索引',
      primaryAction: SearchStatusPrimaryAction.triggerIndex,
    );
  }

  if (status.pendingItems.isNotEmpty && status.taskState.lastCompletedAt == null) {
    return SearchStatusSummary(
      phase: SearchStatusPhase.needsInitialIndex,
      headline: '建议先构建本地索引',
      description: '已有待索引内容，完成首次构建后再查看语义检索结果会更稳定。',
      pendingCount: status.pendingItems.length,
      lastResultSummary: lastSummary,
      errorText: null,
      primaryActionLabel: '立即构建索引',
      primaryAction: SearchStatusPrimaryAction.triggerIndex,
    );
  }

  if (status.pendingItems.isNotEmpty) {
    return SearchStatusSummary(
      phase: SearchStatusPhase.needsRefresh,
      headline: '索引需要刷新',
      description: '索引已有新变更，建议刷新后再判断当前语义检索结果。',
      pendingCount: status.pendingItems.length,
      lastResultSummary: lastSummary,
      errorText: null,
      primaryActionLabel: '刷新索引',
      primaryAction: SearchStatusPrimaryAction.triggerIndex,
    );
  }

  return SearchStatusSummary(
    phase: SearchStatusPhase.ready,
    headline: '本地语义检索已可用',
    description: readiness.reason,
    pendingCount: 0,
    lastResultSummary: lastSummary,
    errorText: null,
    primaryActionLabel: null,
    primaryAction: SearchStatusPrimaryAction.none,
  );
}

String? _lastResultSummary(SearchIndexTaskState taskState) {
  if (taskState.lastCompletedAt == null) {
    return null;
  }
  if (taskState.lastError != null) {
    return '最近一次完成 0 项，仍有错误需要处理。';
  }
  return '最近一次完成 ${taskState.lastIndexedCount} 项，当前无错误。';
}
