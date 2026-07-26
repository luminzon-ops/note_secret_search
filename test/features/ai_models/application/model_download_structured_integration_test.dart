import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/logging/app_logger.dart';
import 'package:note_secret_search/core/storage/database/model_state_records.dart';
import 'package:note_secret_search/features/ai_models/application/model_catalog_providers.dart';
import 'package:note_secret_search/features/ai_models/application/model_download_providers.dart';
import 'package:note_secret_search/features/ai_models/domain/model_artifact_path.dart';
import 'package:note_secret_search/features/ai_models/domain/model_catalog_entry.dart';
import 'package:note_secret_search/features/ai_models/domain/model_download_repository.dart';
import 'package:note_secret_search/features/ai_models/domain/model_download_task.dart';
import 'package:note_secret_search/features/ai_models/domain/model_lifecycle_store.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_repository.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/io_model_revision_store.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/model_download_service.dart';
import 'package:note_secret_search/features/search/application/embedding_runtime_providers.dart';
import 'package:note_secret_search/features/search/infrastructure/embedding_runtime_bridge.dart';

part 'model_download_structured_failure_recovery_cases.dart';
part 'model_download_structured_repair_cases.dart';
part 'model_download_structured_resume_failover_cases.dart';
part 'model_download_structured_test_doubles.dart';

void main() {
  test(
    'stages every signed artifact and commits one trusted revision',
    () async {
      final downloads = _MemoryDownloadRepository();
      final registry = _MemoryRegistryRepository();
      final lifecycle = _RecordingLifecycleStore(
        downloads: downloads,
        registry: registry,
      );
      final service = _StructuredDownloadService();
      final revisions = _RecordingRevisionStore();
      final bridge = _ReadyEmbeddingBridge();
      final container = _container(
        downloads: downloads,
        registry: registry,
        lifecycle: lifecycle,
        service: service,
        revisions: revisions,
        bridge: bridge,
      );
      addTearDown(container.dispose);

      await container
          .read(modelDownloadControllerProvider)
          .startDownload(entry: _entry, source: _entry.sources.single);

      expect(service.stagedArtifactIds, <String>['model', 'sidecar']);
      expect(revisions.installCalls, 1);
      expect(
        revisions.artifacts.map((artifact) => artifact.artifactId),
        <String>['model', 'sidecar'],
      );
      expect(lifecycle.commitCalls, 1);
      expect(registry.entry?.releaseId, _entry.releaseId);
      expect(registry.entry?.catalogVersion, _entry.catalogVersion);
      expect(registry.entry?.catalogDigest, _entry.catalogDigest);
      expect(registry.entry?.generation, 1);
      expect(registry.entry?.revisionRoot, 'revisions/1');
      expect(registry.entry?.artifacts, hasLength(2));
      expect(registry.entry?.isInstalled, isTrue);
      expect(bridge.ensureCalls, 1);
      expect(lifecycle.journals.map((journal) => journal.phase), <String>[
        'queued',
        'staging',
        'staged',
        'runtime_validating',
        'releasing_sessions',
        'installing',
        'committing',
        'completed',
      ]);
      expect(lifecycle.journals.last.completedAt, isNotNull);
    },
  );

  _registerStructuredFailureRecoveryTests();
  _registerStructuredRepairTests();
  _registerStructuredResumeFailoverTests();
}

ProviderContainer _container({
  required _MemoryDownloadRepository downloads,
  required _MemoryRegistryRepository registry,
  required _RecordingLifecycleStore lifecycle,
  required _StructuredDownloadService service,
  required _RecordingRevisionStore revisions,
  required _ReadyEmbeddingBridge bridge,
}) {
  return ProviderContainer(
    overrides: <Override>[
      modelDownloadRepositoryProvider.overrideWithValue(downloads),
      modelRegistryRepositoryProvider.overrideWithValue(registry),
      modelLifecycleStoreProvider.overrideWithValue(lifecycle),
      modelDownloadServiceProvider.overrideWithValue(service),
      modelRevisionStoreProvider.overrideWithValue(revisions),
      embeddingRuntimeBridgeProvider.overrideWithValue(bridge),
    ],
  );
}

