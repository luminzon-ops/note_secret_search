import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/core/logging/app_logger.dart';
import 'package:note_secret_search/core/logging/logging_providers.dart';
import 'package:note_secret_search/features/ai_chat/application/llm_runtime_providers.dart';
import 'package:note_secret_search/features/ai_chat/application/multimodal_llm_runtime_providers.dart';
import 'package:note_secret_search/features/ai_chat/domain/llm_runtime_bridge.dart';
import 'package:note_secret_search/features/ai_chat/infrastructure/local_llm_engine.dart';
import 'package:note_secret_search/features/ai_models/application/model_catalog_providers.dart';
import 'package:note_secret_search/features/ai_models/application/model_download_providers.dart';
import 'package:note_secret_search/features/ai_models/application/model_runtime_providers.dart';
import 'package:note_secret_search/features/ai_models/domain/model_artifact_path.dart';
import 'package:note_secret_search/features/ai_models/domain/model_artifact_store.dart';
import 'package:note_secret_search/features/ai_models/domain/model_catalog_entry.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/ai_models/domain/model_revision_store.dart';
import 'package:note_secret_search/features/ai_models/domain/model_runtime.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/asset_bundled_model_artifact_stager.dart';
import 'package:note_secret_search/features/search/application/embedding_runtime_providers.dart';
import 'package:note_secret_search/features/search/application/search_index_write_fence.dart';
import 'package:note_secret_search/features/search/domain/embedding_engine.dart';
import 'package:note_secret_search/features/search/infrastructure/onnx_embedding_engine.dart';

List<Override> modelRuntimeFixtureOverrides({
  ModelArtifactStore artifactStore = const _FixtureModelArtifactStore(),
  ModelRevisionStore revisionStore = const _FixtureModelRevisionStore(),
}) {
  return <Override>[
    loggerProvider.overrideWithValue(const AppLogger()),
    modelRuntimeCoordinatorProvider.overrideWith((ref) {
      return FixtureModelRuntimeCoordinator(ref);
    }),
    bundledModelArtifactStagerProvider.overrideWith((ref) {
      return AssetBundledModelArtifactStager(assetBundle: rootBundle);
    }),
    modelArtifactStoreProvider.overrideWithValue(artifactStore),
    modelRevisionStoreProvider.overrideWithValue(revisionStore),
  ];
}

class FixtureModelRuntimeCoordinator implements ModelRuntimeCoordinator {
  const FixtureModelRuntimeCoordinator(this._ref);

  final Ref _ref;

  @override
  Future<ModelRuntimeState> inspectInstalledModel(
    ModelRegistryEntry entry,
  ) async {
    switch (entry.type) {
      case 'embedding':
        final catalog = await _catalogEntry(entry.id);
        final payload = await _ref
            .read(embeddingRuntimeBridgeProvider)
            .inspectModel(
              modelId: entry.id,
              modelPath: entry.localPath!,
              tokenizer: catalog?.tokenizer,
              runtime: catalog?.runtime,
              verifiedChecksum: entry.checksum,
            );
        return _fromEmbedding(
          mapEmbeddingEngineState(payload, fallbackPath: entry.localPath),
        );
      case 'llm':
        final bridge = _ref.read(llmRuntimeBridgeProvider);
        final payload = bridge is RequestIdentifiedLlmRuntimeBridge
            ? await (bridge as RequestIdentifiedLlmRuntimeBridge)
                  .ensureIdentifiedModelReady(
                    modelId: entry.id,
                    modelPath: entry.localPath!,
                    verifiedChecksum: entry.checksum,
                  )
            : await bridge.ensureModelReady(
                modelId: entry.id,
                modelPath: entry.localPath!,
              );
        return mapLlmRuntimeState(payload, fallbackPath: entry.localPath);
      default:
        return ModelRuntimeState(
          ready: false,
          reason: 'unsupported runtime',
          status: ModelRuntimeStatus.degraded,
          modelPath: entry.localPath,
        );
    }
  }

  @override
  Future<void> releaseForMutation(
    String modelId, {
    required String? modelType,
  }) async {
    _ref.read(searchIndexWriteFenceProvider).invalidate();
    if (modelType == null || modelType == 'embedding') {
      await _ref
          .read(embeddingRuntimeBridgeProvider)
          .releaseModel(modelId: modelId);
    }
    if (modelType == null ||
        modelType == 'llm' ||
        modelType == 'multimodal_llm') {
      await _ref.read(llmRuntimeBridgeProvider).releaseModel(modelId: modelId);
    }
  }

