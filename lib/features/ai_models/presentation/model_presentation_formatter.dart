import 'package:note_secret_search/features/ai_models/domain/model_catalog_entry.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/ai_chat/domain/llm_runtime_status.dart';
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
  return entry.type == 'embedding' || entry.type == 'llm' || entry.type == 'multimodal_llm';
}

String formatCatalogRuntimeSupportStatus(ModelCatalogEntry entry) {
  if (entry.type == 'multimodal_llm') {
    return '运行时支持：需要下载主模型和视觉投影文件，部署后可进行本地多模态推理。';
  }
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

/// Formats a source label with trust suffix if the source declares artifact trust.
/// Returns the label with " (已签名)" appended if declaresArtifactTrust() is true,
/// otherwise returns the plain label.
String formatSourceLabelWithTrust(ModelSourceEntry source) {
  if (source.declaresArtifactTrust()) {
    return '${source.label} (已签名)';
  }
  return source.label;
}

/// Returns a short contextual caption for the current effective source when signed.
/// Returns null when the effective source does not declare artifact trust.
/// This is a local, source-specific trust note — distinct from the generic explainer.
String? formatEffectiveSourceTrustCaption(ModelSourceEntry? effectiveSource) {
  if (effectiveSource != null && effectiveSource.declaresArtifactTrust()) {
    return '已签名来源声明';
  }
  return null;
}

/// Returns the generic trust explainer text when any source in the entry declares artifact trust.
/// Returns null when no source declares trust.
/// The generic explainer is the single full disclaimer about unverified signatures.
String? formatGenericTrustExplainer(List<ModelSourceEntry> sources) {
  if (sources.any((s) => s.declaresArtifactTrust())) {
    return '说明：已签名仅表示来源声明附带签名信息；当前版本尚未完成签名校验，不代表文件已验证。';
  }
  return null;
}

/// Returns true when the generic trust explainer should be shown alongside
/// the source selector area.
///
/// The generic explainer is suppressed when the entry has exactly one signed
/// source (the local caption suffices). It is shown in all other cases where
/// at least one source declares artifact trust, which currently means
/// multi-source trust contexts.
///
/// Parameters:
/// - [sources]: all sources in the catalog entry
bool shouldShowGenericTrustExplainer(List<ModelSourceEntry> sources) {
  final hasAnySignedSource = sources.any((s) => s.declaresArtifactTrust());
  if (!hasAnySignedSource) return false;

  // Suppress generic explainer when there is exactly one source and it is signed.
  // The local caption ("已签名来源声明") is sufficient in that case.
  final signedSources = sources.where((s) => s.declaresArtifactTrust()).toList();
  if (signedSources.length == 1 && sources.length == 1) {
    return false;
  }

  return true;
}
