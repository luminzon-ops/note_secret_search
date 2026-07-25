part of 'model_download_structured_integration_test.dart';

void _registerStructuredFailureRecoveryTests() {
  test(
    'required artifact failure does not publish a partial revision',
    () async {
      final downloads = _MemoryDownloadRepository();
      const oldEntry = _trustedOldEntry;
      final registry = _MemoryRegistryRepository()..entry = oldEntry;
      final lifecycle = _RecordingLifecycleStore(
        downloads: downloads,
        registry: registry,
      );
      final service = _StructuredDownloadService(failingArtifactId: 'sidecar');
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

      expect(lifecycle.commitCalls, 0);
      expect(revisions.installCalls, 0);
      expect(registry.entry?.generation, oldEntry.generation);
      expect(registry.entry?.revisionRoot, oldEntry.revisionRoot);
      expect(downloads.tasks, isNotEmpty);
      expect(lifecycle.journals.map((journal) => journal.phase), <String>[
        'queued',
        'staging',
        'failed',
      ]);
      expect(lifecycle.journals.last.completedAt, isNotNull);
      expect(lifecycle.journals.last.oldRevision, oldEntry.revisionRoot);
      expect(revisions.discardedRevisionRoots, isEmpty);
    },
  );

  test(
    'registry commit failure discards only the new revision and keeps old trust',
    () async {
      final downloads = _MemoryDownloadRepository();
      const oldEntry = _trustedOldEntry;
      final registry = _MemoryRegistryRepository()..entry = oldEntry;
      final lifecycle = _RecordingLifecycleStore(
        downloads: downloads,
        registry: registry,
        commitError: StateError('model_registry_generation_stale'),
      );
      final revisions = _RecordingRevisionStore();
      final container = _container(
        downloads: downloads,
        registry: registry,
        lifecycle: lifecycle,
        service: _StructuredDownloadService(),
        revisions: revisions,
        bridge: _ReadyEmbeddingBridge(),
      );
      addTearDown(container.dispose);

      await container
          .read(modelDownloadControllerProvider)
          .startDownload(entry: _entry, source: _entry.sources.single);

      expect(lifecycle.commitCalls, 1);
      expect(registry.entry, same(oldEntry));
      expect(revisions.discardedRevisionRoots, <String>[
        '/support/models/structured-model/revisions/2',
      ]);
      expect(
        revisions.discardedRevisionRoots,
        isNot(contains(oldEntry.revisionRoot)),
      );
      expect(lifecycle.journals.last.phase, 'failed');
      expect(lifecycle.journals.last.completedAt, isNotNull);
    },
  );

  test(
    'open pre-commit journal rolls back before a newer generation installs',
    () async {
      final downloads = _MemoryDownloadRepository();
      const oldEntry = _trustedOldEntry;
      final registry = _MemoryRegistryRepository()..entry = oldEntry;
      final lifecycle = _RecordingLifecycleStore(
        downloads: downloads,
        registry: registry,
        initialJournals: const <ModelInstallJournalRecord>[
          ModelInstallJournalRecord(
            operationId: 'interrupted-operation',
            modelId: 'structured-model',
            releaseId: 'release-1',
            attemptGeneration: 2,
            operationType: 'replace',
            phase: 'installing',
            oldRevision: 'revisions/1',
            newRevision: 'revisions/2',
            stagingRoot: '.staging/interrupted-operation',
            targetRoot: 'revisions/2',
            createdAt: 1,
            updatedAt: 2,
          ),
        ],
      );
      final revisions = _RecordingRevisionStore();
      final container = _container(
        downloads: downloads,
        registry: registry,
        lifecycle: lifecycle,
        service: _StructuredDownloadService(),
        revisions: revisions,
        bridge: _ReadyEmbeddingBridge(),
      );
      addTearDown(container.dispose);

      await container
          .read(modelDownloadControllerProvider)
          .startDownload(entry: _entry, source: _entry.sources.single);

      expect(registry.entry?.generation, 3);
      expect(lifecycle.latestJournal('interrupted-operation')?.phase, 'failed');
      expect(
        lifecycle.latestJournal('interrupted-operation')?.errorCode,
        'interrupted_install_rolled_back',
      );
      expect(revisions.discardedRevisionRoots, <String>[
        'revisions/2',
        'revisions/1',
      ]);
    },
  );

  test(
    'open post-commit journal is finalized before the next replacement',
    () async {
      final downloads = _MemoryDownloadRepository();
      final registry = _MemoryRegistryRepository()
        ..entry = _trustedOldEntry.copyWith(
          version: 'release-1',
          releaseId: 'release-1',
          catalogVersion: 7,
          catalogDigest: _entry.catalogDigest,
          generation: 2,
          revisionRoot: 'revisions/2',
        );
      final lifecycle = _RecordingLifecycleStore(
        downloads: downloads,
        registry: registry,
        initialJournals: const <ModelInstallJournalRecord>[
          ModelInstallJournalRecord(
            operationId: 'committed-operation',
            modelId: 'structured-model',
            releaseId: 'release-1',
            attemptGeneration: 2,
            operationType: 'replace',
            phase: 'committing',
            oldRevision: 'revisions/1',
            newRevision: 'revisions/2',
            stagingRoot: '.staging/committed-operation',
            targetRoot: 'revisions/2',
            createdAt: 1,
            updatedAt: 2,
          ),
        ],
      );
      final revisions = _RecordingRevisionStore();
      final container = _container(
        downloads: downloads,
        registry: registry,
        lifecycle: lifecycle,
        service: _StructuredDownloadService(),
        revisions: revisions,
        bridge: _ReadyEmbeddingBridge(),
      );
      addTearDown(container.dispose);

      await container
          .read(modelDownloadControllerProvider)
          .startDownload(entry: _entry, source: _entry.sources.single);

      expect(registry.entry?.generation, 3);
      expect(
        lifecycle.latestJournal('committed-operation')?.phase,
        'completed',
      );
      expect(
        lifecycle.latestJournal('committed-operation')?.completedAt,
        isNotNull,
      );
      expect(revisions.discardedRevisionRoots, <String>[
        'revisions/1',
        'revisions/2',
      ]);
    },
  );
}
