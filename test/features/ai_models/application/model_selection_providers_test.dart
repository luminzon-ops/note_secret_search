import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/ai_chat/application/llm_runtime_providers.dart';
import 'package:note_secret_search/features/ai_chat/domain/llm_runtime_status.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:note_secret_search/features/ai_models/application/model_download_providers.dart';
import 'package:note_secret_search/features/ai_models/application/model_selection_providers.dart';
import 'package:note_secret_search/features/ai_models/domain/active_model_selection.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/settings/application/security_settings_providers.dart';
import 'package:note_secret_search/features/search/application/search_providers.dart';
import 'package:note_secret_search/features/search/domain/embedding_engine.dart';
import 'package:note_secret_search/features/search/domain/search_scope.dart';

const _embeddingModel = ModelRegistryEntry(
  id: 'embed-1',
  type: 'embedding',
  provider: 'builtin',
  name: 'MiniLM Embedding',
  version: '1.0.2',
  sizeBytes: 10485760,
  quantization: 'Q8',
  minRamMb: 512,
  recommendedTier: 'mvp',
  localPath: '/data/models/minilm.onnx',
  checksum: 'abc',
  enabled: true,
  installedAt: null,
  filePresent: true,
);

const _llmModel = ModelRegistryEntry(
  id: 'llm-1',
  type: 'llm',
  provider: 'builtin',
  name: 'Phi Local',
  version: '1.0.0',
  sizeBytes: 104857600,
  quantization: 'Q4_K_M',
  minRamMb: 2048,
  recommendedTier: 'local',
  localPath: '/data/models/phi.gguf',
  checksum: 'abc',
  enabled: true,
  installedAt: null,
  filePresent: true,
);

