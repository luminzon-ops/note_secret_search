import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/logging/app_logger.dart';
import 'package:note_secret_search/features/ai_models/application/model_catalog_providers.dart';
import 'package:note_secret_search/features/ai_models/application/model_download_providers.dart';
import 'package:note_secret_search/features/ai_models/application/model_selection_providers.dart';
import 'package:note_secret_search/features/ai_models/domain/active_model_selection.dart';
import 'package:note_secret_search/features/ai_models/domain/model_catalog_entry.dart';
import 'package:note_secret_search/features/ai_models/domain/model_download_repository.dart';
import 'package:note_secret_search/features/ai_models/domain/model_download_task.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_repository.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/model_download_service.dart';
import 'package:note_secret_search/features/ai_models/presentation/model_management_page.dart';
import 'package:note_secret_search/features/search/domain/embedding_engine.dart';

class _FakeModelDownloadRepository implements ModelDownloadRepository {
  const _FakeModelDownloadRepository();

  @override
  Future<ModelDownloadTask?> findLatestTaskByModel(String modelId) async => null;

  @override
  Future<List<ModelDownloadTask>> listTasks() async => const <ModelDownloadTask>[];

  @override
  Future<void> saveTask(ModelDownloadTask task) async {}
}

class _FakeModelRegistryRepository implements ModelRegistryRepository {
  const _FakeModelRegistryRepository();

  @override
  Future<void> deleteById(String id) async {}

  @override
  Future<ModelRegistryEntry?> getById(String id) async => null;

  @override
  Future<List<ModelRegistryEntry>> listInstalledModels() async => const <ModelRegistryEntry>[];

  @override
  Future<void> save(ModelRegistryEntry entry) async {}
}

class _FakeModelDownloadController extends ModelDownloadController {
  _FakeModelDownloadController({required super.ref})
      : super(
          repository: const _FakeModelDownloadRepository(),
          registryRepository: const _FakeModelRegistryRepository(),
          downloadService: ModelDownloadService(dio: Dio(), logger: const AppLogger()),
          logger: const AppLogger(),
        );
}

