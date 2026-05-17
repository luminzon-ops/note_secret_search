import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/ai_chat/application/llm_runtime_providers.dart';
import 'package:note_secret_search/features/ai_chat/domain/llm_engine.dart';
import 'package:note_secret_search/features/ai_chat/domain/llm_runtime_status.dart';
import 'package:note_secret_search/features/ai_chat/infrastructure/llm_runtime_bridge.dart';
import 'package:note_secret_search/features/ai_models/application/model_download_providers.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/settings/application/security_settings_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  test('active local llm controller persists selected model id', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((ref) async => SharedPreferences.getInstance()),
        modelRegistryEntriesProvider.overrideWith((ref) async => const [_llmModel]),
        llmRuntimeStatesProvider.overrideWith(
          (ref) async => {
            'llm-1': const LlmRuntimeState(
              ready: true,
              reason: 'ready',
              status: LlmRuntimeStatus.ready,
            ),
          },
        ),
      ],
    );

    addTearDown(container.dispose);

    await container.read(activeLocalLlmSelectionControllerProvider).setActiveLocalLlmModel('llm-1');

    final preferences = await container.read(sharedPreferencesProvider.future);
    final selected = await container.read(activeLocalLlmModelProvider.future);

    expect(preferences.getString('ai.active_llm_model_id'), 'llm-1');
    expect(selected?.id, 'llm-1');
  });

  test('active local llm controller clears selected model id', () async {
    SharedPreferences.setMockInitialValues({'ai.active_llm_model_id': 'llm-1'});
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((ref) async => SharedPreferences.getInstance()),
        modelRegistryEntriesProvider.overrideWith((ref) async => const [_llmModel]),
        llmRuntimeStatesProvider.overrideWith(
          (ref) async => {
            'llm-1': const LlmRuntimeState(
              ready: true,
              reason: 'ready',
              status: LlmRuntimeStatus.ready,
            ),
          },
        ),
      ],
    );

    addTearDown(container.dispose);

    await container.read(activeLocalLlmSelectionControllerProvider).setActiveLocalLlmModel(null);

    final preferences = await container.read(sharedPreferencesProvider.future);
    final selected = await container.read(activeLocalLlmModelProvider.future);

    expect(preferences.getString('ai.active_llm_model_id'), isNull);
    expect(selected, isNull);
  });

  test('activeLocalLlmModelProvider returns only ready llm models', () async {
    SharedPreferences.setMockInitialValues({'ai.active_llm_model_id': 'llm-1'});
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((ref) async => SharedPreferences.getInstance()),
        modelRegistryEntriesProvider.overrideWith((ref) async => const [_llmModel]),
        llmRuntimeStatesProvider.overrideWith(
          (ref) async => {
            'llm-1': const LlmRuntimeState(
              ready: true,
              reason: 'ready',
              status: LlmRuntimeStatus.ready,
            ),
          },
        ),
      ],
    );

    addTearDown(container.dispose);

    final model = await container.read(activeLocalLlmModelProvider.future);
    expect(model?.id, 'llm-1');
  });

  test('localLlmReadinessProvider reports missing active model', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((ref) async => SharedPreferences.getInstance()),
        modelRegistryEntriesProvider.overrideWith((ref) async => const <ModelRegistryEntry>[]),
        llmRuntimeStatesProvider.overrideWith((ref) async => const <String, LlmRuntimeState>{}),
      ],
    );

    addTearDown(container.dispose);

    final readiness = await container.read(localLlmReadinessProvider.future);
    expect(readiness.ready, isFalse);
    expect(readiness.activeModel, isNull);
    expect(readiness.reason, '尚未选择本地 LLM 模型。');
  });

  test('llmRuntimeStatesProvider surfaces degraded runtime state', () async {
    final degradedModel = _llmModel.copyWith(localPath: '/data/models/phi.gguf');
    final container = ProviderContainer(
      overrides: [
        modelRegistryEntriesProvider.overrideWith((ref) async => [degradedModel]),
        llmEngineProvider.overrideWithValue(_FakeLlmEngine()),
      ],
    );

    addTearDown(container.dispose);

    final states = await container.read(llmRuntimeStatesProvider.future);
    expect(states['llm-1']?.ready, isFalse);
    expect(states['llm-1']?.status, LlmRuntimeStatus.degraded);
    expect(states['llm-1']?.reason, 'session failed');
  });

  test('activeLocalLlmModelProvider keeps degraded selected llm model in preferences', () async {
    SharedPreferences.setMockInitialValues({'ai.active_llm_model_id': 'llm-1'});
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((ref) async => SharedPreferences.getInstance()),
        modelRegistryEntriesProvider.overrideWith((ref) async => const [_llmModel]),
        llmRuntimeStatesProvider.overrideWith(
          (ref) async => {
            'llm-1': const LlmRuntimeState(
              ready: false,
              reason: 'probe failed',
              status: LlmRuntimeStatus.degraded,
            ),
          },
        ),
      ],
    );

    addTearDown(container.dispose);

    final model = await container.read(activeLocalLlmModelProvider.future);
    final preferences = await container.read(sharedPreferencesProvider.future);
    final readiness = await container.read(localLlmReadinessProvider.future);

    expect(model?.id, 'llm-1');
    expect(preferences.getString('ai.active_llm_model_id'), 'llm-1');
    expect(readiness.ready, isFalse);
    expect(readiness.activeModel?.id, 'llm-1');
    expect(readiness.reason, 'probe failed');
  });

  test('activeLocalLlmModelProvider keeps selected llm when runtime can be ensured ready', () async {
    SharedPreferences.setMockInitialValues({'ai.active_llm_model_id': 'llm-1'});
    final bridge = _ReadyAfterEnsureBridge();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((ref) async => SharedPreferences.getInstance()),
        modelRegistryEntriesProvider.overrideWith((ref) async => const [_llmModel]),
        llmRuntimeBridgeProvider.overrideWithValue(bridge),
      ],
    );

    addTearDown(container.dispose);

    final model = await container.read(activeLocalLlmModelProvider.future);
    final preferences = await container.read(sharedPreferencesProvider.future);

    expect(model?.id, 'llm-1');
    expect(preferences.getString('ai.active_llm_model_id'), 'llm-1');
    expect(bridge.ensureCalls, 1);
  });
}

