part of 'model_download_structured_integration_test.dart';

void _registerStructuredResumeFailoverTests() {
  test(
    'mirror failover reuses one artifact task and resets partial bytes',
    () async {
      final downloads = _HistoryDownloadRepository();
      final registry = _MemoryRegistryRepository();
      final lifecycle = _RecordingLifecycleStore(
        downloads: downloads,
        registry: registry,
      );
      final service = _ScriptedStructuredDownloadService(
        failingSourceUrl: 'https://mirror-a.example/model.onnx',
      );
      final revisions = _RecordingRevisionStore();
      final container = _container(
        downloads: downloads,
        registry: registry,
        lifecycle: lifecycle,
        service: service,
        revisions: revisions,
        bridge: _ReadyEmbeddingBridge(),
      );
      addTearDown(container.dispose);

      await container
          .read(modelDownloadControllerProvider)
          .startDownload(
            entry: _entryWithMirrors,
            source: _entryWithMirrors.sources.first,
          );

      final modelCalls = service.calls
          .where((call) => call.artifactId == 'model')
          .toList(growable: false);
      expect(modelCalls, hasLength(2));
      expect(modelCalls.map((call) => call.taskId).toSet(), hasLength(1));
      expect(modelCalls.map((call) => call.sourceUrl), <String>[
        'https://mirror-a.example/model.onnx',
        'https://mirror-b.example/model.onnx',
      ]);
      expect(modelCalls.map((call) => call.resumeFromBytes), <int>[0, 0]);
      expect(
        downloads.tasks.where((task) => task.artifactId == 'model'),
        hasLength(1),
      );
      expect(
        downloads.history.any(
          (task) =>
              task.artifactId == 'model' &&
              task.sourceId == 'model-source-a' &&
              task.phase == ModelDownloadPhase.retryableFailed &&
              task.effectiveReceivedBytes == 4,
        ),
        isTrue,
      );
      expect(
        downloads.history.any(
          (task) =>
              task.artifactId == 'model' &&
              task.sourceId == 'model-source-b' &&
              task.phase == ModelDownloadPhase.downloading &&
              task.effectiveReceivedBytes == 0,
        ),
        isTrue,
      );
    },
  );

  test(
    'open staging journal resumes the same operation task and generation',
    () async {
      final downloads = _HistoryDownloadRepository();
      const operationId = 'resume-operation';
      const sourceUrl = 'https://example.com/model.onnx';
      await downloads.saveTask(
        ModelDownloadTask(
          id: 'resume-task',
          modelId: 'structured-model',
          sourceId: 'model-source',
          status: ModelDownloadStatus.paused,
          totalBytes: 10,
          downloadedBytes: 4,
          averageSpeed: null,
          errorMessage: null,
          resumable: true,
          createdAt: DateTime(2026, 7, 24, 10),
          updatedAt: DateTime(2026, 7, 24, 10, 1),
          operationId: operationId,
          attemptGeneration: 2,
          releaseId: 'release-1',
          artifactId: 'model',
          sourceUrl: sourceUrl,
          stagingPath:
              '/support/models/structured-model/.staging/$operationId/model.part',
          expectedChecksum: _modelDigest,
          expectedSizeBytes: 10,
          etag: '"resume-v1"',
          phase: ModelDownloadPhase.paused,
          receivedBytes: 4,
        ),
      );
      const oldEntry = _trustedOldEntry;
      final registry = _MemoryRegistryRepository()..entry = oldEntry;
      final lifecycle = _RecordingLifecycleStore(
        downloads: downloads,
        registry: registry,
        initialJournals: const <ModelInstallJournalRecord>[
          ModelInstallJournalRecord(
            operationId: operationId,
            modelId: 'structured-model',
            releaseId: 'release-1',
            attemptGeneration: 2,
            operationType: 'replace',
            phase: 'staging',
            oldRevision: 'revisions/1',
            newRevision: 'revisions/2',
            stagingRoot: '.staging/$operationId',
            targetRoot: 'revisions/2',
            createdAt: 1,
            updatedAt: 2,
          ),
        ],
      );
      final service = _ScriptedStructuredDownloadService();
      final revisions = _RecordingRevisionStore();
      final container = _container(
        downloads: downloads,
        registry: registry,
        lifecycle: lifecycle,
        service: service,
        revisions: revisions,
        bridge: _ReadyEmbeddingBridge(),
      );
      addTearDown(container.dispose);

      await container
          .read(modelDownloadControllerProvider)
          .startDownload(entry: _entry, source: _entry.sources.single);

      final modelCall = service.calls.singleWhere(
        (call) => call.artifactId == 'model',
      );
      expect(modelCall.operationId, operationId);
      expect(modelCall.taskId, 'resume-task');
      expect(modelCall.resumeFromBytes, 4);
      expect(registry.entry?.generation, 2);
      expect(lifecycle.latestJournal(operationId)?.phase, 'completed');
    },
  );

  test(
    'pause keeps the staging journal open and resumes the same task',
    () async {
      final downloads = _HistoryDownloadRepository();
      const oldEntry = _trustedOldEntry;
      final registry = _MemoryRegistryRepository()..entry = oldEntry;
      final lifecycle = _RecordingLifecycleStore(
        downloads: downloads,
        registry: registry,
      );
      final service = _PausableStructuredDownloadService();
      final revisions = _RecordingRevisionStore();
      final container = _container(
        downloads: downloads,
        registry: registry,
        lifecycle: lifecycle,
        service: service,
        revisions: revisions,
        bridge: _ReadyEmbeddingBridge(),
      );
      addTearDown(container.dispose);
      final controller = container.read(modelDownloadControllerProvider);

      final firstAttempt = controller.startDownload(
        entry: _entry,
        source: _entry.sources.single,
      );
      await service.firstProgress.future;
      final firstCall = service.calls.single;

      await controller.pause('structured-model', sourceId: 'model-source');
      await firstAttempt;

      var task = downloads.tasks.singleWhere(
        (candidate) => candidate.artifactId == 'model',
      );
      expect(task.status, ModelDownloadStatus.paused);
      expect(task.phase, ModelDownloadPhase.paused);
      expect(task.effectiveReceivedBytes, 4);
      expect(lifecycle.latestJournal(firstCall.operationId)?.phase, 'staging');
      expect(
        lifecycle.latestJournal(firstCall.operationId)?.completedAt,
        isNull,
      );
      expect(registry.entry, same(oldEntry));

      await controller.startDownload(
        entry: _entry,
        source: _entry.sources.single,
      );

      final modelCalls = service.calls
          .where((call) => call.artifactId == 'model')
          .toList(growable: false);
      expect(modelCalls, hasLength(2));
      expect(modelCalls.map((call) => call.operationId).toSet(), hasLength(1));
      expect(modelCalls.map((call) => call.taskId).toSet(), hasLength(1));
      expect(modelCalls.map((call) => call.resumeFromBytes), <int>[0, 4]);
      task = downloads.tasks.singleWhere(
        (candidate) => candidate.artifactId == 'model',
      );
      expect(task.phase, ModelDownloadPhase.completed);
      expect(registry.entry?.generation, 2);
      expect(
        lifecycle.latestJournal(firstCall.operationId)?.phase,
        'completed',
      );
    },
  );
}