const _entry = ModelCatalogEntry(
  id: 'structured-model',
  type: 'embedding',
  tier: 'local',
  displayName: 'Structured Model',
  description: 'fixture',
  sizeBytes: 12,
  minRamMb: 512,
  recommendedTier: 'local',
  releaseId: 'release-1',
  catalogVersion: 7,
  catalogDigest:
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  sources: <ModelSourceEntry>[
    ModelSourceEntry(
      id: 'model-source',
      label: 'model',
      url: 'https://example.com/model.onnx',
      checksum: _modelDigest,
      artifactId: 'model',
    ),
  ],
  artifacts: <ModelArtifactSpec>[
    ModelArtifactSpec(
      id: 'model',
      releaseId: 'release-1',
      role: 'model',
      required: true,
      relativePath: 'runtime/model.onnx',
      sizeBytes: 10,
      checksum: _modelDigest,
      origin: ModelArtifactOrigin.download,
      sources: <ModelSourceEntry>[
        ModelSourceEntry(
          id: 'model-source',
          label: 'model',
          url: 'https://example.com/model.onnx',
          checksum: _modelDigest,
          artifactId: 'model',
        ),
      ],
    ),
    ModelArtifactSpec(
      id: 'sidecar',
      releaseId: 'release-1',
      role: 'sidecar',
      required: true,
      relativePath: 'runtime/sidecar.json',
      sizeBytes: 2,
      checksum: _sidecarDigest,
      origin: ModelArtifactOrigin.download,
      sources: <ModelSourceEntry>[
        ModelSourceEntry(
          id: 'sidecar-source',
          label: 'sidecar',
          url: 'https://example.com/sidecar.json',
          checksum: _sidecarDigest,
          artifactId: 'sidecar',
        ),
      ],
    ),
  ],
);

const _trustedOldEntry = ModelRegistryEntry(
  id: 'structured-model',
  type: 'embedding',
  provider: 'builtin_catalog',
  name: 'Structured Model',
  version: 'release-0',
  sizeBytes: 10,
  quantization: null,
  minRamMb: 512,
  recommendedTier: 'local',
  localPath: '/support/models/structured-model/revisions/1/runtime/model.onnx',
  checksum: _modelDigest,
  enabled: true,
  installedAt: null,
  filePresent: true,
  integrityStatus: ModelIntegrityStatus.valid,
  releaseId: 'release-0',
  catalogVersion: 6,
  catalogDigest:
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  generation: 1,
  revisionRoot: 'revisions/1',
  artifacts: <ModelArtifactPath>[
    ModelArtifactPath(
      artifactId: 'model',
      sourceId: 'model-source',
      releaseId: 'release-0',
      role: 'model',
      required: true,
      relativePath: 'runtime/model.onnx',
      localPath:
          '/support/models/structured-model/revisions/1/runtime/model.onnx',
      expectedChecksum: _modelDigest,
      expectedSizeBytes: 10,
      verifiedChecksum: _modelDigest,
      verifiedSizeBytes: 10,
      state: 'installed',
      verifiedAt: 1,
    ),
  ],
);

const _modelDigest =
    'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _sidecarDigest =
    'sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

class _MemoryDownloadRepository implements ModelDownloadRepository {
  final List<ModelDownloadTask> tasks = <ModelDownloadTask>[];

  @override
  Future<ModelDownloadTask?> findLatestTaskByModel(String modelId) async {
    return tasks
        .where((task) => task.modelId == modelId)
        .fold<ModelDownloadTask?>(null, (latest, task) {
          if (latest == null || task.updatedAt.isAfter(latest.updatedAt)) {
            return task;
          }
          return latest;
        });
  }

  @override
  Future<ModelDownloadTask?> findLatestTaskByModelAndSource(
    String modelId,
    String sourceId,
  ) async {
    final matching = tasks
        .where((task) => task.modelId == modelId && task.sourceId == sourceId)
        .toList();
    if (matching.isEmpty) return null;
    matching.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return matching.first;
  }

  @override
  Future<List<ModelDownloadTask>> listTasks() async =>
      List<ModelDownloadTask>.unmodifiable(tasks);

  @override
  Future<void> saveTask(ModelDownloadTask task) async {
    tasks.removeWhere((candidate) => candidate.id == task.id);
    tasks.add(task);
  }
}

class _MemoryRegistryRepository implements ModelRegistryRepository {
  ModelRegistryEntry? entry;

  @override
  Future<void> deleteById(String id) async {
    if (entry?.id == id) entry = null;
  }

  @override
  Future<ModelRegistryEntry?> getById(String id) async =>
      entry?.id == id ? entry : null;

  @override
  Future<List<ModelRegistryEntry>> listInstalledModels() async => entry == null
      ? const <ModelRegistryEntry>[]
      : <ModelRegistryEntry>[entry!];

  @override
  Future<void> save(ModelRegistryEntry value) async => entry = value;
}

