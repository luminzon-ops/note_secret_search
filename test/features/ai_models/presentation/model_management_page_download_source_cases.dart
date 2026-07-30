part of 'model_management_page_test.dart';

void _registerDownloadSourceCases() {
  testWidgets(
    'ModelManagementPage lets the user switch the selected download source',
    (tester) async {
      late _RecordingModelDownloadController controller;

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
                      id: 'source-a',
                      label: 'GitHub Releases',
                      url: 'https://example.com/a.onnx',
                      checksum: 'sha256:source-a',
                    ),
                    ModelSourceEntry(
                      id: 'source-b',
                      label: '备用镜像',
                      url: 'https://example.com/b.onnx',
                      checksum: 'sha256:source-b',
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
            modelDownloadControllerProvider.overrideWith((ref) {
              controller = _RecordingModelDownloadController(ref: ref);
              return controller;
            }),
          ],
          child: const MaterialApp(home: ModelManagementPage()),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('当前下载源'), findsOneWidget);
      expect(find.textContaining('GitHub Releases'), findsAtLeast(2));

      final dropdownFinder = find.byType(DropdownButton<String>);
      await scrollUntilFound(tester, dropdownFinder);
      await tester.tap(dropdownFinder);
      await tester.pumpAndSettle();
      await tester.tap(find.text('备用镜像').hitTestable());
      await tester.pumpAndSettle();

      // After switching, the source label updates and dropdown item is selected.
      expect(find.textContaining('备用镜像'), findsAtLeast(1));
    },
  );

  testWidgets('ModelManagementPage starts download with the selected source', (
    tester,
  ) async {
    late _RecordingModelDownloadController controller;

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
                    id: 'source-a',
                    label: 'GitHub Releases',
                    url: 'https://example.com/a.onnx',
                    checksum: 'sha256:source-a',
                  ),
                  ModelSourceEntry(
                    id: 'source-b',
                    label: '备用镜像',
                    url: 'https://example.com/b.onnx',
                    checksum: 'sha256:source-b',
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
          modelDownloadControllerProvider.overrideWith((ref) {
            controller = _RecordingModelDownloadController(ref: ref);
            return controller;
          }),
        ],
        child: const MaterialApp(home: ModelManagementPage()),
      ),
    );

    await tester.pumpAndSettle();

    final dropdownFinder = find.byType(DropdownButton<String>);
    await scrollUntilFound(tester, dropdownFinder);
    await tester.tap(dropdownFinder);
    await tester.pumpAndSettle();
    await tester.tap(find.text('备用镜像').hitTestable());
    await tester.pumpAndSettle();

    final downloadButtonFinder = find.text('开始下载');
    await scrollUntilFound(tester, downloadButtonFinder);
    await tester.tap(downloadButtonFinder);
    await tester.pumpAndSettle();

    expect(controller.startedSource?.id, 'source-b');
    expect(controller.startedSource?.label, '备用镜像');
  });

  testWidgets(
    'ModelManagementPage prefers active downloading task over stale failed task from another source',
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
                      id: 'source-a',
                      label: '主镜像',
                      url: 'https://example.com/a.onnx',
                    ),
                    ModelSourceEntry(
                      id: 'source-b',
                      label: '备用镜像',
                      url: 'https://example.com/b.onnx',
                    ),
                  ],
                ),
              ],
            ),
            modelDownloadTasksProvider.overrideWith(
              (ref) async => [
                ModelDownloadTask(
                  id: 'task-failed-a',
                  modelId: 'embed-1',
                  sourceId: 'source-a',
                  status: ModelDownloadStatus.failed,
                  totalBytes: 10485760,
                  downloadedBytes: 1048576,
                  averageSpeed: null,
                  errorMessage: 'source-a failed',
                  resumable: false,
                  createdAt: DateTime(2026, 4, 21, 10, 0),
                  updatedAt: DateTime(2026, 4, 21, 10, 1),
                ),
                ModelDownloadTask(
                  id: 'task-downloading-b',
                  modelId: 'embed-1',
                  sourceId: 'source-b',
                  status: ModelDownloadStatus.downloading,
                  totalBytes: 10485760,
                  downloadedBytes: 5242880,
                  averageSpeed: 1572864,
                  errorMessage: null,
                  resumable: true,
                  createdAt: DateTime(2026, 4, 21, 10, 2),
                  updatedAt: DateTime(2026, 4, 21, 10, 3),
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

      expect(find.text('当前来源：备用镜像'), findsOneWidget);
      expect(find.text('source-a failed'), findsNothing);
    },
  );
}
