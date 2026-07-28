import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/security/core_security_providers.dart';
import 'package:note_secret_search/features/ai_models/application/model_selection_providers.dart';
import 'package:note_secret_search/features/ai_models/domain/active_model_selection.dart';
import 'package:note_secret_search/features/ai_models/domain/active_model_selection_store.dart';
import 'package:note_secret_search/features/ai_models/domain/model_artifact_path.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/search/application/search_index_settings_providers.dart';
import 'package:note_secret_search/features/search/application/search_index_write_fence.dart';
import 'package:note_secret_search/features/search/domain/embedding_engine.dart';
import 'package:note_secret_search/features/search/domain/search_scope.dart';

const _catalogDigest =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _artifactDigest =
    'sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

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
  checksum: _artifactDigest,
  enabled: true,
  installedAt: null,
  filePresent: true,
  integrityStatus: ModelIntegrityStatus.valid,
  releaseId: 'release-1',
  catalogVersion: 1,
  catalogDigest: _catalogDigest,
  generation: 1,
  revisionRoot: 'revisions/1',
  artifacts: <ModelArtifactPath>[
    ModelArtifactPath(
      artifactId: 'model',
      releaseId: 'release-1',
      role: 'model',
      sourceId: 'test-source',
      localPath: '/data/models/minilm.onnx',
      relativePath: 'runtime/model.onnx',
      expectedChecksum: _artifactDigest,
      verifiedChecksum: _artifactDigest,
      expectedSizeBytes: 10485760,
      verifiedSizeBytes: 10485760,
      state: 'installed',
      verifiedAt: 1,
    ),
  ],
);