void main() {
  Finder chipWithLabel(String label) {
    return find.byWidgetPredicate(
      (widget) =>
          widget is Chip &&
          widget.label is Text &&
          (widget.label as Text).data == label,
      description: 'Chip with label $label',
    );
  }

  testWidgets('ModelManagementPage shows aligned installed model summary and ready deployment status', (
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
                enabled: true,
                installedAt: null,
                filePresent: true,
              ),
            ],
          ),
          activeModelSelectionProvider.overrideWith(
            (ref) async => const ActiveModelSelection(activeEmbeddingModelId: 'embed-1'),
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
      find.text('builtin · embedding · Q8 · 版本 1.0.2 · 10.0 MB · RAM ≥ 512MB · 推荐档位 mvp'),
      findsOneWidget,
    );
    expect(find.text('部署状态：本地已就绪。'), findsOneWidget);
    expect(find.text('当前语义模型'), findsOneWidget);
  });

  testWidgets('ModelManagementPage shows 可下载模型目录 section heading for catalog entries', (
    tester,
  ) async {
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
            (ref) async => const ActiveModelSelection(activeEmbeddingModelId: null),
          ),
          embeddingRuntimeStatesProvider.overrideWith((ref) async => const <String, EmbeddingEngineState>{}),
          modelDownloadControllerProvider.overrideWith(
            (ref) => _FakeModelDownloadController(ref: ref),
          ),
        ],
        child: const MaterialApp(home: ModelManagementPage()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('可下载模型目录'), findsOneWidget);
  });

  testWidgets('ModelManagementPage shows 已安装模型 for an installed but inactive model', (
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
                enabled: true,
                installedAt: null,
                filePresent: true,
              ),
            ],
          ),
          activeModelSelectionProvider.overrideWith(
            (ref) async => const ActiveModelSelection(activeEmbeddingModelId: null),
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
  });

  testWidgets('ModelManagementPage shows degraded deployment status for a missing-file registry entry', (
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
                enabled: true,
                installedAt: null,
                filePresent: false,
              ),
            ],
          ),
          activeModelSelectionProvider.overrideWith(
            (ref) async => const ActiveModelSelection(activeEmbeddingModelId: null),
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
  });

  testWidgets('ModelManagementPage shows runtime unverified status for installed embedding model', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          modelCatalogEntriesProvider.overrideWith((ref) async => const <ModelCatalogEntry>[]),
          modelDownloadTasksProvider.overrideWith((ref) async => const <ModelDownloadTask>[]),
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
            (ref) async => const ActiveModelSelection(activeEmbeddingModelId: null),
          ),
          modelDownloadControllerProvider.overrideWith((ref) => _FakeModelDownloadController(ref: ref)),
        ],
        child: const MaterialApp(home: ModelManagementPage()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('部署状态：本地已安装，但运行时尚未校验。'), findsOneWidget);
    expect(find.text('运行时状态：待校验'), findsOneWidget);
  });

  testWidgets('ModelManagementPage disables semantic activation when embedding runtime is degraded', (
    tester,
  ) async {
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
          modelDownloadTasksProvider.overrideWith((ref) async => const <ModelDownloadTask>[]),
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
                reason: 'runtime broken',
                status: EmbeddingRuntimeStatus.degraded,
              ),
            },
          ),
          activeModelSelectionProvider.overrideWith(
            (ref) async => const ActiveModelSelection(activeEmbeddingModelId: null),
          ),
          modelDownloadControllerProvider.overrideWith((ref) => _FakeModelDownloadController(ref: ref)),
        ],
        child: const MaterialApp(home: ModelManagementPage()),
      ),
    );

    await tester.pumpAndSettle();

    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '设为语义模型'),
    );
    expect(button.onPressed, isNull);
    expect(find.text('运行时状态：运行时异常'), findsWidgets);
  });

  testWidgets('ModelManagementPage catalog entry shows installed deployment status when local file is ready', (
    tester,
  ) async {
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
            (ref) async => const ActiveModelSelection(activeEmbeddingModelId: null),
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

    expect(find.text('部署状态：本地已就绪，可用于后续启用或检索配置。'), findsOneWidget);
    expect(find.text('本地部署已就绪'), findsOneWidget);
  });

  testWidgets('ModelManagementPage catalog chip shows 当前语义模型 for the active embedding model', (
    tester,
  ) async {
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
            (ref) async => const ActiveModelSelection(activeEmbeddingModelId: 'embed-1'),
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

    expect(chipWithLabel('当前语义模型'), findsOneWidget);
  });

  testWidgets('ModelManagementPage shows 下载任务未开始 when no download task exists', (
    tester,
  ) async {
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
            (ref) async => const ActiveModelSelection(activeEmbeddingModelId: null),
          ),
          embeddingRuntimeStatesProvider.overrideWith((ref) async => const <String, EmbeddingEngineState>{}),
          modelDownloadControllerProvider.overrideWith(
            (ref) => _FakeModelDownloadController(ref: ref),
          ),
        ],
        child: const MaterialApp(home: ModelManagementPage()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('下载任务未开始'), findsOneWidget);
  });

  testWidgets('ModelManagementPage shows queued download guidance for queued task', (
    tester,
  ) async {
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
            (ref) async => const ActiveModelSelection(activeEmbeddingModelId: null),
          ),
          embeddingRuntimeStatesProvider.overrideWith((ref) async => const <String, EmbeddingEngineState>{}),
          modelDownloadControllerProvider.overrideWith(
            (ref) => _FakeModelDownloadController(ref: ref),
          ),
        ],
        child: const MaterialApp(home: ModelManagementPage()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('任务状态：队列中'), findsOneWidget);
    expect(find.text('任务说明：已加入下载队列，等待开始下载。'), findsOneWidget);
  });

  testWidgets('ModelManagementPage shows paused download guidance for paused task', (
    tester,
  ) async {
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
            (ref) async => const ActiveModelSelection(activeEmbeddingModelId: null),
          ),
          embeddingRuntimeStatesProvider.overrideWith((ref) async => const <String, EmbeddingEngineState>{}),
          modelDownloadControllerProvider.overrideWith(
            (ref) => _FakeModelDownloadController(ref: ref),
          ),
        ],
        child: const MaterialApp(home: ModelManagementPage()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('任务状态：已暂停'), findsOneWidget);
    expect(find.text('任务说明：下载已暂停，可稍后继续或重新开始。'), findsOneWidget);
  });

  testWidgets('ModelManagementPage shows download speed and resumable support while downloading', (
    tester,
  ) async {
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
            (ref) async => const ActiveModelSelection(activeEmbeddingModelId: null),
          ),
          embeddingRuntimeStatesProvider.overrideWith((ref) async => const <String, EmbeddingEngineState>{}),
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
  });

  testWidgets('ModelManagementPage shows non-resumable hint for failed download task', (
    tester,
  ) async {
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
            (ref) async => const ActiveModelSelection(activeEmbeddingModelId: null),
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
  });

  testWidgets('ModelManagementPage shows download source label and updated time for active task', (
    tester,
  ) async {
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
            (ref) async => const ActiveModelSelection(activeEmbeddingModelId: null),
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
  });
}
