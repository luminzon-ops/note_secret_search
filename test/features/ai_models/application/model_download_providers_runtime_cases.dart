part of 'model_download_providers_test.dart';

void _registerModelDownloadRuntimeCases() {
  test(
    'startDownload validates embedding runtime after download completes',
    () async {
      final downloadRepository = _MemoryDownloadRepository();
      final registryRepository = _MemoryRegistryRepository();
      final bridge = _RecordingEmbeddingRuntimeBridge();
      final downloadService = _FakeDownloadService(
        result: const ModelDownloadResult(
          localPath: '/models/embed-1.onnx',
          totalBytes: 4096,
          verifiedChecksum: 'sha256:verified-embed-1',
        ),
      );

      final container = _modelProviderContainer(
        overrides: [
          modelDownloadRepositoryProvider.overrideWithValue(downloadRepository),
          modelRegistryRepositoryProvider.overrideWithValue(registryRepository),
          modelDownloadServiceProvider.overrideWithValue(downloadService),
          embeddingRuntimeBridgeProvider.overrideWithValue(bridge),
        ],
      );

      addTearDown(container.dispose);

      await container
          .read(modelDownloadControllerProvider)
          .startDownload(
            entry: const ModelCatalogEntry(
              id: 'embed-1',
              type: 'embedding',
              tier: 'mvp',
              displayName: 'MiniLM Embedding',
              description: '用于本地语义检索。',
              sizeBytes: 4096,
              minRamMb: 512,
              recommendedTier: 'mvp',
              tokenizer: EmbeddingTokenizerSpec(
                format: 'tokenizer_json',
                assetPath:
                    'assets/model_catalog/tokenizers/all_minilm/tokenizer.json',
                maxSequenceLength: 256,
                lowercase: true,
              ),
              runtime: EmbeddingRuntimeSpec(
                inputIdsName: 'input_ids',
                attentionMaskName: 'attention_mask',
                outputName: 'last_hidden_state',
                pooling: 'mean',
                normalization: 'l2',
              ),
              sources: <ModelSourceEntry>[
                ModelSourceEntry(
                  id: 'source-1',
                  label: '镜像源',
                  url: 'https://example.com/embed-1.onnx',
                  checksum: 'sha256:verified-embed-1',
                ),
              ],
            ),
            source: const ModelSourceEntry(
              id: 'source-1',
              label: '镜像源',
              url: 'https://example.com/embed-1.onnx',
              checksum: 'sha256:verified-embed-1',
            ),
          );

      expect(bridge.ensureCalls, 1);
      expect(bridge.lastModelId, 'embed-1');
      expect(bridge.lastModelPath, '/models/embed-1.onnx');
      expect(bridge.lastTokenizer, isNotNull);
      expect(bridge.lastTokenizer?.maxSequenceLength, 256);
      expect(bridge.lastRuntime, isNotNull);
      expect(bridge.lastRuntime?.pooling, 'mean');
      expect(bridge.lastVerifiedChecksum, 'sha256:verified-embed-1');
      expect(
        registryRepository.entries['embed-1']?.localPath,
        '/models/embed-1.onnx',
      );
      expect(
        registryRepository.entries['embed-1']?.checksum,
        'sha256:verified-embed-1',
      );
    },
  );

  test(
    'startDownload rejects repeated multimodal attempts without tasks or side effects',
    () async {
      final downloadRepository = _MemoryDownloadRepository();
      final registryRepository = _MemoryRegistryRepository();
      final downloadService = _FakeDownloadService();
      final runtimeBridge = _RecordingMultimodalLlmRuntimeBridge(
        ensureResult: <String, dynamic>{
          'status': 'runtime_unavailable',
          'ready': false,
          'message': '当前 native runtime 不支持 MiniCPM-V 4.6 多模态推理，请更新 runtime。',
        },
      );
      const modelUrl = 'https://example.com/MiniCPM-V-4_6-Q4_K_M.gguf';
      const mmprojUrl = 'https://example.com/mmproj-model-f16.gguf';
      downloadService.setResultForSource(
        sourceUrl: modelUrl,
        result: const ModelDownloadResult(
          localPath: '/models/minicpm/MiniCPM-V-4_6-Q4_K_M.gguf',
          totalBytes: 10,
          verifiedChecksum: 'sha256:model',
        ),
      );
      downloadService.setResultForSource(
        sourceUrl: mmprojUrl,
        result: const ModelDownloadResult(
          localPath: '/models/minicpm/mmproj-model-f16.gguf',
          totalBytes: 20,
          verifiedChecksum: 'sha256:mmproj',
        ),
      );
      const entry = ModelCatalogEntry(
        id: 'minicpm_v_4_6_q4_k_m',
        type: 'multimodal_llm',
        tier: 'local_multimodal',
        displayName: 'MiniCPM-V 4.6 Q4_K_M Multimodal',
        description: 'Requires LLM GGUF plus mmproj-model-f16.gguf.',
        sizeBytes: 30,
        minRamMb: 6144,
        recommendedTier: 'vision_language_local',
        sources: <ModelSourceEntry>[
          ModelSourceEntry(
            id: 'minicpm-v-4-6-q4-k-m-llm',
            label: 'HuggingFace MiniCPM-V 4.6 GGUF LLM',
            role: 'model',
            url: modelUrl,
            checksum: 'sha256:model',
          ),
          ModelSourceEntry(
            id: 'minicpm-v-4-6-mmproj-f16',
            label: 'HuggingFace MiniCPM-V 4.6 mmproj',
            role: 'mmproj',
            url: mmprojUrl,
            checksum: 'sha256:mmproj',
          ),
        ],
      );

      final container = _modelProviderContainer(
        overrides: [
          modelDownloadRepositoryProvider.overrideWithValue(downloadRepository),
          modelRegistryRepositoryProvider.overrideWithValue(registryRepository),
          modelDownloadServiceProvider.overrideWithValue(downloadService),
          multimodalLlmRuntimeBridgeProvider.overrideWithValue(runtimeBridge),
        ],
      );

      addTearDown(container.dispose);

      final controller = container.read(modelDownloadControllerProvider);
      final unsupportedError = isA<UnsupportedError>().having(
        (error) => error.message,
        'message',
        contains('multimodal_llm'),
      );

      await expectLater(
        controller.startDownload(entry: entry, source: entry.sources.first),
        throwsA(unsupportedError),
      );
      await expectLater(
        controller.startDownload(entry: entry, source: entry.sources.first),
        throwsA(unsupportedError),
      );

      expect(downloadRepository.tasksById, isEmpty);
      expect(downloadService.invocations, isEmpty);
      expect(downloadService.inspectedKeys, isEmpty);
      expect(downloadService.fileExistsPaths, isEmpty);
      expect(downloadService.verifiedPaths, isEmpty);
      expect(downloadService.deletedPaths, isEmpty);
      expect(runtimeBridge.ensureCalls, 0);
      expect(registryRepository.entries['minicpm_v_4_6_q4_k_m'], isNull);
    },
  );

  test(
    'startDownload persists downloading status before first progress callback',
    () async {
      final downloadRepository = _MemoryDownloadRepository();
      final registryRepository = _MemoryRegistryRepository();
      final bridge = _RecordingEmbeddingRuntimeBridge();
      final downloadService = _FakeDownloadService(
        result: const ModelDownloadResult(
          localPath: '/models/embed-1.onnx',
          totalBytes: 4096,
          verifiedChecksum: 'sha256:verified-embed-1',
        ),
      );
      downloadService.progressGate = Completer<void>();

      final container = _modelProviderContainer(
        overrides: [
          modelDownloadRepositoryProvider.overrideWithValue(downloadRepository),
          modelRegistryRepositoryProvider.overrideWithValue(registryRepository),
          modelDownloadServiceProvider.overrideWithValue(downloadService),
          embeddingRuntimeBridgeProvider.overrideWithValue(bridge),
        ],
      );

      addTearDown(container.dispose);

      final startFuture = container
          .read(modelDownloadControllerProvider)
          .startDownload(
            entry: const ModelCatalogEntry(
              id: 'embed-1',
              type: 'embedding',
              tier: 'mvp',
              displayName: 'MiniLM Embedding',
              description: '用于本地语义检索。',
              sizeBytes: 4096,
              minRamMb: 512,
              recommendedTier: 'mvp',
              sources: <ModelSourceEntry>[
                ModelSourceEntry(
                  id: 'source-1',
                  label: '镜像源',
                  url: 'https://example.com/embed-1.onnx',
                  checksum: 'sha256:verified-embed-1',
                ),
              ],
            ),
            source: const ModelSourceEntry(
              id: 'source-1',
              label: '镜像源',
              url: 'https://example.com/embed-1.onnx',
              checksum: 'sha256:verified-embed-1',
            ),
          );

      await Future<void>.delayed(Duration.zero);

      expect(
        downloadRepository.tasksByModelAndSource('embed-1', 'source-1')?.status,
        ModelDownloadStatus.downloading,
      );

      downloadService.progressGate!.complete();
      await startFuture;
    },
  );

  test(
    'modelDownloadTasksProvider normalizes stale downloading task to paused with local partial bytes when catalog source exists',
    () async {
      final downloadRepository = _MemoryDownloadRepository();
      final registryRepository = _MemoryRegistryRepository();
      final downloadService = _FakeDownloadService();
      final catalogRepository = _MemoryCatalogRepository(
        const <ModelCatalogEntry>[
          ModelCatalogEntry(
            id: 'embed-1',
            type: 'embedding',
            tier: 'mvp',
            displayName: 'MiniLM Embedding',
            description: '用于本地语义检索。',
            sizeBytes: 4096,
            minRamMb: 512,
            recommendedTier: 'mvp',
            sources: <ModelSourceEntry>[
              ModelSourceEntry(
                id: 'source-a',
                label: '主镜像',
                url: 'https://example.com/embed-1.onnx',
                checksum: 'sha256:verified-embed-1',
              ),
            ],
          ),
        ],
      );

      downloadRepository.tasksById['task-downloading'] = _buildTask(
        id: 'task-downloading',
        modelId: 'embed-1',
        sourceId: 'source-a',
        status: ModelDownloadStatus.downloading,
        downloadedBytes: 32,
      );

      downloadService.setTarget(
        modelId: 'embed-1',
        sourceUrl: 'https://example.com/embed-1.onnx',
        existingBytes: 1536,
        localPath: '/partials/embed-1-source-a.partial',
      );

      final container = _modelProviderContainer(
        overrides: [
          sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
          modelDownloadRepositoryProvider.overrideWithValue(downloadRepository),
          modelRegistryRepositoryProvider.overrideWithValue(registryRepository),
          modelDownloadServiceProvider.overrideWithValue(downloadService),
          modelCatalogRepositoryProvider.overrideWithValue(catalogRepository),
        ],
      );

      addTearDown(container.dispose);

      final tasks = await container.read(modelDownloadTasksProvider.future);
      final normalized = tasks.singleWhere(
        (task) => task.id == 'task-downloading',
      );

      expect(normalized.status, ModelDownloadStatus.paused);
      expect(normalized.downloadedBytes, 1536);
      expect(
        downloadRepository.tasksById['task-downloading']?.status,
        ModelDownloadStatus.paused,
      );
      expect(
        downloadRepository.tasksById['task-downloading']?.downloadedBytes,
        1536,
      );
    },
  );

  test(
    'startDownload validates llm runtime after download completes',
    () async {
      final downloadRepository = _MemoryDownloadRepository();
      final registryRepository = _MemoryRegistryRepository();
      final llmBridge = _RecordingLlmRuntimeBridge();
      final downloadService = _FakeDownloadService(
        result: const ModelDownloadResult(
          localPath: '/models/phi.gguf',
          totalBytes: 8192,
          verifiedChecksum: 'sha256:verified-llm-1',
        ),
      );

      final container = _modelProviderContainer(
        overrides: [
          modelDownloadRepositoryProvider.overrideWithValue(downloadRepository),
          modelRegistryRepositoryProvider.overrideWithValue(registryRepository),
          modelDownloadServiceProvider.overrideWithValue(downloadService),
          llmRuntimeBridgeProvider.overrideWithValue(llmBridge),
        ],
      );

      addTearDown(container.dispose);

      await container
          .read(modelDownloadControllerProvider)
          .startDownload(
            entry: const ModelCatalogEntry(
              id: 'llm-1',
              type: 'llm',
              tier: 'local',
              displayName: 'Phi Local',
              description: '用于本地问答。',
              sizeBytes: 8192,
              minRamMb: 2048,
              recommendedTier: 'local',
              sources: <ModelSourceEntry>[
                ModelSourceEntry(
                  id: 'source-1',
                  label: '镜像源',
                  url: 'https://example.com/phi.gguf',
                  checksum: 'sha256:verified-llm-1',
                ),
              ],
            ),
            source: const ModelSourceEntry(
              id: 'source-1',
              label: '镜像源',
              url: 'https://example.com/phi.gguf',
              checksum: 'sha256:verified-llm-1',
            ),
          );

      expect(llmBridge.ensureCalls, 1);
      expect(llmBridge.lastModelId, 'llm-1');
      expect(llmBridge.lastModelPath, '/models/phi.gguf');
      expect(
        registryRepository.entries['llm-1']?.localPath,
        '/models/phi.gguf',
      );
      expect(
        registryRepository.entries['llm-1']?.checksum,
        'sha256:verified-llm-1',
      );
    },
  );

  test(
    'startDownload keeps llm model disabled when runtime verification returns degraded',
    () async {
      final downloadRepository = _MemoryDownloadRepository();
      final registryRepository = _MemoryRegistryRepository();
      final llmBridge = _RecordingLlmRuntimeBridge(
        ensureResult: <String, dynamic>{
          'ready': false,
          'status': 'degraded',
          'reason': '真实 probe failed',
          'modelPath': '/models/phi.gguf',
          'checkedAt': DateTime(2026, 4, 26).millisecondsSinceEpoch,
        },
      );
      final downloadService = _FakeDownloadService(
        result: const ModelDownloadResult(
          localPath: '/models/phi.gguf',
          totalBytes: 8192,
          verifiedChecksum: 'sha256:verified-llm-1',
        ),
      );

      final container = _modelProviderContainer(
        overrides: [
          modelDownloadRepositoryProvider.overrideWithValue(downloadRepository),
          modelRegistryRepositoryProvider.overrideWithValue(registryRepository),
          modelDownloadServiceProvider.overrideWithValue(downloadService),
          llmRuntimeBridgeProvider.overrideWithValue(llmBridge),
        ],
      );

      addTearDown(container.dispose);

      await container
          .read(modelDownloadControllerProvider)
          .startDownload(
            entry: const ModelCatalogEntry(
              id: 'llm-1',
              type: 'llm',
              tier: 'local',
              displayName: 'Phi Local',
              description: '用于本地问答。',
              sizeBytes: 8192,
              minRamMb: 2048,
              recommendedTier: 'local',
              sources: <ModelSourceEntry>[
                ModelSourceEntry(
                  id: 'source-1',
                  label: '镜像源',
                  url: 'https://example.com/phi.gguf',
                  checksum: 'sha256:verified-llm-1',
                ),
              ],
            ),
            source: const ModelSourceEntry(
              id: 'source-1',
              label: '镜像源',
              url: 'https://example.com/phi.gguf',
              checksum: 'sha256:verified-llm-1',
            ),
          );

      expect(llmBridge.ensureCalls, 1);
      expect(registryRepository.entries['llm-1']?.enabled, isFalse);
      expect(registryRepository.entries['llm-1']?.filePresent, isTrue);
      expect(
        registryRepository.entries['llm-1']?.checksum,
        'sha256:verified-llm-1',
      );
    },
  );
}
