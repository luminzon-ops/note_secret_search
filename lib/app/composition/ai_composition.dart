import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/app/composition/shared_preferences_composition.dart';
import 'package:note_secret_search/core/logging/logging_providers.dart';
import 'package:note_secret_search/core/security/core_security_providers.dart';
import 'package:note_secret_search/core/storage/database/app_database_providers.dart';
import 'package:note_secret_search/core/storage/database/sqlite_model_state_repository.dart';
import 'package:note_secret_search/features/ai_chat/application/chat_session_providers.dart';
import 'package:note_secret_search/features/ai_chat/application/llm_runtime_providers.dart';
import 'package:note_secret_search/features/ai_chat/application/multimodal_llm_runtime_providers.dart';
import 'package:note_secret_search/features/ai_chat/domain/llm_engine.dart';
import 'package:note_secret_search/features/ai_chat/infrastructure/llm_runtime_bridge.dart';
import 'package:note_secret_search/features/ai_chat/infrastructure/local_llm_engine.dart';
import 'package:note_secret_search/features/ai_chat/infrastructure/multimodal_llm_runtime_bridge.dart';
import 'package:note_secret_search/features/ai_chat/infrastructure/sqlite_chat_session_repository.dart';
import 'package:note_secret_search/features/ai_models/application/device_capability_providers.dart';
import 'package:note_secret_search/features/ai_models/application/model_catalog_providers.dart';
import 'package:note_secret_search/features/ai_models/application/model_download_providers.dart';
import 'package:note_secret_search/features/ai_models/application/model_runtime_providers.dart';
import 'package:note_secret_search/features/ai_models/application/model_session_releaser.dart';
import 'package:note_secret_search/features/ai_models/domain/local_llm_selection_store.dart';
import 'package:note_secret_search/features/ai_models/domain/model_catalog_entry.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/ai_models/domain/model_runtime.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/asset_bundled_model_artifact_stager.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/asset_model_catalog_repository.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/device_profiler_bridge.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/io_model_artifact_store.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/io_model_revision_store.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/model_catalog_trust.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/model_download_service.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/model_source_probe_service.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/sqlite_model_catalog_acceptance_store.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/sqlite_model_download_repository.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/sqlite_model_lifecycle_store.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/sqlite_model_registry_repository.dart';
import 'package:note_secret_search/features/ai_providers/application/ai_provider_providers.dart';
import 'package:note_secret_search/features/ai_providers/application/external_provider_client_router.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_consent_store.dart';
import 'package:note_secret_search/features/ai_providers/infrastructure/ollama_provider_client.dart';
import 'package:note_secret_search/features/ai_providers/infrastructure/openai_compatible_provider_client.dart';
import 'package:note_secret_search/features/ai_providers/infrastructure/sqlite_external_provider_repository.dart';
import 'package:note_secret_search/features/search/application/embedding_runtime_providers.dart';
import 'package:note_secret_search/features/search/application/search_index_write_fence.dart';
import 'package:note_secret_search/features/search/domain/embedding_engine.dart';
import 'package:note_secret_search/features/search/domain/embedding_runtime.dart';
import 'package:note_secret_search/features/search/infrastructure/onnx_embedding_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

