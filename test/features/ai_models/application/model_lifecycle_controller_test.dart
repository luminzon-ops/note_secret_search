import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/ai_models/application/model_lifecycle_controller.dart';
import 'package:note_secret_search/features/ai_models/application/model_session_releaser.dart';
import 'package:note_secret_search/features/ai_models/domain/model_artifact_path.dart';
import 'package:note_secret_search/features/ai_models/domain/model_artifact_store.dart';
import 'package:note_secret_search/features/ai_models/domain/model_download_task.dart';
import 'package:note_secret_search/features/ai_models/domain/model_lifecycle_store.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';

void main() {
  test('keeps database state until artifact cleanup succeeds', () async {
    final lifecycleStore = _RecordingLifecycleStore(_registryEntry());
    final artifactStore = _RecordingArtifactStore(fail: true);
    final controller = ModelLifecycleController(
      lifecycleStore: lifecycleStore,
      artifactStore: artifactStore,
    );

    await expectLater(
      controller.deleteInstalledModel('model-1'),
      throwsStateError,
    );

    expect(artifactStore.deleteCalls, 1);
    expect(artifactStore.primaryPath, '/support/models/model-1/model.onnx');
    expect(artifactStore.artifacts, hasLength(2));
    expect(lifecycleStore.purgeCalls, 0);
    expect(lifecycleStore.manifest, isNotNull);

    artifactStore.fail = false;
    await controller.deleteInstalledModel('model-1');

    expect(artifactStore.deleteCalls, 2);
    expect(lifecycleStore.purgeCalls, 1);
    expect(lifecycleStore.manifest, isNull);
  });

  test(
    'cleans owned files and database state when registry is missing',
    () async {
      final lifecycleStore = _RecordingLifecycleStore(null);
      final artifactStore = _RecordingArtifactStore(fail: false);
      final controller = ModelLifecycleController(
        lifecycleStore: lifecycleStore,
        artifactStore: artifactStore,
      );

      await controller.deleteInstalledModel('model-1');

      expect(artifactStore.deleteCalls, 1);
      expect(artifactStore.primaryPath, isNull);
      expect(artifactStore.artifacts, isEmpty);
      expect(lifecycleStore.purgeCalls, 1);
    },
  );

  test('releases embedding runtime before deleting model artifacts', () async {
    final events = <String>[];
    final lifecycleStore = _RecordingLifecycleStore(
      _registryEntry().copyWith(type: 'embedding'),
      onPurge: () => events.add('purge'),
    );
    final artifactStore = _RecordingArtifactStore(
      fail: false,
      onDelete: () => events.add('delete'),
    );
    final controller = ModelLifecycleController(
      lifecycleStore: lifecycleStore,
      artifactStore: artifactStore,
      invalidateEmbeddingWrites: () => events.add('invalidate'),
      releaseEmbeddingModel: (modelId) async {
        events.add('release:$modelId');
      },
    );

    await controller.deleteInstalledModel('model-1');

    expect(events, <String>[
      'invalidate',
      'release:model-1',
      'delete',
      'purge',
    ]);
  });

  test(
    'keeps artifacts and database state when embedding release fails',
    () async {
      final events = <String>[];
      final lifecycleStore = _RecordingLifecycleStore(
        _registryEntry().copyWith(type: 'embedding'),
        onPurge: () => events.add('purge'),
      );
      final artifactStore = _RecordingArtifactStore(
        fail: false,
        onDelete: () => events.add('delete'),
      );
      final controller = ModelLifecycleController(
        lifecycleStore: lifecycleStore,
        artifactStore: artifactStore,
        invalidateEmbeddingWrites: () => events.add('invalidate'),
        releaseEmbeddingModel: (modelId) async {
          events.add('release:$modelId');
          throw StateError('release_failed');
        },
      );

      await expectLater(
        controller.deleteInstalledModel('model-1'),
        throwsStateError,
      );

      expect(events, <String>['invalidate', 'release:model-1']);
      expect(artifactStore.deleteCalls, 0);
      expect(lifecycleStore.purgeCalls, 0);
      expect(lifecycleStore.manifest, isNotNull);
    },
  );

  test(
    'releases embedding and llm sessions before deleting artifacts',
    () async {
      final events = <String>[];
      final lifecycleStore = _RecordingLifecycleStore(
        _registryEntry().copyWith(type: 'llm'),
        onPurge: () => events.add('purge'),
      );
      final artifactStore = _RecordingArtifactStore(
        fail: false,
        onDelete: () => events.add('delete'),
      );
      final controller = ModelLifecycleController(
        lifecycleStore: lifecycleStore,
        artifactStore: artifactStore,
        sessionReleaser: ModelSessionReleaser(
          stopWrites: () => events.add('fence'),
          releaseEmbedding: (modelId) async {
            events.add('embedding:$modelId');
          },
          releaseLlm: (modelId) async {
            events.add('llm:$modelId');
          },
        ),
      );

      await controller.deleteInstalledModel('model-1');

      expect(events, <String>[
        'fence',
        'embedding:model-1',
        'llm:model-1',
        'delete',
        'purge',
      ]);
    },
  );

  test('keeps old artifacts when any native session release fails', () async {
    final events = <String>[];
    final lifecycleStore = _RecordingLifecycleStore(
      _registryEntry().copyWith(type: 'llm'),
      onPurge: () => events.add('purge'),
    );
    final artifactStore = _RecordingArtifactStore(
      fail: false,
      onDelete: () => events.add('delete'),
    );
    final controller = ModelLifecycleController(
      lifecycleStore: lifecycleStore,
      artifactStore: artifactStore,
      sessionReleaser: ModelSessionReleaser(
        stopWrites: () => events.add('fence'),
        releaseEmbedding: (modelId) async {
          events.add('embedding:$modelId');
        },
        releaseLlm: (modelId) async {
          events.add('llm:$modelId');
          throw StateError('llm_release_failed');
        },
      ),
    );

    await expectLater(
      controller.deleteInstalledModel('model-1'),
      throwsStateError,
    );

    expect(events, <String>['fence', 'embedding:model-1', 'llm:model-1']);
    expect(artifactStore.deleteCalls, 0);
    expect(lifecycleStore.purgeCalls, 0);
    expect(lifecycleStore.manifest, isNotNull);
  });
}