const _entryWithMirrors = ModelCatalogEntry(
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
      id: 'model-source-a',
      label: 'model a',
      url: 'https://mirror-a.example/model.onnx',
      checksum: _modelDigest,
      artifactId: 'model',
    ),
    ModelSourceEntry(
      id: 'model-source-b',
      label: 'model b',
      url: 'https://mirror-b.example/model.onnx',
      checksum: _modelDigest,
      artifactId: 'model',
      priority: 1,
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
          id: 'model-source-a',
          label: 'model a',
          url: 'https://mirror-a.example/model.onnx',
          checksum: _modelDigest,
          artifactId: 'model',
        ),
        ModelSourceEntry(
          id: 'model-source-b',
          label: 'model b',
          url: 'https://mirror-b.example/model.onnx',
          checksum: _modelDigest,
          artifactId: 'model',
          priority: 1,
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

class _HistoryDownloadRepository extends _MemoryDownloadRepository {
  final List<ModelDownloadTask> history = <ModelDownloadTask>[];

  @override
  Future<void> saveTask(ModelDownloadTask task) async {
    history.add(task);
    await super.saveTask(task);
  }
}

class _StructuredStageCall {
  const _StructuredStageCall({
    required this.taskId,
    required this.operationId,
    required this.artifactId,
    required this.sourceUrl,
    required this.resumeFromBytes,
  });

  final String taskId;
  final String operationId;
  final String artifactId;
  final String sourceUrl;
  final int resumeFromBytes;
}

class _ScriptedStructuredDownloadService extends _StructuredDownloadService {
  _ScriptedStructuredDownloadService({this.failingSourceUrl});

  final String? failingSourceUrl;
  final List<_StructuredStageCall> calls = <_StructuredStageCall>[];

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
    calls.add(
      _StructuredStageCall(
        taskId: taskId,
        operationId: operationId,
        artifactId: artifactId,
        sourceUrl: sourceUrl,
        resumeFromBytes: resumeFromBytes,
      ),
    );
    if (sourceUrl == failingSourceUrl) {
      await onProgress(
        const ModelDownloadProgress(
          receivedBytes: 4,
          totalBytes: 10,
          averageSpeedBytesPerSecond: 4,
        ),
      );
      throw StateError('connection failed');
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
      resumable: true,
      etag: '"fixture-v1"',
    );
  }
}

class _PausableStructuredDownloadService
    extends _ScriptedStructuredDownloadService {
  final Completer<void> firstProgress = Completer<void>();
  Completer<ModelDownloadResult>? _blockedAttempt;
  var _modelAttempts = 0;

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
    if (artifactId == 'model' && _modelAttempts++ == 0) {
      calls.add(
        _StructuredStageCall(
          taskId: taskId,
          operationId: operationId,
          artifactId: artifactId,
          sourceUrl: sourceUrl,
          resumeFromBytes: resumeFromBytes,
        ),
      );
      await onProgress(
        const ModelDownloadProgress(
          receivedBytes: 4,
          totalBytes: 10,
          averageSpeedBytesPerSecond: 4,
          etag: '"pause-v1"',
          resumable: true,
        ),
      );
      firstProgress.complete();
      final blocked = Completer<ModelDownloadResult>();
      _blockedAttempt = blocked;
      return blocked.future;
    }
    return super.stageArtifact(
      taskId: taskId,
      modelId: modelId,
      operationId: operationId,
      artifactId: artifactId,
      sourceUrl: sourceUrl,
      expectedChecksum: expectedChecksum,
      expectedSizeBytes: expectedSizeBytes,
      resumeFromBytes: resumeFromBytes,
      onProgress: onProgress,
    );
  }

  @override
  void cancel(String taskId) {
    final blocked = _blockedAttempt;
    if (blocked != null && !blocked.isCompleted) {
      blocked.completeError(
        DioException(
          requestOptions: RequestOptions(path: 'fixture'),
          type: DioExceptionType.cancel,
        ),
      );
    }
  }
}
