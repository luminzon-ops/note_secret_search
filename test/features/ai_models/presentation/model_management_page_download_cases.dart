part of 'model_management_page_test.dart';

void _registerDownloadCases() {
  testWidgets(
    'ModelManagementPage shows 尚未创建下载任务 when no download task exists',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            modelCatalogEntriesProvider.overrideWith(
              (ref) async => const [
                ModelCatalogEntry(
                  id: 'embed-1',
                  type: 'embedding',
                  tier: 'mvp',
                  displayName: 'MiniLM Embedding',
                  description: '用于本地语义检索。',
                  sizeBytes: 10485760,
                  minRamMb: 512,
                  recommendedTier: 'mvp',
                  sources: <ModelSourceEntry>[
                    ModelSourceEntry(
                      id: 'src-1',
                      label: '镜像源',
                      url: 'https://example.com/model',
                    ),
                  ],
                ),
              ],
            ),
            modelDownloadTasksProvider.overrideWith(
              (ref) async => const <ModelDownloadTask>[],
            ),
            modelRegistryEntriesProvider.overrideWith(
              (ref) async => const <ModelRegistryEntry>[],
            ),
            activeModelSelectionProvider.overrideWith(
              (ref) async =>
                  const ActiveModelSelection(activeEmbeddingModelId: null),
            ),
            embeddingRuntimeStatesProvider.overrideWith(
              (ref) async => const <String, EmbeddingEngineState>{},
            ),
            modelDownloadControllerProvider.overrideWith(
              (ref) => _FakeModelDownloadController(ref: ref),
            ),
          ],
          child: const MaterialApp(home: ModelManagementPage()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('尚未创建下载任务'), findsOneWidget);
    },
  );

  testWidgets(
    'ModelManagementPage shows queued download guidance for queued task',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            modelCatalogEntriesProvider.overrideWith(
              (ref) async => const [
                ModelCatalogEntry(
                  id: 'embed-1',
                  type: 'embedding',
                  tier: 'mvp',
                  displayName: 'MiniLM Embedding',
                  description: '用于本地语义检索。',
                  sizeBytes: 10485760,
                  minRamMb: 512,
                  recommendedTier: 'mvp',
                  sources: <ModelSourceEntry>[
                    ModelSourceEntry(
                      id: 'src-1',
                      label: '镜像源',
                      url: 'https://example.com/model',
                    ),
                  ],
                ),
              ],
            ),
            modelDownloadTasksProvider.overrideWith(
              (ref) async => [
                ModelDownloadTask(
                  id: 'task-1',
                  modelId: 'embed-1',
                  sourceId: 'src-1',
                  status: ModelDownloadStatus.queued,
                  totalBytes: 10485760,
                  downloadedBytes: 0,
                  averageSpeed: null,
                  errorMessage: null,
                  resumable: true,
                  createdAt: DateTime(2026, 4, 21, 10, 0),
                  updatedAt: DateTime(2026, 4, 21, 10, 1),
                ),
              ],
            ),
            modelRegistryEntriesProvider.overrideWith(
              (ref) async => const <ModelRegistryEntry>[],
            ),
            activeModelSelectionProvider.overrideWith(
              (ref) async =>
                  const ActiveModelSelection(activeEmbeddingModelId: null),
            ),
            embeddingRuntimeStatesProvider.overrideWith(
              (ref) async => const <String, EmbeddingEngineState>{},
            ),
            modelDownloadControllerProvider.overrideWith(
              (ref) => _FakeModelDownloadController(ref: ref),
            ),
          ],
          child: const MaterialApp(home: ModelManagementPage()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('任务说明：已加入下载队列，等待开始下载。'), findsOneWidget);
    },
  );

  testWidgets(
    'ModelManagementPage shows paused download guidance for paused task',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            modelCatalogEntriesProvider.overrideWith(
              (ref) async => const [
                ModelCatalogEntry(
                  id: 'embed-1',
                  type: 'embedding',
                  tier: 'mvp',
                  displayName: 'MiniLM Embedding',
                  description: '用于本地语义检索。',
                  sizeBytes: 10485760,
                  minRamMb: 512,
                  recommendedTier: 'mvp',
                  sources: <ModelSourceEntry>[
                    ModelSourceEntry(
                      id: 'src-1',
                      label: '镜像源',
                      url: 'https://example.com/model',
                    ),
                  ],
                ),
              ],
            ),
            modelDownloadTasksProvider.overrideWith(
              (ref) async => [
                ModelDownloadTask(
                  id: 'task-1',
                  modelId: 'embed-1',
                  sourceId: 'src-1',
                  status: ModelDownloadStatus.paused,
                  totalBytes: 10485760,
                  downloadedBytes: 5242880,
                  averageSpeed: null,
                  errorMessage: null,
                  resumable: true,
                  createdAt: DateTime(2026, 4, 21, 10, 0),
                  updatedAt: DateTime(2026, 4, 21, 10, 1),
                ),
              ],
            ),
            modelRegistryEntriesProvider.overrideWith(
              (ref) async => const <ModelRegistryEntry>[],
            ),
            activeModelSelectionProvider.overrideWith(
              (ref) async =>
                  const ActiveModelSelection(activeEmbeddingModelId: null),
            ),
            embeddingRuntimeStatesProvider.overrideWith(
              (ref) async => const <String, EmbeddingEngineState>{},
            ),
            modelDownloadControllerProvider.overrideWith(
              (ref) => _FakeModelDownloadController(ref: ref),
            ),
          ],
          child: const MaterialApp(home: ModelManagementPage()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('任务说明：下载已暂停，可稍后继续或重新开始。'), findsOneWidget);
    },
  );

  testWidgets(
    'ModelManagementPage shows 继续下载 with visible paused progress copy for resumable paused task',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            modelCatalogEntriesProvider.overrideWith(
              (ref) async => const [
                ModelCatalogEntry(
                  id: 'embed-1',
                  type: 'embedding',
                  tier: 'mvp',
                  displayName: 'MiniLM Embedding',
                  description: '用于本地语义检索。',
                  sizeBytes: 10485760,
                  minRamMb: 512,
                  recommendedTier: 'mvp',
                  sources: <ModelSourceEntry>[
                    ModelSourceEntry(
                      id: 'src-1',
                      label: '镜像源',
                      url: 'https://example.com/model',
                    ),
                  ],
                ),
              ],
            ),
            modelDownloadTasksProvider.overrideWith(
              (ref) async => [
                ModelDownloadTask(
                  id: 'task-1',
                  modelId: 'embed-1',
                  sourceId: 'src-1',
                  status: ModelDownloadStatus.paused,
                  totalBytes: 10485760,
                  downloadedBytes: 5242880,
                  averageSpeed: null,
                  errorMessage: null,
                  resumable: true,
                  createdAt: DateTime(2026, 4, 21, 10, 0),
                  updatedAt: DateTime(2026, 4, 21, 10, 1),
                ),
              ],
            ),
            modelRegistryEntriesProvider.overrideWith(
              (ref) async => const <ModelRegistryEntry>[],
            ),
            activeModelSelectionProvider.overrideWith(
              (ref) async =>
                  const ActiveModelSelection(activeEmbeddingModelId: null),
            ),
            embeddingRuntimeStatesProvider.overrideWith(
              (ref) async => const <String, EmbeddingEngineState>{},
            ),
            modelDownloadControllerProvider.overrideWith(
              (ref) => _FakeModelDownloadController(ref: ref),
            ),
          ],
          child: const MaterialApp(home: ModelManagementPage()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('下载进度：50%'), findsOneWidget);
      expect(find.text('继续下载'), findsOneWidget);
      expect(find.text('开始下载'), findsNothing);
    },
  );

  testWidgets(
    'ModelManagementPage shows download speed and resumable support while downloading',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            modelCatalogEntriesProvider.overrideWith(
              (ref) async => const [
                ModelCatalogEntry(
                  id: 'embed-1',
                  type: 'embedding',
                  tier: 'mvp',
                  displayName: 'MiniLM Embedding',
                  description: '用于本地语义检索。',
                  sizeBytes: 10485760,
                  minRamMb: 512,
                  recommendedTier: 'mvp',
                  sources: <ModelSourceEntry>[
                    ModelSourceEntry(
                      id: 'src-1',
                      label: '镜像源',
                      url: 'https://example.com/model',
                    ),
                  ],
                ),
              ],
            ),
            modelDownloadTasksProvider.overrideWith(
              (ref) async => [
                ModelDownloadTask(
                  id: 'task-1',
                  modelId: 'embed-1',
                  sourceId: 'src-1',
                  status: ModelDownloadStatus.downloading,
                  totalBytes: 10485760,
                  downloadedBytes: 5242880,
                  averageSpeed: 1572864,
                  errorMessage: null,
                  resumable: true,
                  createdAt: DateTime(2026, 4, 21, 10, 0),
                  updatedAt: DateTime(2026, 4, 21, 10, 1),
                ),
              ],
            ),
            modelRegistryEntriesProvider.overrideWith(
              (ref) async => const <ModelRegistryEntry>[],
            ),
            activeModelSelectionProvider.overrideWith(
              (ref) async =>
                  const ActiveModelSelection(activeEmbeddingModelId: null),
            ),
            embeddingRuntimeStatesProvider.overrideWith(
              (ref) async => const <String, EmbeddingEngineState>{},
            ),
            modelDownloadControllerProvider.overrideWith(
              (ref) => _FakeModelDownloadController(ref: ref),
            ),
          ],
          child: const MaterialApp(home: ModelManagementPage()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('下载速度：1.5 MB/s'), findsOneWidget);
      expect(find.text('断点续传：支持'), findsOneWidget);
    },
  );

  testWidgets(
    'ModelManagementPage shows non-resumable hint for failed download task',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            modelCatalogEntriesProvider.overrideWith(
              (ref) async => const [
                ModelCatalogEntry(
                  id: 'embed-1',
                  type: 'embedding',
                  tier: 'mvp',
                  displayName: 'MiniLM Embedding',
                  description: '用于本地语义检索。',
                  sizeBytes: 10485760,
                  minRamMb: 512,
                  recommendedTier: 'mvp',
                  sources: <ModelSourceEntry>[
                    ModelSourceEntry(
                      id: 'src-1',
                      label: '镜像源',
                      url: 'https://example.com/model',
                    ),
                  ],
                ),
              ],
            ),
            modelDownloadTasksProvider.overrideWith(
              (ref) async => [
                ModelDownloadTask(
                  id: 'task-1',
                  modelId: 'embed-1',
                  sourceId: 'src-1',
                  status: ModelDownloadStatus.failed,
                  totalBytes: 10485760,
                  downloadedBytes: 3145728,
                  averageSpeed: null,
                  errorMessage: '网络中断',
                  resumable: false,
                  createdAt: DateTime(2026, 4, 21, 10, 0),
                  updatedAt: DateTime(2026, 4, 21, 10, 1),
                ),
              ],
            ),
            modelRegistryEntriesProvider.overrideWith(
              (ref) async => const <ModelRegistryEntry>[],
            ),
            activeModelSelectionProvider.overrideWith(
              (ref) async =>
                  const ActiveModelSelection(activeEmbeddingModelId: null),
            ),
            modelDownloadControllerProvider.overrideWith(
              (ref) => _FakeModelDownloadController(ref: ref),
            ),
          ],
          child: const MaterialApp(home: ModelManagementPage()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('断点续传：当前下载源不支持'), findsOneWidget);
    },
  );
}
