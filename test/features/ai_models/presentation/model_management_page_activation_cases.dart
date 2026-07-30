part of 'model_management_page_test.dart';

void _registerActivationCases() {
  testWidgets(
    'ModelManagementPage allows activating a ready installed local llm',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      String? selectedModelId;
      final activation = ModelActivationUseCase(
        setEmbedding: (_) async {},
        setLocalLlm: (modelId) async {
          selectedModelId = modelId;
        },
      );

      await tester.binding.setSurfaceSize(const Size(1000, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWith(
              (ref) async => SharedPreferences.getInstance(),
            ),
            modelCatalogEntriesProvider.overrideWith(
              (ref) async => const [
                ModelCatalogEntry(
                  id: 'llm-1',
                  type: 'llm',
                  tier: 'local',
                  displayName: 'Phi Local',
                  description: '用于本地自由聊天。',
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
              (ref) async => const [_installedPhiRegistryEntry],
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
            modelActivationUseCaseProvider.overrideWithValue(activation),
            modelDownloadControllerProvider.overrideWith(
              (ref) => _FakeModelDownloadController(ref: ref),
            ),
          ],
          child: const MaterialApp(home: ModelManagementPage()),
        ),
      );

      await tester.pumpAndSettle();

      final buttonFinder = find.widgetWithText(OutlinedButton, '设为当前本地LLM');
      await scrollUntilFound(tester, buttonFinder);
      await tester.tap(buttonFinder);
      await tester.pump();

      expect(selectedModelId, 'llm-1');
    },
  );

  testWidgets(
    'ModelManagementPage disables local llm activation when runtime is degraded',
    (tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWith(
              (ref) async => SharedPreferences.getInstance(),
            ),
            modelCatalogEntriesProvider.overrideWith(
              (ref) async => const [
                ModelCatalogEntry(
                  id: 'llm-1',
                  type: 'llm',
                  tier: 'local',
                  displayName: 'Phi Local',
                  description: '用于本地自由聊天。',
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
              (ref) async => const [_installedPhiRegistryEntry],
            ),
            llmRuntimeStatesProvider.overrideWith(
              (ref) async => {
                'llm-1': const LlmRuntimeState(
                  ready: false,
                  reason: 'probe failed',
                  status: LlmRuntimeStatus.degraded,
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

      final buttonFinder = find.widgetWithText(OutlinedButton, '设为当前本地LLM');
      await scrollUntilFound(tester, buttonFinder);
      final button = tester.widget<OutlinedButton>(buttonFinder);
      expect(button.onPressed, isNull);
    },
  );

  testWidgets(
    'ModelManagementPage renders current source and selector in separate vertical sections',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            modelCatalogEntriesProvider.overrideWith(
              (ref) async => const [_bgeEmbeddingCatalogEntry],
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

      // A standalone section header "当前下载源" (not inline with the source label) should exist.
      expect(find.text('当前下载源'), findsOneWidget);
      // The source label appears as separate text from the dropdown.
      // The section header appears as its own widget, and the source label (with trust) also appears.
      expect(
        find.textContaining('HuggingFace Xenova（revision pinned）'),
        findsAtLeast(2),
      );
      // The dropdown for switching sources should be present.
      expect(find.byType(DropdownButton<String>), findsOneWidget);
    },
  );

  testWidgets(
    'ModelManagementPage shows active download status section with compact staged copy',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            modelCatalogEntriesProvider.overrideWith(
              (ref) async => const [_bgeEmbeddingCatalogEntry],
            ),
            modelDownloadTasksProvider.overrideWith(
              (ref) async => [
                ModelDownloadTask(
                  id: 'task-1',
                  modelId: 'bge-small-zh',
                  sourceId: 'hf-xenova-pinned',
                  status: ModelDownloadStatus.downloading,
                  totalBytes: 10485760,
                  downloadedBytes: 0,
                  averageSpeed: null,
                  errorMessage: null,
                  resumable: true,
                  createdAt: DateTime(2026, 5, 2, 10, 0, 0),
                  updatedAt: DateTime(2026, 5, 2, 10, 0, 1),
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

      // A section header "下载状态" should appear (distinct from the old "任务状态：..." wording).
      expect(find.text('下载状态'), findsOneWidget);
      // The compact staged copy "连接中" should be shown for zero-byte downloading task.
      expect(find.textContaining('连接中'), findsOneWidget);
      // The compact progress copy shows downloaded / total bytes.
      expect(find.textContaining('已下载 0 MB / 10 MB'), findsOneWidget);
    },
  );

  testWidgets('stale registry keeps model cleanup retry available', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    late _RecordingModelDownloadController controller;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          modelCatalogEntriesProvider.overrideWith(
            (ref) async => const <ModelCatalogEntry>[_bgeEmbeddingCatalogEntry],
          ),
          modelDownloadTasksProvider.overrideWith(
            (ref) async => const <ModelDownloadTask>[],
          ),
          modelRegistryEntriesProvider.overrideWith(
            (ref) async => const <ModelRegistryEntry>[
              ModelRegistryEntry(
                id: 'bge-small-zh',
                type: 'embedding',
                provider: 'builtin_catalog',
                name: 'BGE Small Chinese',
                version: null,
                sizeBytes: 10,
                quantization: null,
                minRamMb: 512,
                recommendedTier: 'mvp',
                localPath: '/data/models/bge-small-zh/model.onnx',
                checksum: 'sha256:model',
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
    final deleteButton = find.widgetWithText(OutlinedButton, '删除本地模型');
    await scrollUntilFound(tester, deleteButton);

    expect(tester.widget<OutlinedButton>(deleteButton).onPressed, isNotNull);
    await tester.tap(deleteButton);
    await tester.pump();
    expect(controller.deletedModelId, 'bge-small-zh');
  });
}
