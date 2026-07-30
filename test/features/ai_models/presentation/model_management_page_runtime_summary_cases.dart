part of 'model_management_page_test.dart';

void _registerRuntimeSummaryCases() {
  testWidgets(
    'ModelManagementPage shows corrupted deployment status for a checksum-mismatched model file',
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
                  enabled: false,
                  installedAt: null,
                  filePresent: true,
                  integrityStatus: ModelIntegrityStatus.corrupted,
                ),
              ],
            ),
            embeddingRuntimeStatesProvider.overrideWith(
              (ref) async => {
                'embed-1': const EmbeddingEngineState(
                  ready: false,
                  reason: '本地模型文件校验失败，需要重新下载或修复。',
                  status: EmbeddingRuntimeStatus.corrupted,
                ),
              },
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

      expect(find.text('部署状态：本地文件校验失败，需要重新下载或修复。'), findsOneWidget);
      expect(find.text('运行时状态：文件损坏'), findsOneWidget);
      expect(find.text('本地记录失效'), findsOneWidget);
    },
  );

  testWidgets(
    'ModelManagementPage shows runtime unverified status for installed embedding model',
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
            embeddingRuntimeStatesProvider.overrideWith(
              (ref) async => {
                'embed-1': const EmbeddingEngineState(
                  ready: false,
                  reason: 'waiting verification',
                  status: EmbeddingRuntimeStatus.installedUnverified,
                ),
              },
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

      expect(find.text('部署状态：本地已安装，但运行时尚未校验。'), findsOneWidget);
      expect(find.text('运行时状态：待校验'), findsOneWidget);
    },
  );

  testWidgets(
    'ModelManagementPage disables semantic activation when embedding runtime is degraded',
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
            embeddingRuntimeStatesProvider.overrideWith(
              (ref) async => {
                'embed-1': const EmbeddingEngineState(
                  ready: false,
                  reason: 'runtime broken',
                  status: EmbeddingRuntimeStatus.degraded,
                ),
              },
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

      final buttonFinder = find.widgetWithText(OutlinedButton, '设为语义模型');
      await scrollUntilFound(tester, buttonFinder);
      final button = tester.widget<OutlinedButton>(buttonFinder);
      expect(button.onPressed, isNull);
      expect(find.text('运行时状态：运行时异常'), findsWidgets);
    },
  );
}