void main() {
  test('readiness reports an unverified runtime as blocked', () async {
    final container = ProviderContainer(
      overrides: <Override>[
        sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
        activeModelSelectionProvider.overrideWith(
          (ref) async =>
              const ActiveModelSelection(activeEmbeddingModelId: 'embed-1'),
        ),
        modelSelectionRegistryEntriesProvider.overrideWith(
          (ref) async => const <ModelRegistryEntry>[_embeddingModel],
        ),
        modelSelectionEmbeddingRuntimeStatesProvider.overrideWith(
          (ref) async => const <String, EmbeddingEngineState>{
            'embed-1': EmbeddingEngineState(
              ready: false,
              reason: 'waiting verification',
              status: EmbeddingRuntimeStatus.installedUnverified,
            ),
          },
        ),
        searchScopeConfigProvider.overrideWith(
          (ref) async => const SearchScopeConfig.defaults(),
        ),
      ],
    );
    addTearDown(container.dispose);

    final readiness = await container.read(
      semanticSearchReadinessProvider.future,
    );

    expect(readiness.ready, isFalse);
    expect(readiness.runtimeStatus, EmbeddingRuntimeStatus.installedUnverified);
    expect(readiness.reason, '已选择模型 MiniLM Embedding，但运行时尚未完成校验，暂不能用于语义检索。');
  });

  test(
    'active model projection preserves a selected degraded runtime',
    () async {
      final container = ProviderContainer(
        overrides: <Override>[
          sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
          activeModelSelectionProvider.overrideWith(
            (ref) async =>
                const ActiveModelSelection(activeEmbeddingModelId: 'embed-1'),
          ),
          modelSelectionRegistryEntriesProvider.overrideWith(
            (ref) async => const <ModelRegistryEntry>[_embeddingModel],
          ),
          modelSelectionEmbeddingRuntimeStatesProvider.overrideWith(
            (ref) async => const <String, EmbeddingEngineState>{
              'embed-1': EmbeddingEngineState(
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
    },
  );

  test(
    'missing registry entry fences and releases before clearing selection',
    () async {
      final events = <String>[];
      final store = _RecordingSelectionStore(
        activeModelId: 'embed-1',
        events: events,
      );
      final writeFence = SearchIndexWriteFence();
      final effects = _RecordingSelectionEffects(
        writeFence: writeFence,
        events: events,
      );
      final container = _selectionContainer(
        store: store,
        effects: effects,
        entries: const <ModelRegistryEntry>[],
      );
      addTearDown(container.dispose);

      final selection = await container.read(
        activeModelSelectionProvider.future,
      );

      expect(selection.activeEmbeddingModelId, isNull);
      expect(writeFence.revision, 1);
      expect(events, <String>['fence', 'release:embed-1', 'persist:null']);
    },
  );

  test('failed self-heal release preserves the persisted selection', () async {
    final events = <String>[];
    final store = _RecordingSelectionStore(
      activeModelId: 'embed-1',
      events: events,
    );
    final writeFence = SearchIndexWriteFence();
    final effects = _RecordingSelectionEffects(
      writeFence: writeFence,
      events: events,
      failRelease: true,
    );
    final container = _selectionContainer(
      store: store,
      effects: effects,
      entries: const <ModelRegistryEntry>[],
    );
    addTearDown(container.dispose);

    await expectLater(
      container.read(activeModelSelectionProvider.future),
      throwsStateError,
    );

    expect(store.activeModelId, 'embed-1');
    expect(writeFence.revision, 1);
    expect(events, <String>['fence', 'release:embed-1']);
  });

  test(
    'controller fences and releases the old model before persistence',
    () async {
      final events = <String>[];
      final store = _RecordingSelectionStore(
        activeModelId: 'embed-old',
        events: events,
      );
      final writeFence = SearchIndexWriteFence();
      final effects = _RecordingSelectionEffects(
        writeFence: writeFence,
        events: events,
      );
      final container = ProviderContainer(
        overrides: <Override>[
          activeModelSelectionStoreProvider.overrideWith((ref) async => store),
          activeEmbeddingSelectionEffectsProvider.overrideWithValue(effects),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(activeModelSelectionControllerProvider)
          .setActiveEmbeddingModel('embed-new');

      expect(store.activeModelId, 'embed-new');
      expect(writeFence.revision, 1);
      expect(events, <String>[
        'fence',
        'release:embed-old',
        'persist:embed-new',
      ]);
    },
  );
}

ProviderContainer _selectionContainer({
  required _RecordingSelectionStore store,
  required ActiveEmbeddingSelectionEffects effects,
  required List<ModelRegistryEntry> entries,
}) {
  return ProviderContainer(
    overrides: <Override>[
      sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
      activeModelSelectionStoreProvider.overrideWith((ref) async => store),
      activeEmbeddingSelectionEffectsProvider.overrideWithValue(effects),
      modelSelectionRegistryEntriesProvider.overrideWith(
        (ref) async => entries,
      ),
      modelSelectionEmbeddingRuntimeStatesProvider.overrideWith(
        (ref) async => const <String, EmbeddingEngineState>{},
      ),
    ],
  );
}

class _RecordingSelectionStore implements ActiveModelSelectionStore {
  _RecordingSelectionStore({required this.activeModelId, required this.events});

  String? activeModelId;
  final List<String> events;

  @override
  Future<String?> loadActiveEmbeddingModelId() async => activeModelId;

  @override
  Future<void> saveActiveEmbeddingModelId(String? modelId) async {
    events.add('persist:${modelId ?? 'null'}');
    activeModelId = modelId;
  }
}

class _RecordingSelectionEffects implements ActiveEmbeddingSelectionEffects {
  const _RecordingSelectionEffects({
    required SearchIndexWriteFence writeFence,
    required List<String> events,
    this.failRelease = false,
  }) : _writeFence = writeFence,
       _events = events;

  final SearchIndexWriteFence _writeFence;
  final List<String> _events;
  final bool failRelease;

  @override
  Future<void> prepareForPersistence({
    required String? previousModelId,
    required String? nextModelId,
  }) async {
    _writeFence.invalidate();
    _events.add('fence');
    if (previousModelId == null ||
        previousModelId.isEmpty ||
        previousModelId == nextModelId) {
      return;
    }
    _events.add('release:$previousModelId');
    if (failRelease) {
      throw StateError('release_failed');
    }
  }
}