class _FakeLlmEngine implements LlmEngine {
  @override
  Future<LlmInferenceResponse> generate(LlmInferenceRequest request) {
    throw UnimplementedError();
  }

  @override
  Future<LlmRuntimeState> getState(ModelRegistryEntry model) async {
    return LlmRuntimeState(
      ready: false,
      reason: 'session failed',
      status: LlmRuntimeStatus.degraded,
      modelPath: model.localPath,
    );
  }

  @override
  Future<void> releaseModel(String modelId) async {}
}

class _ReadyAfterEnsureBridge implements LlmRuntimeBridge {
  int ensureCalls = 0;
  int inspectCalls = 0;

  @override
  Future<Map<String, dynamic>> ensureModelReady({
    required String modelId,
    required String modelPath,
  }) async {
    ensureCalls += 1;
    return <String, dynamic>{
      'ready': true,
      'reason': 'runtime loaded',
      'status': 'ready',
      'modelPath': modelPath,
    };
  }

  @override
  Future<Map<String, dynamic>> generateText({
    required String modelId,
    required String modelPath,
    required String prompt,
    required bool usedPrivateContext,
    required int maxOutputTokens,
    required int maxPromptChars,
    required int contextLength,
    required bool conservativeMode,
    required double temperature,
    required int topK,
    required double topP,
    required int seed,
    required List<String> stopSequences,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>> inspectModel({
    required String modelId,
    required String modelPath,
  }) async {
    inspectCalls += 1;
    return <String, dynamic>{
      'ready': false,
      'reason': 'installed but unverified',
      'status': 'installed_unverified',
      'modelPath': modelPath,
    };
  }

  @override
  Future<void> releaseModel({required String modelId}) async {}
}
