part of 'model_management_page_test.dart';

void _registerSummaryIntroCases() {
  testWidgets(
    'ModelManagementPage shows aligned installed model summary and ready deployment status',
    (tester) async {
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
              (ref) async => const [
                ModelRegistryEntry(
                  id: 'embed-1',
                  type: 'embedding',
                  provider: 'builtin',
                  name: 'MiniLM Embedding',
                  version: '1.0.2',
                  sizeBytes: 10485760,
                  quantization: 'Q8',
                  minRamMb: 512,
                  recommendedTier: 'mvp',
                  localPath: '/data/models/minilm.onnx',
                  checksum: 'abc',
                  enabled: true,
                  installedAt: null,
                  filePresent: true,
                ),
              ],
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

      expect(find.text('设备能力评级'), findsOneWidget);
      expect(find.text('模型下载与本地部署说明'), findsOneWidget);
      expect(find.text('本地已安装模型'), findsOneWidget);
      expect(
        find.text(
          'builtin · embedding · Q8 · 版本 1.0.2 · 10.0 MB · RAM ≥ 512MB · 推荐档位 mvp',
        ),
        findsOneWidget,
      );
      expect(find.text('部署状态：本地已就绪。'), findsOneWidget);
      expect(find.text('当前语义模型'), findsOneWidget);
    },
  );
}

void _registerInstalledSummaryCases() {
  testWidgets(
    'ModelManagementPage shows 已安装模型 for an installed but inactive model',
    (tester) async {
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

      expect(find.text('本地已安装模型'), findsOneWidget);
      expect(find.text('已安装模型'), findsOneWidget);
    },
  );

  testWidgets(
    'ModelManagementPage shows 当前本地LLM for a ready active llm model',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
            modelCatalogEntriesProvider.overrideWith(
              (ref) async => const <ModelCatalogEntry>[],
            ),
            modelDownloadTasksProvider.overrideWith(
              (ref) async => const <ModelDownloadTask>[],
            ),
            modelRegistryEntriesProvider.overrideWith(
              (ref) async => const [
                ModelRegistryEntry(
                  id: 'llm-1',
                  type: 'llm',
                  provider: 'builtin',
                  name: 'Phi Local',
                  version: '1.0.0',
                  sizeBytes: 104857600,
                  quantization: 'Q4_K_M',
                  minRamMb: 2048,
                  recommendedTier: 'local',
                  localPath: '/data/models/phi.gguf',
                  checksum: 'abc',
                  enabled: true,
                  installedAt: null,
                  filePresent: true,
                ),
              ],
            ),
            llmRuntimeStatesProvider.overrideWith(
              (ref) async => {
                'llm-1': const LlmRuntimeState(
                  ready: true,
                  reason: 'ready',
                  status: LlmRuntimeStatus.ready,
                ),
              },
            ),
            embeddingRuntimeStatesProvider.overrideWith(
              (ref) async => const <String, EmbeddingEngineState>{},
            ),
            activeModelSelectionProvider.overrideWith(
              (ref) async =>
                  const ActiveModelSelection(activeEmbeddingModelId: null),
            ),
            activeLocalLlmModelProvider.overrideWith(
              (ref) async => _installedPhiRegistryEntry,
            ),
            modelDownloadControllerProvider.overrideWith(
              (ref) => _FakeModelDownloadController(ref: ref),
            ),
          ],
          child: const MaterialApp(home: ModelManagementPage()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('当前本地LLM'), findsOneWidget);
      expect(find.text('部署状态：本地已就绪，可用于本地问答。'), findsOneWidget);
    },
  );

  testWidgets(
    'ModelManagementPage catalog entry uses llm runtime state for installed unverified llm',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            modelCatalogEntriesProvider.overrideWith(
              (ref) async => const [
                ModelCatalogEntry(
                  id: 'llm-1',
                  type: 'llm',
                  tier: 'local',
                  displayName: 'Qwen Local',
                  description: '用于本地问答。',
                  sizeBytes: 104857600,
                  minRamMb: 2048,
                  recommendedTier: 'local',
                  sources: <ModelSourceEntry>[],
                ),
              ],
            ),
            modelDownloadTasksProvider.overrideWith(
              (ref) async => const <ModelDownloadTask>[],
            ),
            modelRegistryEntriesProvider.overrideWith(
              (ref) async => const [_installedQwenRegistryEntry],
            ),
            llmRuntimeStatesProvider.overrideWith(
              (ref) async => {
                'llm-1': const LlmRuntimeState(
                  ready: false,
                  reason: 'pending validation',
                  status: LlmRuntimeStatus.installedUnverified,
                  modelPath: '/data/models/qwen.gguf',
                ),
              },
            ),
            embeddingRuntimeStatesProvider.overrideWith(
              (ref) async => const <String, EmbeddingEngineState>{},
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

      final deploymentStatus = find.text('部署状态：本地文件已安装，待运行时校验。');
      await scrollUntilFound(tester, deploymentStatus);
      expect(deploymentStatus, findsOneWidget);
      expect(find.text('部署状态：本地记录存在，但文件缺失，需要重新下载。'), findsNothing);
    },
  );

  testWidgets(
    'ModelManagementPage shows degraded deployment status for a missing-file registry entry',
    (tester) async {
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
              (ref) async => const [
                ModelRegistryEntry(
                  id: 'embed-1',
                  type: 'embedding',
                  provider: 'builtin',
                  name: 'MiniLM Embedding',
                  version: '1.0.2',
                  sizeBytes: 10485760,
                  quantization: 'Q8',
                  minRamMb: 512,
                  recommendedTier: 'mvp',
                  localPath: '/data/models/minilm.onnx',
                  checksum: 'abc',
                  enabled: true,
                  installedAt: null,
                  filePresent: false,
                ),
              ],
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

      expect(find.text('部署状态：本地文件缺失，当前记录不可直接使用。'), findsOneWidget);
      expect(find.text('本地记录失效'), findsOneWidget);
    },
  );
}
