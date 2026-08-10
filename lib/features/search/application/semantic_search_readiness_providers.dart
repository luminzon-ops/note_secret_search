import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/core/security/core_security_providers.dart';
import 'package:note_secret_search/features/ai_models/application/model_selection_sensitive_providers.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/search/application/search_index_settings_providers.dart';
import 'package:note_secret_search/features/search/domain/embedding_engine.dart';

class SemanticSearchReadiness {
  const SemanticSearchReadiness({
    required this.ready,
    required this.reason,
    this.activeEmbeddingModel,
    this.runtimeStatus,
    this.runtimeState,
  });

  final bool ready;
  final String reason;
  final ModelRegistryEntry? activeEmbeddingModel;
  final EmbeddingRuntimeStatus? runtimeStatus;
  final EmbeddingEngineState? runtimeState;
}

final semanticSearchReadinessProvider = FutureProvider<SemanticSearchReadiness>(
  (ref) {
    return guardSensitiveFuture<SemanticSearchReadiness>(
      ref,
      lockedValue: const SemanticSearchReadiness(
        ready: false,
        reason: '应用已锁定。',
      ),
      load: () async {
        final selectedRuntime = await ref.watch(
          activeEmbeddingRuntimeSelectionProvider.future,
        );
        final scope = await ref.watch(searchScopeConfigProvider.future);

        if (!scope.allowLocalEmbedding) {
          return const SemanticSearchReadiness(
            ready: false,
            reason: '本地语义检索已在当前搜索范围中关闭。',
          );
        }

        if (selectedRuntime == null) {
          return const SemanticSearchReadiness(
            ready: false,
            reason: '尚未选择本地 embedding 模型。',
          );
        }

        final runtimeState = selectedRuntime.runtimeState;
        final activeEmbeddingModel = selectedRuntime.entry;
        if (!runtimeState.ready) {
          return SemanticSearchReadiness(
            ready: false,
            reason: _runtimeBlockedReason(
              activeEmbeddingModel.name,
              runtimeState,
            ),
            activeEmbeddingModel: activeEmbeddingModel,
            runtimeStatus: runtimeState.status,
            runtimeState: runtimeState,
          );
        }

        return SemanticSearchReadiness(
          ready: true,
          reason: '本地语义检索模型已就绪：${activeEmbeddingModel.name}',
          activeEmbeddingModel: activeEmbeddingModel,
          runtimeStatus: runtimeState.status,
          runtimeState: runtimeState,
        );
      },
    );
  },
);

String _runtimeBlockedReason(
  String modelName,
  EmbeddingEngineState runtimeState,
) {
  return switch (runtimeState.status) {
    EmbeddingRuntimeStatus.notInstalled => '已选择模型 $modelName，但本地模型文件尚未安装。',
    EmbeddingRuntimeStatus.missing => '已选择模型 $modelName，但本地模型文件缺失，需要重新下载或修复。',
    EmbeddingRuntimeStatus.corrupted =>
      '已选择模型 $modelName，但本地模型文件校验失败，需要重新下载或修复。',
    EmbeddingRuntimeStatus.installedUnverified =>
      '已选择模型 $modelName，但运行时尚未完成校验，暂不能用于语义检索。',
    EmbeddingRuntimeStatus.degraded =>
      '已选择模型 $modelName，但运行时当前不可用：${runtimeState.reason}',
    EmbeddingRuntimeStatus.ready => runtimeState.reason,
  };
}
