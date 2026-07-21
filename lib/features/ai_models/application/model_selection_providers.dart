import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/app/di/bootstrap_provider.dart';
import 'package:note_secret_search/features/ai_models/domain/active_model_selection.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/ai_models/application/model_download_providers.dart';
import 'package:note_secret_search/features/search/application/search_providers.dart';
import 'package:note_secret_search/features/search/application/search_index_write_fence.dart';
import 'package:note_secret_search/features/search/domain/embedding_engine.dart';
import 'package:note_secret_search/features/settings/application/security_settings_providers.dart';

part 'model_selection_sensitive_providers.dart';

final activeModelSelectionControllerProvider = Provider<ActiveModelSelectionController>((ref) {
  return ActiveModelSelectionController(ref: ref);
});

class ActiveModelSelectionController {
  ActiveModelSelectionController({required Ref ref}) : _ref = ref;

  final Ref _ref;

  Future<void> setActiveEmbeddingModel(String? modelId) async {
    _ref.read(searchIndexWriteFenceProvider).invalidate();
    final preferences = await _ref.read(sharedPreferencesProvider.future);
    if (modelId == null || modelId.isEmpty) {
      await preferences.remove(_activeEmbeddingModelIdKey);
    } else {
      await preferences.setString(_activeEmbeddingModelIdKey, modelId);
    }

    _ref.invalidate(activeModelSelectionProvider);
    _ref.invalidate(activeEmbeddingModelProvider);
    _ref.invalidate(semanticSearchReadinessProvider);
  }
}

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

class SelectedEmbeddingRuntime {
  const SelectedEmbeddingRuntime({required this.entry, required this.runtimeState});

  final ModelRegistryEntry entry;
  final EmbeddingEngineState runtimeState;
}

EmbeddingEngineState _fallbackRuntimeState(ModelRegistryEntry entry) {
  if (entry.localPath == null || entry.localPath!.trim().isEmpty) {
    return const EmbeddingEngineState(
      ready: false,
      reason: '尚未配置本地 embedding 模型文件。',
      status: EmbeddingRuntimeStatus.notInstalled,
    );
  }

  if (!entry.filePresent) {
    return EmbeddingEngineState(
      ready: false,
      reason: '本地模型文件缺失，需要重新下载或修复。',
      status: EmbeddingRuntimeStatus.missing,
      modelPath: entry.localPath,
    );
  }

   if (entry.integrityStatus == ModelIntegrityStatus.corrupted) {
    return EmbeddingEngineState(
      ready: false,
      reason: '本地模型文件校验失败，需要重新下载或修复。',
      status: EmbeddingRuntimeStatus.corrupted,
      modelPath: entry.localPath,
    );
  }

  return EmbeddingEngineState(
    ready: entry.isInstalled,
    reason: entry.isInstalled ? '本地语义检索模型已就绪。' : '本地 embedding 模型当前不可用。',
    status: entry.isInstalled ? EmbeddingRuntimeStatus.ready : EmbeddingRuntimeStatus.degraded,
    modelPath: entry.localPath,
  );
}

String _runtimeBlockedReason(String modelName, EmbeddingEngineState runtimeState) {
  return switch (runtimeState.status) {
    EmbeddingRuntimeStatus.notInstalled => '已选择模型 $modelName，但本地模型文件尚未安装。',
    EmbeddingRuntimeStatus.missing => '已选择模型 $modelName，但本地模型文件缺失，需要重新下载或修复。',
    EmbeddingRuntimeStatus.corrupted => '已选择模型 $modelName，但本地模型文件校验失败，需要重新下载或修复。',
    EmbeddingRuntimeStatus.installedUnverified =>
      '已选择模型 $modelName，但运行时尚未完成校验，暂不能用于语义检索。',
    EmbeddingRuntimeStatus.degraded =>
      '已选择模型 $modelName，但运行时当前不可用：${runtimeState.reason}',
    EmbeddingRuntimeStatus.ready => runtimeState.reason,
  };
}

const _activeEmbeddingModelIdKey = 'ai.active_embedding_model_id';
