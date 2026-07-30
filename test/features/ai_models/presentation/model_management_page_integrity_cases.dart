part of 'model_management_page_test.dart';

void _registerIntegrityCases() {
  group('installed model integrity maintenance', () {
    testWidgets('installed model row exposes 校验 button', (tester) async {
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
            modelDownloadControllerProvider.overrideWith((ref) {
              controller = _RecordingModelDownloadController(ref: ref);
              return controller;
            }),
          ],
          child: const MaterialApp(home: ModelManagementPage()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('校验'), findsOneWidget);
    });

    testWidgets(
      'installed model maintenance actions are rendered outside the ListTile body',
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
                    id: 'llm-1',
                    type: 'llm',
                    provider: 'builtin_catalog',
                    name: 'Qwen Local',
                    version: '1.0.0',
                    sizeBytes: 104857600,
                    quantization: 'Q4_K_M',
                    minRamMb: 2048,
                    recommendedTier: 'local',
                    localPath: '/data/models/qwen.gguf',
                    checksum: 'sha256:qwen',
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
              modelDownloadControllerProvider.overrideWith(
                (ref) => _FakeModelDownloadController(ref: ref),
              ),
            ],
            child: const MaterialApp(home: ModelManagementPage()),
          ),
        );

        await tester.pumpAndSettle();

        final validateButton = find.widgetWithText(OutlinedButton, '校验');
        expect(validateButton, findsOneWidget);
        expect(
          find.ancestor(of: validateButton, matching: find.byType(ListTile)),
          findsNothing,
        );
      },
    );

    testWidgets(
      'healthy installed model row does not expose active 修复 button',
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

        // 修复 button should not appear for healthy models
        expect(find.text('修复'), findsNothing);
      },
    );

    testWidgets('broken installed model row exposes enabled 修复 button', (
      tester,
    ) async {
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
                  filePresent: false,
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
                  ready: false,
                  reason: 'missing',
                  status: EmbeddingRuntimeStatus.missing,
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

      expect(find.text('修复'), findsOneWidget);
      final button = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, '修复'),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('tapping 校验 calls revalidateInstalledModel with model id', (
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
            modelDownloadControllerProvider.overrideWith((ref) {
              controller = _RecordingModelDownloadController(ref: ref);
              return controller;
            }),
          ],
          child: const MaterialApp(home: ModelManagementPage()),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.text('校验'));
      await tester.pumpAndSettle();

      expect(controller.revalidatedModelId, 'embed-1');
    });

    testWidgets('tapping 修复 calls repairInstalledModel with model id', (
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
                  filePresent: false,
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
                  ready: false,
                  reason: 'missing',
                  status: EmbeddingRuntimeStatus.missing,
                ),
              },
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

      await tester.tap(find.text('修复'));
      await tester.pumpAndSettle();

      expect(controller.repairedModelId, 'embed-1');
    });
  });
}