  @override
  Future<ModelRuntimeState> validateCandidate({
    required ModelCatalogEntry entry,
    required String modelPath,
    required String verifiedChecksum,
    String? multimodalProjectorPath,
  }) async {
    switch (entry.type) {
      case 'embedding':
        final payload = await _ref
            .read(embeddingRuntimeBridgeProvider)
            .ensureModelReady(
              modelId: entry.id,
              modelPath: modelPath,
              tokenizer: entry.tokenizer,
              runtime: entry.runtime,
              verifiedChecksum: verifiedChecksum,
            );
        return _fromEmbedding(
          mapEmbeddingEngineState(payload, fallbackPath: modelPath),
        );
      case 'llm':
        final bridge = _ref.read(llmRuntimeBridgeProvider);
        final payload = bridge is RequestIdentifiedLlmRuntimeBridge
            ? await (bridge as RequestIdentifiedLlmRuntimeBridge)
                  .ensureIdentifiedModelReady(
                    modelId: entry.id,
                    modelPath: modelPath,
                    verifiedChecksum: verifiedChecksum,
                  )
            : await bridge.ensureModelReady(
                modelId: entry.id,
                modelPath: modelPath,
              );
        return mapLlmRuntimeState(payload, fallbackPath: modelPath);
      case 'multimodal_llm':
        final payload = await _ref
            .read(multimodalLlmRuntimeBridgeProvider)
            .ensureModelReady(
              modelId: entry.id,
              modelPath: modelPath,
              mmprojPath: multimodalProjectorPath!,
            );
        return _fromPayload(payload, modelPath);
      default:
        return ModelRuntimeState(
          ready: false,
          reason: 'unsupported runtime',
          status: ModelRuntimeStatus.degraded,
          modelPath: modelPath,
        );
    }
  }

  Future<ModelCatalogEntry?> _catalogEntry(String modelId) async {
    final catalog = await _ref.read(modelCatalogEntriesProvider.future);
    return catalog.where((entry) => entry.id == modelId).firstOrNull;
  }
}

ModelRuntimeState _fromEmbedding(EmbeddingEngineState state) {
  return ModelRuntimeState(
    ready: state.ready,
    reason: state.reason,
    status: switch (state.status) {
      EmbeddingRuntimeStatus.notInstalled => ModelRuntimeStatus.notInstalled,
      EmbeddingRuntimeStatus.missing => ModelRuntimeStatus.missing,
      EmbeddingRuntimeStatus.corrupted => ModelRuntimeStatus.corrupted,
      EmbeddingRuntimeStatus.installedUnverified =>
        ModelRuntimeStatus.installedUnverified,
      EmbeddingRuntimeStatus.ready => ModelRuntimeStatus.ready,
      EmbeddingRuntimeStatus.degraded => ModelRuntimeStatus.degraded,
    },
    modelPath: state.modelPath,
    checkedAt: state.checkedAt,
  );
}

ModelRuntimeState _fromPayload(Map<String, dynamic> payload, String modelPath) {
  final status = switch (payload['status']) {
    'notInstalled' || 'not_installed' => ModelRuntimeStatus.notInstalled,
    'missing' => ModelRuntimeStatus.missing,
    'corrupted' => ModelRuntimeStatus.corrupted,
    'installedUnverified' ||
    'installed_unverified' => ModelRuntimeStatus.installedUnverified,
    'ready' => ModelRuntimeStatus.ready,
    _ => ModelRuntimeStatus.degraded,
  };
  return ModelRuntimeState(
    ready: payload['ready'] as bool? ?? status == ModelRuntimeStatus.ready,
    reason: payload['reason'] as String? ?? 'runtime unavailable',
    status: status,
    modelPath: payload['modelPath'] as String? ?? modelPath,
  );
}

class _FixtureModelArtifactStore implements ModelArtifactStore {
  const _FixtureModelArtifactStore();

  @override
  Future<void> deleteModelArtifacts({
    required String modelId,
    required String? primaryPath,
    required List<ModelArtifactPath> artifacts,
  }) async {}
}

class _FixtureModelRevisionStore implements ModelRevisionStore {
  const _FixtureModelRevisionStore();

  @override
  Future<void> discardInstalledRevision({
    required String modelId,
    required String revisionRoot,
  }) async {}

  @override
  Future<InstalledModelRevision> installVerifiedRevision({
    required String modelId,
    required String operationId,
    required int generation,
    required List<StagedModelArtifact> artifacts,
  }) async {
    return InstalledModelRevision(
      revisionRoot: 'fixture://$modelId/$generation',
      pathsByArtifactId: <String, String>{
        for (final artifact in artifacts)
          artifact.artifactId: artifact.stagingPath,
      },
    );
  }

  @override
  Future<void> recoverInterruptedInstalls({required String modelId}) async {}

  @override
  Future<StagedModelArtifact> stageExistingArtifact({
    required String modelId,
    required String operationId,
    required String artifactId,
    required String relativePath,
    required String sourcePath,
    required int expectedSizeBytes,
    required String expectedChecksum,
  }) async {
    return StagedModelArtifact(
      artifactId: artifactId,
      relativePath: relativePath,
      stagingPath: sourcePath,
      expectedSizeBytes: expectedSizeBytes,
      expectedChecksum: expectedChecksum,
    );
  }
}