class _RecordingLifecycleStore implements ModelLifecycleStore {
  _RecordingLifecycleStore(this.manifest, {this.onPurge});

  ModelRegistryEntry? manifest;
  final void Function()? onPurge;
  int purgeCalls = 0;

  @override
  Future<void> commitInstallation({
    required ModelRegistryEntry registryEntry,
    required List<ModelDownloadTask> completedTasks,
  }) async {}

  @override
  Future<ModelRegistryEntry?> getDeletionManifest(String modelId) async {
    return manifest?.id == modelId ? manifest : null;
  }

  @override
  Future<void> purgeModelData(String modelId) async {
    onPurge?.call();
    purgeCalls += 1;
    if (manifest?.id == modelId) {
      manifest = null;
    }
  }
}

class _RecordingArtifactStore implements ModelArtifactStore {
  _RecordingArtifactStore({required this.fail, this.onDelete});

  bool fail;
  final void Function()? onDelete;
  int deleteCalls = 0;
  String? primaryPath;
  List<ModelArtifactPath>? artifacts;

  @override
  Future<void> deleteModelArtifacts({
    required String modelId,
    required String? primaryPath,
    required List<ModelArtifactPath> artifacts,
  }) async {
    onDelete?.call();
    deleteCalls += 1;
    this.primaryPath = primaryPath;
    this.artifacts = artifacts;
    if (fail) {
      throw StateError('injected_artifact_failure');
    }
  }
}

ModelRegistryEntry _registryEntry() {
  return const ModelRegistryEntry(
    id: 'model-1',
    type: 'multimodal_llm',
    provider: 'builtin_catalog',
    name: 'Model',
    version: null,
    sizeBytes: 30,
    quantization: null,
    minRamMb: 512,
    recommendedTier: 'mvp',
    localPath: '/support/models/model-1/model.onnx',
    checksum: 'sha256:model',
    enabled: true,
    installedAt: null,
    filePresent: true,
    integrityStatus: ModelIntegrityStatus.valid,
    artifacts: <ModelArtifactPath>[
      ModelArtifactPath(
        role: 'model',
        sourceId: 'source-model',
        localPath: '/support/models/model-1/model.onnx',
      ),
      ModelArtifactPath(
        role: 'mmproj',
        sourceId: 'source-mmproj',
        localPath: '/support/models/model-1/mmproj.gguf',
      ),
    ],
  );
}