final List<Override> aiCompositionOverrides = <Override>[
  modelCatalogAcceptanceStoreProvider.overrideWith((ref) {
    return SqliteModelCatalogAcceptanceStore(
      repository: SqliteModelStateRepository(
        database: ref.watch(appDatabaseProvider),
      ),
    );
  }),
  modelCatalogRepositoryProvider.overrideWith((ref) {
    return AssetModelCatalogRepository(
      assetBundle: rootBundle,
      verifier: ModelCatalogVerifier(),
      acceptanceStore: ref.watch(modelCatalogAcceptanceStoreProvider),
    );
  }),
  deviceProfilerBridgeProvider.overrideWith((ref) {
    return DeviceProfilerBridge();
  }),
  modelDownloadRepositoryProvider.overrideWith((ref) {
    return SqliteModelDownloadRepository(
      database: ref.watch(appDatabaseProvider),
    );
  }),
  modelRegistryRepositoryProvider.overrideWith((ref) {
    return SqliteModelRegistryRepository(
      database: ref.watch(appDatabaseProvider),
      beforeMutation: ref.watch(searchIndexWriteFenceProvider).invalidate,
    );
  }),
  modelLifecycleStoreProvider.overrideWith((ref) {
    return SqliteModelLifecycleStore(
      database: ref.watch(appDatabaseProvider),
      beforeMutation: ref.watch(searchIndexWriteFenceProvider).invalidate,
    );
  }),
  modelArtifactStoreProvider.overrideWith((ref) {
    return IoModelArtifactStore();
  }),
  modelRevisionStoreProvider.overrideWith((ref) {
    return IoModelRevisionStore();
  }),
  bundledModelArtifactStagerProvider.overrideWith((ref) {
    return AssetBundledModelArtifactStager(assetBundle: rootBundle);
  }),
  modelDownloadServiceProvider.overrideWith((ref) {
    return ModelDownloadService(dio: Dio(), logger: ref.watch(loggerProvider));
  }),
  modelSourceProbeServiceProvider.overrideWith((ref) {
    return ModelSourceProbeService(
      dio: Dio(),
      logger: ref.watch(loggerProvider),
    );
  }),
  chatSessionRepositoryProvider.overrideWith((ref) {
    return SqliteChatSessionRepository(
      database: ref.watch(appDatabaseProvider),
    );
  }),
  llmRuntimeBridgeProvider.overrideWith((ref) {
    return MethodChannelLlmRuntimeBridge();
  }),
  llmEngineProvider.overrideWith((ref) {
    return LocalLlmEngine(bridge: ref.watch(llmRuntimeBridgeProvider));
  }),
  multimodalLlmRuntimeBridgeProvider.overrideWith((ref) {
    return MethodChannelMultimodalLlmRuntimeBridge();
  }),
  modelRuntimeCoordinatorProvider.overrideWith((ref) {
    return _ComposedModelRuntimeCoordinator(
      writeFence: ref.watch(searchIndexWriteFenceProvider),
      embeddingEngine: ref.watch(embeddingEngineProvider),
      embeddingRuntime: ref.watch(embeddingRuntimeBridgeProvider),
      llmEngine: ref.watch(llmEngineProvider),
      llmRuntime: ref.watch(llmRuntimeBridgeProvider),
      multimodalRuntime: ref.watch(multimodalLlmRuntimeBridgeProvider),
    );
  }),
  localLlmSelectionStoreProvider.overrideWith((ref) {
    return _SharedPreferencesLocalLlmSelectionStore(
      loadPreferences: () => ref.read(sharedPreferencesProvider.future),
    );
  }),
  externalProviderRepositoryProvider.overrideWith((ref) {
    return SqliteExternalProviderRepository(
      database: ref.watch(appDatabaseProvider),
      cryptoService: ref.watch(cryptoServiceProvider),
    );
  }),
  externalProviderClientRouterProvider.overrideWith((ref) {
    return ExternalProviderClientRouter(
      openAiCompatible: OpenAiCompatibleProviderClient(dio: Dio()),
      ollama: OllamaProviderClient(dio: Dio()),
    );
  }),
  externalProviderConsentStoreProvider.overrideWith((ref) {
    return _SharedPreferencesExternalProviderConsentStore(
      loadPreferences: () => ref.read(sharedPreferencesProvider.future),
    );
  }),
];

class _ComposedModelRuntimeCoordinator implements ModelRuntimeCoordinator {
  _ComposedModelRuntimeCoordinator({
    required SearchIndexWriteFence writeFence,
    required EmbeddingEngine embeddingEngine,
    required EmbeddingRuntimeBridge embeddingRuntime,
    required LlmEngine llmEngine,
    required LlmRuntimeBridge llmRuntime,
    required MultimodalLlmRuntimeBridge multimodalRuntime,
  }) : _embeddingEngine = embeddingEngine,
       _embeddingRuntime = embeddingRuntime,
       _llmEngine = llmEngine,
       _llmRuntime = llmRuntime,
       _multimodalRuntime = multimodalRuntime,
       _sessionReleaser = ModelSessionReleaser(
         stopWrites: writeFence.invalidate,
         releaseEmbedding: (modelId) {
           return embeddingRuntime.releaseModel(modelId: modelId);
         },
         releaseLlm: (modelId) {
           return llmRuntime.releaseModel(modelId: modelId);
         },
         shouldReleaseEmbedding: (modelType) {
           return modelType == null || modelType == 'embedding';
         },
         shouldReleaseLlm: (modelType) {
           return modelType == null ||
               modelType == 'llm' ||
               modelType == 'multimodal_llm';
         },
         shouldReleaseMultimodal: (_) => false,
       );

  final EmbeddingEngine _embeddingEngine;
  final EmbeddingRuntimeBridge _embeddingRuntime;
  final LlmEngine _llmEngine;
  final LlmRuntimeBridge _llmRuntime;
  final MultimodalLlmRuntimeBridge _multimodalRuntime;
  final ModelSessionReleaser _sessionReleaser;

