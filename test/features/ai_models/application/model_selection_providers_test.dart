import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/security/core_security_providers.dart';
import 'package:note_secret_search/features/ai_chat/application/llm_runtime_providers.dart';
import 'package:note_secret_search/features/ai_chat/domain/llm_runtime_status.dart';
import 'package:note_secret_search/features/ai_models/application/model_download_providers.dart';
import 'package:note_secret_search/features/ai_models/domain/model_artifact_path.dart';
import 'package:note_secret_search/features/ai_models/domain/model_catalog_entry.dart';
import 'package:note_secret_search/features/ai_models/domain/local_llm_selection_store.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';

const _testCatalogDigest =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _testArtifactDigest =
    'sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

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
  checksum: _testArtifactDigest,
  enabled: true,
  installedAt: null,
  filePresent: true,
  integrityStatus: ModelIntegrityStatus.valid,
  releaseId: 'release-1',
  catalogVersion: 1,
  catalogDigest: _testCatalogDigest,
  generation: 1,
  revisionRoot: 'revisions/1',
  artifacts: <ModelArtifactPath>[
    ModelArtifactPath(
      artifactId: 'model',
      releaseId: 'release-1',
      role: 'model',
      sourceId: 'test-source',
      localPath: '/data/models/phi.gguf',
      relativePath: 'runtime/model.gguf',
      expectedChecksum: _testArtifactDigest,
      verifiedChecksum: _testArtifactDigest,
      expectedSizeBytes: 104857600,
      verifiedSizeBytes: 104857600,
      state: 'installed',
      verifiedAt: 1,
    ),
  ],
);

void main() {
  test(
    'activeLocalLlmModelProvider preserves selection when runtime is degraded (recoverable)',
    () async {
      final selectionStore = _InMemoryLocalLlmSelectionStore('llm-1');
      final container = ProviderContainer(
        overrides: [
          sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
          localLlmSelectionStoreProvider.overrideWithValue(selectionStore),
          modelRegistryEntriesProvider.overrideWith(
            (ref) async => const [_llmModel],
          ),
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

      // Degraded is recoverable, so the selected model must be preserved.
      expect(model?.id, 'llm-1');
      expect(selectionStore.activeModelId, 'llm-1');
    },
  );

  test(
    'activeLocalLlmModelProvider preserves selection when runtime is installedUnverified (recoverable)',
    () async {
      final selectionStore = _InMemoryLocalLlmSelectionStore('llm-1');
      final container = ProviderContainer(
        overrides: [
          sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
          localLlmSelectionStoreProvider.overrideWithValue(selectionStore),
          modelRegistryEntriesProvider.overrideWith(
            (ref) async => const [_llmModel],
          ),
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

      // installedUnverified is recoverable, so selection remains intact.
      expect(model?.id, 'llm-1');
      expect(selectionStore.activeModelId, 'llm-1');
    },
  );

  test(
    'activeLocalLlmModelProvider self-heals when runtime probe fails after selection',
    () async {
      final selectionStore = _InMemoryLocalLlmSelectionStore('llm-1');
      final container = ProviderContainer(
        overrides: [
          sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
          localLlmSelectionStoreProvider.overrideWithValue(selectionStore),
          modelRegistryEntriesProvider.overrideWith(
            (ref) async => const [_llmModel],
          ),
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
    },
  );

  test(
    'activeLocalLlmModelProvider self-heals when LLM file is missing (not recoverable)',
    () async {
      final selectionStore = _InMemoryLocalLlmSelectionStore('llm-1');
      final missingLlmModel = _llmModel.copyWith(
        filePresent: false,
        enabled: false,
      );
      final container = ProviderContainer(
        overrides: [
          sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
          localLlmSelectionStoreProvider.overrideWithValue(selectionStore),
          modelRegistryEntriesProvider.overrideWith(
            (ref) async => [missingLlmModel],
          ),
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

      // Missing file is not recoverable, so selection must be cleared.
      expect(model, isNull);
      expect(selectionStore.activeModelId, isNull);
    },
  );

  test(
    'activeLocalLlmModelProvider keeps selection when runtime is ready but registry entry is stale',
    () async {
      final selectionStore = _InMemoryLocalLlmSelectionStore('llm-1');
      final staleLlmModel = _llmModel.copyWith(enabled: false);
      final container = ProviderContainer(
        overrides: [
          sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
          localLlmSelectionStoreProvider.overrideWithValue(selectionStore),
          modelRegistryEntriesProvider.overrideWith(
            (ref) async => [staleLlmModel],
          ),
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

      expect(model?.id, 'llm-1');
      expect(selectionStore.activeModelId, 'llm-1');
    },
  );
}

class _InMemoryLocalLlmSelectionStore implements LocalLlmSelectionStore {
  _InMemoryLocalLlmSelectionStore(this.activeModelId);

  String? activeModelId;

  @override
  Future<String?> loadActiveModelId() async => activeModelId;

  @override
  Future<void> saveActiveModelId(String? modelId) async {
    activeModelId = modelId;
  }
}
