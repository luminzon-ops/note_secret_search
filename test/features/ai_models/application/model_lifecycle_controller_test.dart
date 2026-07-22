import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/ai_models/application/model_lifecycle_controller.dart';
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
    );
    final artifactStore = _RecordingArtifactStore(
      fail: false,
      onDelete: () => events.add('delete'),
    );
    final controller = ModelLifecycleController(
      lifecycleStore: lifecycleStore,
      artifactStore: artifactStore,
      releaseEmbeddingModel: (modelId) async {
        events.add('release:$modelId');
      },
    );

    await controller.deleteInstalledModel('model-1');

    expect(events, <String>['release:model-1', 'delete']);
  });
}

class _RecordingLifecycleStore implements ModelLifecycleStore {
  _RecordingLifecycleStore(this.manifest);

  ModelRegistryEntry? manifest;
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