  @override
  Future<ModelRuntimeState> inspectInstalledModel(
    ModelRegistryEntry entry,
  ) async {
    switch (entry.type) {
      case 'embedding':
        return _fromEmbedding(await _embeddingEngine.getState(entry));
      case 'llm':
        return _fromLlm(await _llmEngine.getState(entry));
      default:
        return ModelRuntimeState(
          ready: false,
          reason: '当前模型类型没有可用的运行时检查。',
          status: ModelRuntimeStatus.degraded,
          modelPath: entry.localPath,
        );
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
        final payload = await _embeddingRuntime.ensureModelReady(
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
        final runtime = _llmRuntime;
        final payload = runtime is RequestIdentifiedLlmRuntimeBridge
            ? await (runtime as RequestIdentifiedLlmRuntimeBridge)
                  .ensureIdentifiedModelReady(
                    modelId: entry.id,
                    modelPath: modelPath,
                    verifiedChecksum: verifiedChecksum,
                  )
            : await runtime.ensureModelReady(
                modelId: entry.id,
                modelPath: modelPath,
              );
        return _fromLlm(mapLlmRuntimeState(payload, fallbackPath: modelPath));
      case 'multimodal_llm':
        final projectorPath = multimodalProjectorPath;
        if (projectorPath == null || projectorPath.trim().isEmpty) {
          return ModelRuntimeState(
            ready: false,
            reason: '多模态投影文件缺失。',
            status: ModelRuntimeStatus.missing,
            modelPath: modelPath,
          );
        }
        final payload = await _multimodalRuntime.ensureModelReady(
          modelId: entry.id,
          modelPath: modelPath,
          mmprojPath: projectorPath,
        );
        return _fromPayload(payload, fallbackPath: modelPath);
      default:
        return ModelRuntimeState(
          ready: false,
          reason: '当前模型类型没有可用的运行时。',
          status: ModelRuntimeStatus.degraded,
          modelPath: modelPath,
        );
    }
  }

  @override
  Future<void> releaseForMutation(
    String modelId, {
    required String? modelType,
  }) {
    return _sessionReleaser.releaseForMutation(modelId, modelType: modelType);
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

ModelRuntimeState _fromLlm(ModelRuntimeState state) => state;

ModelRuntimeState _fromPayload(
  Map<String, dynamic> payload, {
  required String fallbackPath,
}) {
  final rawStatus = payload['status'] as String? ?? 'degraded';
  final status = switch (rawStatus) {
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
    reason: payload['reason'] as String? ?? '当前模型运行时未就绪。',
    status: status,
    modelPath: payload['modelPath'] as String? ?? fallbackPath,
    checkedAt: _parseCheckedAt(payload['checkedAt']),
  );
}

DateTime? _parseCheckedAt(Object? raw) {
  if (raw is num) {
    return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
  }
  return null;
}

class _SharedPreferencesLocalLlmSelectionStore
    implements LocalLlmSelectionStore {
  const _SharedPreferencesLocalLlmSelectionStore({
    required Future<SharedPreferences> Function() loadPreferences,
  }) : _loadPreferences = loadPreferences;

  static const _activeModelIdKey = 'ai.active_llm_model_id';
  final Future<SharedPreferences> Function() _loadPreferences;

  @override
  Future<String?> loadActiveModelId() async {
    final preferences = await _loadPreferences();
    return preferences.getString(_activeModelIdKey);
  }

  @override
  Future<void> saveActiveModelId(String? modelId) async {
    final preferences = await _loadPreferences();
    if (modelId == null || modelId.isEmpty) {
      await preferences.remove(_activeModelIdKey);
      return;
    }
    await preferences.setString(_activeModelIdKey, modelId);
  }
}

class _SharedPreferencesExternalProviderConsentStore
    implements ExternalProviderConsentStore {
  const _SharedPreferencesExternalProviderConsentStore({
    required Future<SharedPreferences> Function() loadPreferences,
  }) : _loadPreferences = loadPreferences;

  final Future<SharedPreferences> Function() _loadPreferences;

  @override
  Future<bool> read(String key) async {
    final preferences = await _loadPreferences();
    return preferences.getBool(key) ?? false;
  }

  @override
  Future<void> remove(String key) async {
    final preferences = await _loadPreferences();
    await preferences.remove(key);
  }

  @override
  Future<void> write(String key, bool value) async {
    final preferences = await _loadPreferences();
    await preferences.setBool(key, value);
  }
}
