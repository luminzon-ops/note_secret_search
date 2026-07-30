part of 'model_management_page_test.dart';

void _registerCatalogBasicsCases() {
  testWidgets(
    'ModelManagementPage shows 可下载模型目录 section heading for catalog entries',
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
                  sources: <ModelSourceEntry>[],
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

      expect(find.text('可下载模型目录'), findsOneWidget);
    },
  );

  testWidgets(
    'ModelManagementPage independently filters multimodal catalog entries',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            modelCatalogEntriesProvider.overrideWith(
              (ref) async => const <ModelCatalogEntry>[
                ModelCatalogEntry(
                  id: 'embed-1',
                  type: 'embedding',
                  tier: 'mvp',
                  displayName: 'Visible Embedding',
                  description: 'Supported catalog entry.',
                  sizeBytes: 1024,
                  minRamMb: 512,
                  recommendedTier: 'mvp',
                  sources: <ModelSourceEntry>[],
                ),
                ModelCatalogEntry(
                  id: 'multimodal-1',
                  type: 'multimodal_llm',
                  tier: 'local_multimodal',
                  displayName: 'Hidden Multimodal Catalog Entry',
                  description: 'Unavailable catalog entry.',
                  sizeBytes: 2048,
                  minRamMb: 1024,
                  recommendedTier: 'vision_language_local',
                  sources: <ModelSourceEntry>[],
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
            llmRuntimeStatesProvider.overrideWith(
              (ref) async => const <String, LlmRuntimeState>{},
            ),
            modelDownloadControllerProvider.overrideWith(
              (ref) => _FakeModelDownloadController(ref: ref),
            ),
          ],
          child: const MaterialApp(home: ModelManagementPage()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Visible Embedding'), findsOneWidget);
      expect(find.text('Hidden Multimodal Catalog Entry'), findsNothing);
    },
  );

  testWidgets('ModelManagementPage exposes legacy multimodal cleanup', (
    tester,
  ) async {
    late _RecordingModelDownloadController controller;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          modelCatalogEntriesProvider.overrideWith(
            (ref) async => const <ModelCatalogEntry>[],
          ),
          modelDownloadTasksProvider.overrideWith(
            (ref) async => const <ModelDownloadTask>[],
          ),
          modelRegistryEntriesProvider.overrideWith(
            (ref) async => const <ModelRegistryEntry>[
              ModelRegistryEntry(
                id: 'embed-1',
                type: 'embedding',
                provider: 'builtin',
                name: 'Visible Installed Embedding',
                version: null,
                sizeBytes: null,
                quantization: null,
                minRamMb: null,
                recommendedTier: null,
                localPath: '/models/embed.onnx',
                checksum: 'sha256:embed',
                enabled: true,
                installedAt: null,
                filePresent: true,
              ),
              ModelRegistryEntry(
                id: 'multimodal-1',
                type: 'multimodal_llm',
                provider: 'builtin',
                name: 'Hidden Installed Multimodal',
                version: null,
                sizeBytes: null,
                quantization: null,
                minRamMb: null,
                recommendedTier: null,
                localPath: '/models/multimodal.gguf',
                checksum: 'sha256:multimodal',
                enabled: true,
                installedAt: null,
                filePresent: true,
              ),
            ],
          ),
          activeModelSelectionProvider.overrideWith(
            (ref) async =>
                const ActiveModelSelection(activeEmbeddingModelId: null),
          ),
          embeddingRuntimeStatesProvider.overrideWith(
            (ref) async => {
              'embed-1': const EmbeddingEngineState(
                ready: true,
                reason: 'ready',
                status: EmbeddingRuntimeStatus.ready,
              ),
            },
          ),
          llmRuntimeStatesProvider.overrideWith(
            (ref) async => const <String, LlmRuntimeState>{},
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

    expect(find.text('Visible Installed Embedding'), findsOneWidget);
    expect(find.text('Hidden Installed Multimodal'), findsOneWidget);
    expect(find.text('待清理'), findsOneWidget);
    expect(find.text('校验'), findsOneWidget);
    expect(find.text('修复'), findsNothing);
    expect(find.text('删除本地模型'), findsOneWidget);

    await scrollUntilFound(tester, find.text('删除本地模型'));
    await tester.tap(find.text('删除本地模型'));
    await tester.pump();
    expect(controller.deletedModelId, 'multimodal-1');
  });
}

void _registerCatalogDeploymentCases() {
  testWidgets(
    'ModelManagementPage catalog entry shows installed deployment status when local file is ready',
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
                  sources: <ModelSourceEntry>[],
                ),
              ],
            ),
            modelDownloadTasksProvider.overrideWith(
              (ref) async => const <ModelDownloadTask>[],
            ),
            modelRegistryEntriesProvider.overrideWith(
              (ref) async => const [_installedEmbeddingRegistryEntry],
            ),
            activeModelSelectionProvider.overrideWith(
              (ref) async =>
                  const ActiveModelSelection(activeEmbeddingModelId: null),
            ),
            embeddingRuntimeStatesProvider.overrideWith(
              (ref) async => {
                'embed-1': const EmbeddingEngineState(
                  ready: true,
                  reason: 'ready',
                  status: EmbeddingRuntimeStatus.ready,
                ),
              },
            ),
            modelDownloadControllerProvider.overrideWith(
              (ref) => _FakeModelDownloadController(ref: ref),
            ),
          ],
          child: const MaterialApp(home: ModelManagementPage()),
        ),
      );

      await tester.pumpAndSettle();

      final readyStatus = find.text('部署状态：本地已就绪，可用于后续启用或检索配置。');
      await scrollUntilFound(tester, readyStatus);
      expect(readyStatus, findsOneWidget);
      expect(find.text('本地部署已就绪'), findsOneWidget);
    },
  );

  testWidgets(
    'ModelManagementPage catalog chip shows 当前语义模型 for the active embedding model',
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
                  sources: <ModelSourceEntry>[],
                ),
              ],
            ),
            modelDownloadTasksProvider.overrideWith(
              (ref) async => const <ModelDownloadTask>[],
            ),
            modelRegistryEntriesProvider.overrideWith(
              (ref) async => const [_installedEmbeddingRegistryEntry],
            ),
            activeModelSelectionProvider.overrideWith(
              (ref) async =>
                  const ActiveModelSelection(activeEmbeddingModelId: 'embed-1'),
            ),
            embeddingRuntimeStatesProvider.overrideWith(
              (ref) async => {
                'embed-1': const EmbeddingEngineState(
                  ready: true,
                  reason: 'ready',
                  status: EmbeddingRuntimeStatus.ready,
                ),
              },
            ),
            modelDownloadControllerProvider.overrideWith(
              (ref) => _FakeModelDownloadController(ref: ref),
            ),
          ],
          child: const MaterialApp(home: ModelManagementPage()),
        ),
      );

      await tester.pumpAndSettle();

      final activeChip = chipWithLabel('当前语义模型');
      await scrollUntilFound(tester, activeChip);
      expect(activeChip, findsOneWidget);
    },
  );
}
