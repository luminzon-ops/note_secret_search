part of 'model_management_page_test.dart';

void _registerActionCases() {
  testWidgets(
    'ModelManagementPage shows 开始下载 for zero-byte paused task (action-hole regression)',
    (tester) async {
      // Regression test: zero-byte paused task should still show 开始下载 as primary action.
      // The bug: latestTask != null suppresses 开始下载, but canResume is false (zero bytes),
      // leaving no actionable primary download button.
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
                  downloadedBytes: 0, // zero bytes — the key scenario
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

      // Must show 开始下载 — this is the action-hole regression
      expect(find.text('开始下载'), findsOneWidget);
      expect(find.text('继续下载'), findsNothing);
    },
  );

  testWidgets(
    'ModelManagementPage shows 开始下载 for zero-byte queued task (action-hole regression)',
    (tester) async {
      // Regression test: zero-byte queued task should still show 开始下载 as primary action.
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
                  downloadedBytes: 0, // zero bytes — the key scenario
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

      // Must show 开始下载 — zero-byte queued should fall back to start, not strand user
      expect(find.text('开始下载'), findsOneWidget);
      expect(find.text('继续下载'), findsNothing);
    },
  );

  testWidgets(
    'ModelManagementPage keeps 重试下载 for failed non-resumable task and hides 开始下载',
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
      expect(find.text('重试下载'), findsOneWidget);
      expect(find.text('开始下载'), findsNothing);
    },
  );

  testWidgets(
    'ModelManagementPage shows download source label and updated time for active task',
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
                      label: '清华镜像源',
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
                  updatedAt: DateTime(2026, 4, 21, 10, 1, 30),
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

      expect(find.text('当前来源：清华镜像源'), findsOneWidget);
      expect(find.text('任务创建：2026-04-21 10:00:00'), findsOneWidget);
      expect(find.text('最近更新：2026-04-21 10:01:30'), findsOneWidget);
      expect(find.text('下载进度：50%'), findsOneWidget);
    },
  );
}
