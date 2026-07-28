import 'package:note_secret_search/features/ai_models/domain/model_catalog_entry.dart';
import 'package:note_secret_search/features/ai_models/domain/llm_runtime_status.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/search/domain/embedding_engine.dart';

String formatModelCapabilitySummary(ModelRegistryEntry model) {
  final segments = <String>[model.provider, model.type];
  if (model.quantization != null && model.quantization!.isNotEmpty) {
    segments.add(model.quantization!);
  }
  if (model.version != null && model.version!.isNotEmpty) {
    segments.add('版本 ${model.version!}');
  }
  if (model.sizeBytes != null && model.sizeBytes! > 0) {
    segments.add(_formatModelSize(model.sizeBytes!));
  }
  if (model.minRamMb != null && model.minRamMb! > 0) {
    segments.add('RAM ≥ ${model.minRamMb}MB');
  }
  if (model.recommendedTier != null && model.recommendedTier!.isNotEmpty) {
    segments.add('推荐档位 ${model.recommendedTier!}');
  }
  return segments.join(' · ');
}

String formatSearchSettingsDeploymentStatus(ModelRegistryEntry model) {
  if (model.isInstalled) {
    return '部署状态：本地文件已就绪，可用于当前语义检索。';
  }
  return '部署状态：模型记录仍在，但本地文件缺失，需要重新下载或修复。';
}

String formatInstalledModelDeploymentStatus(
  ModelRegistryEntry entry, {
  EmbeddingEngineState? runtimeState,
  LlmRuntimeState? llmRuntimeState,
}) {
  if (entry.type == 'embedding' && runtimeState != null) {
    switch (runtimeState.status) {
      case EmbeddingRuntimeStatus.ready:
        return '部署状态：本地已就绪。';
      case EmbeddingRuntimeStatus.installedUnverified:
        return '部署状态：本地已安装，但运行时尚未校验。';
      case EmbeddingRuntimeStatus.degraded:
        return '部署状态：运行时异常，当前不可直接使用。';
      case EmbeddingRuntimeStatus.missing:
      case EmbeddingRuntimeStatus.notInstalled:
        return '部署状态：本地文件缺失，当前记录不可直接使用。';
      case EmbeddingRuntimeStatus.corrupted:
        return '部署状态：本地文件校验失败，需要重新下载或修复。';
    }
  }

  if (entry.type == 'llm' && llmRuntimeState != null) {
    switch (llmRuntimeState.status) {
      case LlmRuntimeStatus.ready:
        return '部署状态：本地已就绪，可用于本地问答。';
      case LlmRuntimeStatus.installedUnverified:
        return '部署状态：本地已安装，但运行时尚未校验。';
      case LlmRuntimeStatus.degraded:
        return '部署状态：运行时异常，当前不可直接使用。';
      case LlmRuntimeStatus.missing:
      case LlmRuntimeStatus.notInstalled:
        return '部署状态：本地文件缺失，当前记录不可直接使用。';
      case LlmRuntimeStatus.corrupted:
        return '部署状态：本地文件校验失败，需要重新下载或修复。';
    }
  }

  if (entry.isInstalled) {
    return '部署状态：本地已就绪。';
  }
  return '部署状态：本地文件缺失，当前记录不可直接使用。';
}

String formatCatalogDeploymentStatus(
  ModelRegistryEntry? installedEntry, {
  EmbeddingEngineState? runtimeState,
  LlmRuntimeState? llmRuntimeState,
}) {
  if (installedEntry == null) {
    return '部署状态：尚未下载到本地。';
  }
  if (installedEntry.type == 'embedding' && runtimeState != null) {
    switch (runtimeState.status) {
      case EmbeddingRuntimeStatus.ready:
        return '部署状态：本地已就绪，可用于后续启用或检索配置。';
      case EmbeddingRuntimeStatus.installedUnverified:
        return '部署状态：本地文件已安装，待运行时校验。';
      case EmbeddingRuntimeStatus.degraded:
        return '部署状态：运行时初始化失败，当前不可用于语义检索。';
      case EmbeddingRuntimeStatus.missing:
      case EmbeddingRuntimeStatus.notInstalled:
        return '部署状态：本地记录存在，但文件缺失，需要重新下载。';
      case EmbeddingRuntimeStatus.corrupted:
        return '部署状态：本地文件校验失败，需要重新下载或修复。';
    }
  }
  if (installedEntry.type == 'llm' && llmRuntimeState != null) {
    switch (llmRuntimeState.status) {
      case LlmRuntimeStatus.ready:
        return '部署状态：本地已就绪，可用于本地问答。';
      case LlmRuntimeStatus.installedUnverified:
        return '部署状态：本地文件已安装，待运行时校验。';
      case LlmRuntimeStatus.degraded:
        return '部署状态：运行时初始化失败，当前不可用于本地问答。';
      case LlmRuntimeStatus.missing:
      case LlmRuntimeStatus.notInstalled:
        return '部署状态：本地记录存在，但文件缺失，需要重新下载。';
      case LlmRuntimeStatus.corrupted:
        return '部署状态：本地文件校验失败，需要重新下载或修复。';
    }
  }
  if (installedEntry.isInstalled) {
    return '部署状态：本地已就绪，可用于后续启用或检索配置。';
  }
  return '部署状态：本地记录存在，但文件缺失，需要重新下载。';
}

bool isCatalogEntryDownloadSupported(ModelCatalogEntry entry) {
  return entry.type == 'embedding' || entry.type == 'llm';
}

String formatCatalogRuntimeSupportStatus(ModelCatalogEntry entry) {
  if (isCatalogEntryDownloadSupported(entry)) {
    return '运行时支持：当前版本支持下载部署。';
  }
  return '运行时支持：当前版本尚不支持 ${entry.type}；需要专用 runtime 后才能下载部署。';
}

String _formatModelSize(int bytes) {
  final mb = bytes / (1024 * 1024);
  if (mb >= 1024) {
    return '${(mb / 1024).toStringAsFixed(1)} GB';
  }
  return '${mb.toStringAsFixed(1)} MB';
}

/// Formats a source label without deriving trust UI from signature metadata.
String formatSourceLabelWithTrust(ModelSourceEntry source) {
  return source.label;
}

/// Signature verification is unavailable, so no source-specific trust caption is shown.
String? formatEffectiveSourceTrustCaption(ModelSourceEntry? effectiveSource) {
  return null;
}

/// Signature metadata does not produce explanatory trust copy.
String? formatGenericTrustExplainer(List<ModelSourceEntry> sources) {
  return null;
}

/// Signature metadata never enables trust UI until verification is implemented.
bool shouldShowGenericTrustExplainer(List<ModelSourceEntry> sources) {
  return false;
}