void main() {
  test('semanticSearchReadinessProvider reports unverified runtime as not ready', () async {
    final container = ProviderContainer(
      overrides: [
        activeModelSelectionProvider.overrideWith(
          (ref) async => const ActiveModelSelection(activeEmbeddingModelId: 'embed-1'),
        ),
        modelRegistryEntriesProvider.overrideWith((ref) async => const [_embeddingModel]),
        embeddingRuntimeStatesProvider.overrideWith(
          (ref) async => {
            'embed-1': const EmbeddingEngineState(
              ready: false,
              reason: 'waiting verification',
              status: EmbeddingRuntimeStatus.installedUnverified,
            ),
          },
        ),
        searchScopeConfigProvider.overrideWith((ref) async => const SearchScopeConfig.defaults()),
      ],
    );

    addTearDown(container.dispose);

    final readiness = await container.read(semanticSearchReadinessProvider.future);
    expect(readiness.ready, isFalse);
    expect(readiness.runtimeStatus, EmbeddingRuntimeStatus.installedUnverified);
    expect(readiness.reason, '已选择模型 MiniLM Embedding，但运行时尚未完成校验，暂不能用于语义检索。');
  });

  test('activeEmbeddingModelProvider returns selected model even when runtime degraded', () async {
    final container = ProviderContainer(
      overrides: [
        activeModelSelectionProvider.overrideWith(
          (ref) async => const ActiveModelSelection(activeEmbeddingModelId: 'embed-1'),
        ),
        modelRegistryEntriesProvider.overrideWith((ref) async => const [_embeddingModel]),
        embeddingRuntimeStatesProvider.overrideWith(
          (ref) async => {
            'embed-1': const EmbeddingEngineState(
              ready: false,
              reason: 'session failed',
              status: EmbeddingRuntimeStatus.degraded,
            ),
          },
        ),
      ],
    );

    addTearDown(container.dispose);

    final model = await container.read(activeEmbeddingModelProvider.future);
    expect(model?.id, 'embed-1');
  });

  test('activeModelSelectionProvider self-heals when selected model disappears from registry', () async {
    SharedPreferences.setMockInitialValues({'ai.active_embedding_model_id': 'embed-1'});
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((ref) async => SharedPreferences.getInstance()),
        modelRegistryEntriesProvider.overrideWith((ref) async => const <ModelRegistryEntry>[]),
        embeddingRuntimeStatesProvider.overrideWith((ref) async => const <String, EmbeddingEngineState>{}),
      ],
    );

    addTearDown(container.dispose);

    final model = await container.read(activeEmbeddingModelProvider.future);
    final selection = await container.read(activeModelSelectionProvider.future);

    expect(model, isNull);
    expect(selection.activeEmbeddingModelId, isNull);
  });

  test('activeModelSelectionProvider self-heals when selected model file is missing', () async {
    SharedPreferences.setMockInitialValues({'ai.active_embedding_model_id': 'embed-1'});
    final missingModel = _embeddingModel.copyWith(filePresent: false, enabled: false);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((ref) async => SharedPreferences.getInstance()),
        modelRegistryEntriesProvider.overrideWith((ref) async => [missingModel]),
        embeddingRuntimeStatesProvider.overrideWith(
          (ref) async => {
            'embed-1': const EmbeddingEngineState(
              ready: false,
              reason: 'missing file',
              status: EmbeddingRuntimeStatus.missing,
            ),
          },
        ),
      ],
    );

    addTearDown(container.dispose);

    final model = await container.read(activeEmbeddingModelProvider.future);
    final selection = await container.read(activeModelSelectionProvider.future);

    expect(model, isNull);
    expect(selection.activeEmbeddingModelId, isNull);
  });

  test('activeLocalLlmModelProvider preserves selection when runtime is degraded (recoverable)', () async {
    SharedPreferences.setMockInitialValues({'ai.active_llm_model_id': 'llm-1'});
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((ref) async => SharedPreferences.getInstance()),
        modelRegistryEntriesProvider.overrideWith((ref) async => const [_llmModel]),
        llmRuntimeStatesProvider.overrideWith(
          (ref) async => {
            'llm-1': const LlmRuntimeState(
              ready: false,
              reason: 'session failed',
              status: LlmRuntimeStatus.degraded,
            ),
          },
        ),
      ],
    );

    addTearDown(container.dispose);

    final model = await container.read(activeLocalLlmModelProvider.future);
    final preferences = await container.read(sharedPreferencesProvider.future);

    // Degraded is recoverable — selection and shared-pref key must be preserved
    expect(model?.id, 'llm-1');
    expect(preferences.getString('ai.active_llm_model_id'), 'llm-1');
  });

  test('activeLocalLlmModelProvider preserves selection when runtime is installedUnverified (recoverable)', () async {
    SharedPreferences.setMockInitialValues({'ai.active_llm_model_id': 'llm-1'});
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((ref) async => SharedPreferences.getInstance()),
        modelRegistryEntriesProvider.overrideWith((ref) async => const [_llmModel]),
        llmRuntimeStatesProvider.overrideWith(
          (ref) async => {
            'llm-1': const LlmRuntimeState(
              ready: false,
              reason: 'waiting verification',
              status: LlmRuntimeStatus.installedUnverified,
            ),
          },
        ),
      ],
    );

    addTearDown(container.dispose);

    final model = await container.read(activeLocalLlmModelProvider.future);
    final preferences = await container.read(sharedPreferencesProvider.future);

    // installedUnverified is recoverable — selection and shared-pref key must be preserved
    expect(model?.id, 'llm-1');
    expect(preferences.getString('ai.active_llm_model_id'), 'llm-1');
  });

  test('activeLocalLlmModelProvider self-heals when runtime probe fails after selection', () async {
    SharedPreferences.setMockInitialValues({'ai.active_llm_model_id': 'llm-1'});
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((ref) async => SharedPreferences.getInstance()),
        modelRegistryEntriesProvider.overrideWith((ref) async => const [_llmModel]),
        llmRuntimeStatesProvider.overrideWith(
          (ref) async => {
            'llm-1': const LlmRuntimeState(
              ready: false,
              reason: '真实 probe failed',
              status: LlmRuntimeStatus.degraded,
            ),
          },
        ),
      ],
    );

    addTearDown(container.dispose);

    // A degraded runtime should preserve the model (same as the recoverable case above)
    final model = await container.read(activeLocalLlmModelProvider.future);
    expect(model?.id, 'llm-1');
  });

  test('activeLocalLlmModelProvider self-heals when LLM file is missing (not recoverable)', () async {
    SharedPreferences.setMockInitialValues({'ai.active_llm_model_id': 'llm-1'});
    final missingLlmModel = _llmModel.copyWith(filePresent: false, enabled: false);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((ref) async => SharedPreferences.getInstance()),
        modelRegistryEntriesProvider.overrideWith((ref) async => [missingLlmModel]),
        llmRuntimeStatesProvider.overrideWith(
          (ref) async => {
            'llm-1': const LlmRuntimeState(
              ready: false,
              reason: 'missing file',
              status: LlmRuntimeStatus.missing,
            ),
          },
        ),
      ],
    );

    addTearDown(container.dispose);

    final model = await container.read(activeLocalLlmModelProvider.future);
    final preferences = await container.read(sharedPreferencesProvider.future);

    // Missing file is not recoverable — selection must be cleared
    expect(model, isNull);
    expect(preferences.getString('ai.active_llm_model_id'), isNull);
  });

  test('activeLocalLlmModelProvider keeps selection when runtime is ready but registry entry is stale', () async {
    SharedPreferences.setMockInitialValues({'ai.active_llm_model_id': 'llm-1'});
    final staleLlmModel = _llmModel.copyWith(enabled: false);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((ref) async => SharedPreferences.getInstance()),
        modelRegistryEntriesProvider.overrideWith((ref) async => [staleLlmModel]),
        llmRuntimeStatesProvider.overrideWith(
          (ref) async => {
            'llm-1': const LlmRuntimeState(
              ready: true,
              reason: 'runtime already warm',
              status: LlmRuntimeStatus.ready,
            ),
          },
        ),
      ],
    );

    addTearDown(container.dispose);

    final model = await container.read(activeLocalLlmModelProvider.future);
    final preferences = await container.read(sharedPreferencesProvider.future);

    expect(model?.id, 'llm-1');
    expect(preferences.getString('ai.active_llm_model_id'), 'llm-1');
  });
}