class _RecordingLifecycleStore
    implements ModelLifecycleStore, ModelInstallJournalStore {
  _RecordingLifecycleStore({
    required this.downloads,
    required this.registry,
    this.commitError,
    List<ModelInstallJournalRecord> initialJournals =
        const <ModelInstallJournalRecord>[],
  }) : journals = <ModelInstallJournalRecord>[...initialJournals];

  final _MemoryDownloadRepository downloads;
  final _MemoryRegistryRepository registry;
  final Object? commitError;
  final List<ModelInstallJournalRecord> journals;
  int commitCalls = 0;

  ModelInstallJournalRecord? latestJournal(String operationId) {
    return journals
        .where((journal) => journal.operationId == operationId)
        .lastOrNull;
  }

  @override
  Future<void> commitInstallation({
    required ModelRegistryEntry registryEntry,
    required List<ModelDownloadTask> completedTasks,
  }) async {
    commitCalls += 1;
    final error = commitError;
    if (error != null) {
      throw error;
    }
    await registry.save(registryEntry);
    for (final task in completedTasks) {
      await downloads.saveTask(task);
    }
  }

  @override
  Future<ModelRegistryEntry?> getDeletionManifest(String modelId) =>
      registry.getById(modelId);

  @override
  Future<void> purgeModelData(String modelId) => registry.deleteById(modelId);

  @override
  Future<void> saveInstallJournal(ModelInstallJournalRecord journal) async {
    journals.add(journal);
  }

  @override
  Future<ModelInstallJournalRecord?> loadInstallJournal(
    String operationId,
  ) async {
    return latestJournal(operationId);
  }

  @override
  Future<List<ModelInstallJournalRecord>> listOpenInstallJournals() async {
    final latest = <String, ModelInstallJournalRecord>{};
    for (final journal in journals) {
      latest[journal.operationId] = journal;
    }
    return latest.values
        .where((journal) => journal.completedAt == null)
        .toList(growable: false);
  }
}

class _StructuredDownloadService extends ModelDownloadService {
  _StructuredDownloadService({this.failingArtifactId})
    : super(dio: Dio(), logger: const AppLogger());

  final String? failingArtifactId;
  final List<String> stagedArtifactIds = <String>[];

  @override
  Future<ModelDownloadResult> stageArtifact({
    required String taskId,
    required String modelId,
    required String operationId,
    required String artifactId,
    required String sourceUrl,
    required String expectedChecksum,
    required int expectedSizeBytes,
    int resumeFromBytes = 0,
    required FutureOr<void> Function(ModelDownloadProgress progress) onProgress,
  }) async {
    stagedArtifactIds.add(artifactId);
    if (artifactId == failingArtifactId) {
      throw StateError('artifact_failed');
    }
    await onProgress(
      ModelDownloadProgress(
        receivedBytes: expectedSizeBytes,
        totalBytes: expectedSizeBytes,
        averageSpeedBytesPerSecond: expectedSizeBytes.toDouble(),
      ),
    );
    return ModelDownloadResult(
      localPath:
          '/support/models/$modelId/.staging/$operationId/$artifactId.part',
      totalBytes: expectedSizeBytes,
      verifiedChecksum: expectedChecksum,
    );
  }

  @override
  Future<ModelDownloadStagingTarget> resolveArtifactStagingTarget({
    required String modelId,
    required String operationId,
    required String artifactId,
  }) async {
    final path =
        '/support/models/$modelId/.staging/$operationId/$artifactId.part';
    return ModelDownloadStagingTarget(
      localPath: path,
      stagingPath: path,
      metadataPath: '$path.json',
    );
  }
}

class _RecordingRevisionStore implements ModelRevisionStore {
  int installCalls = 0;
  List<StagedModelArtifact> artifacts = const <StagedModelArtifact>[];
  final List<String> discardedRevisionRoots = <String>[];
  final List<String> reusedArtifactIds = <String>[];

  @override
  Future<InstalledModelRevision> installVerifiedRevision({
    required String modelId,
    required String operationId,
    required int generation,
    required List<StagedModelArtifact> artifacts,
  }) async {
    installCalls += 1;
    this.artifacts = List<StagedModelArtifact>.from(artifacts);
    return InstalledModelRevision(
      revisionRoot: '/support/models/$modelId/revisions/$generation',
      pathsByArtifactId: <String, String>{
        for (final artifact in artifacts)
          artifact.artifactId:
              '/support/models/$modelId/revisions/$generation/${artifact.relativePath}',
      },
    );
  }

  @override
  Future<void> recoverInterruptedInstalls({required String modelId}) async {}

  @override
  Future<void> discardInstalledRevision({
    required String modelId,
    required String revisionRoot,
  }) async {
    discardedRevisionRoots.add(revisionRoot);
  }

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
    reusedArtifactIds.add(artifactId);
    return StagedModelArtifact(
      artifactId: artifactId,
      relativePath: relativePath,
      stagingPath:
          '/support/models/$modelId/.staging/$operationId/$artifactId.part',
      expectedSizeBytes: expectedSizeBytes,
      expectedChecksum: expectedChecksum,
    );
  }
}
