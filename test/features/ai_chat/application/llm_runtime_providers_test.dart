import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/security/core_security_providers.dart';
import 'package:note_secret_search/features/ai_chat/application/llm_runtime_providers.dart';
import 'package:note_secret_search/features/ai_models/application/model_download_providers.dart';
import 'package:note_secret_search/features/ai_models/application/model_runtime_providers.dart';
import 'package:note_secret_search/features/ai_models/domain/llm_runtime_status.dart';
import 'package:note_secret_search/features/ai_models/domain/local_llm_selection_store.dart';
import 'package:note_secret_search/features/ai_models/domain/model_catalog_entry.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/ai_models/domain/model_runtime.dart';

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
    final store = _MemoryLocalLlmSelectionStore();
    final runtime = _FakeModelRuntimeCoordinator();
    final container = ProviderContainer(
      overrides: [
        sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
        localLlmSelectionStoreProvider.overrideWithValue(store),
        modelRuntimeCoordinatorProvider.overrideWithValue(runtime),
        modelRegistryEntriesProvider.overrideWith(
          (ref) async => const [_llmModel],
        ),
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

    await container
        .read(activeLocalLlmSelectionControllerProvider)
        .setActiveLocalLlmModel('llm-1');

    final selected = await container.read(activeLocalLlmModelProvider.future);
    expect(store.modelId, 'llm-1');
    expect(selected?.id, 'llm-1');
  });

  test(
    'active local llm controller releases before clearing selection',
    () async {
      final events = <String>[];
      final store = _MemoryLocalLlmSelectionStore(
        modelId: 'llm-1',
        onSave: (value) => events.add('save:$value'),
      );
      final runtime = _FakeModelRuntimeCoordinator(
        onRelease: (modelId, modelType) {
          events.add('release:$modelId:$modelType');
        },
      );
      final container = ProviderContainer(
        overrides: [
          localLlmSelectionStoreProvider.overrideWithValue(store),
          modelRuntimeCoordinatorProvider.overrideWithValue(runtime),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(activeLocalLlmSelectionControllerProvider)
          .setActiveLocalLlmModel(null);

      expect(events, <String>['release:llm-1:llm', 'save:null']);
      expect(store.modelId, isNull);
    },
  );

  test('activeLocalLlmModelProvider returns selected ready llm', () async {
    final store = _MemoryLocalLlmSelectionStore(modelId: 'llm-1');
    final container = ProviderContainer(
      overrides: [
        sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
        localLlmSelectionStoreProvider.overrideWithValue(store),
        modelRegistryEntriesProvider.overrideWith(
          (ref) async => const [_llmModel],
        ),
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
    final container = ProviderContainer(
      overrides: [
        sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
        localLlmSelectionStoreProvider.overrideWithValue(
          _MemoryLocalLlmSelectionStore(),
        ),
        modelRegistryEntriesProvider.overrideWith(
          (ref) async => const <ModelRegistryEntry>[],
        ),
        llmRuntimeStatesProvider.overrideWith(
          (ref) async => const <String, LlmRuntimeState>{},
        ),
      ],
    );
    addTearDown(container.dispose);

    final readiness = await container.read(localLlmReadinessProvider.future);
    expect(readiness.ready, isFalse);
    expect(readiness.activeModel, isNull);
    expect(readiness.reason, '尚未选择本地 LLM 模型。');
  });

  test('llmRuntimeStatesProvider surfaces degraded runtime state', () async {
    final runtime = _FakeModelRuntimeCoordinator(
      state: const ModelRuntimeState(
        ready: false,
        reason: 'session failed',
        status: ModelRuntimeStatus.degraded,
      ),
    );
    final container = ProviderContainer(
      overrides: [
        sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
        modelRegistryEntriesProvider.overrideWith(
          (ref) async => const [_llmModel],
        ),
        modelRuntimeCoordinatorProvider.overrideWithValue(runtime),
      ],
    );
    addTearDown(container.dispose);

    final states = await container.read(llmRuntimeStatesProvider.future);
    expect(states['llm-1']?.ready, isFalse);
    expect(states['llm-1']?.status, LlmRuntimeStatus.degraded);
    expect(states['llm-1']?.reason, 'session failed');
  });

  test('activeLocalLlmModelProvider keeps degraded selected llm', () async {
    final store = _MemoryLocalLlmSelectionStore(modelId: 'llm-1');
    final container = ProviderContainer(
      overrides: [
        sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
        localLlmSelectionStoreProvider.overrideWithValue(store),
        modelRegistryEntriesProvider.overrideWith(
          (ref) async => const [_llmModel],
        ),
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
    final readiness = await container.read(localLlmReadinessProvider.future);

    expect(model?.id, 'llm-1');
    expect(store.modelId, 'llm-1');
    expect(readiness.ready, isFalse);
    expect(readiness.activeModel?.id, 'llm-1');
    expect(readiness.reason, 'probe failed');
  });

  test('selected llm remains when runtime inspection is ready', () async {
    final store = _MemoryLocalLlmSelectionStore(modelId: 'llm-1');
    final runtime = _FakeModelRuntimeCoordinator(
      state: const ModelRuntimeState(
        ready: true,
        reason: 'runtime loaded',
        status: ModelRuntimeStatus.ready,
      ),
    );
    final container = ProviderContainer(
      overrides: [
        sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
        localLlmSelectionStoreProvider.overrideWithValue(store),
        modelRegistryEntriesProvider.overrideWith(
          (ref) async => const [_llmModel],
        ),
        modelRuntimeCoordinatorProvider.overrideWithValue(runtime),
      ],
    );
    addTearDown(container.dispose);

    final model = await container.read(activeLocalLlmModelProvider.future);

    expect(model?.id, 'llm-1');
    expect(store.modelId, 'llm-1');
    expect(runtime.inspectCalls, 1);
  });
}

class _MemoryLocalLlmSelectionStore implements LocalLlmSelectionStore {
  _MemoryLocalLlmSelectionStore({this.modelId, this.onSave});

  String? modelId;
  final void Function(String? value)? onSave;

  @override
  Future<String?> loadActiveModelId() async => modelId;

  @override
  Future<void> saveActiveModelId(String? modelId) async {
    onSave?.call(modelId);
    this.modelId = modelId;
  }
}

class _FakeModelRuntimeCoordinator implements ModelRuntimeCoordinator {
  _FakeModelRuntimeCoordinator({
    this.state = const ModelRuntimeState(
      ready: true,
      reason: 'ready',
      status: ModelRuntimeStatus.ready,
    ),
    this.onRelease,
  });

  final ModelRuntimeState state;
  final void Function(String modelId, String? modelType)? onRelease;
  int inspectCalls = 0;

  @override
  Future<ModelRuntimeState> inspectInstalledModel(
    ModelRegistryEntry entry,
  ) async {
    inspectCalls += 1;
    return ModelRuntimeState(
      ready: state.ready,
      reason: state.reason,
      status: state.status,
      modelPath: entry.localPath,
      checkedAt: state.checkedAt,
    );
  }

  @override
  Future<void> releaseForMutation(
    String modelId, {
    required String? modelType,
  }) async {
    onRelease?.call(modelId, modelType);
  }

  @override
  Future<ModelRuntimeState> validateCandidate({
    required ModelCatalogEntry entry,
    required String modelPath,
    required String verifiedChecksum,
    String? multimodalProjectorPath,
  }) async {
    return state;
  }
}
