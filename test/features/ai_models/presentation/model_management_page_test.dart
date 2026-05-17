import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/logging/app_logger.dart';
import 'package:note_secret_search/features/ai_chat/application/llm_runtime_providers.dart';
import 'package:note_secret_search/features/ai_chat/domain/llm_runtime_status.dart';
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
import 'package:note_secret_search/features/settings/application/security_settings_providers.dart';
import 'package:note_secret_search/features/ai_models/presentation/model_management_page.dart';
import 'package:note_secret_search/features/search/domain/embedding_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeModelDownloadRepository implements ModelDownloadRepository {
  const _FakeModelDownloadRepository();

  @override
  Future<ModelDownloadTask?> findLatestTaskByModel(String modelId) async => null;

  @override
  Future<ModelDownloadTask?> findLatestTaskByModelAndSource(String modelId, String sourceId) async => null;

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

class _RecordingModelDownloadController extends _FakeModelDownloadController {
  _RecordingModelDownloadController({required super.ref});

  ModelCatalogEntry? startedEntry;
  ModelSourceEntry? startedSource;
  String? revalidatedModelId;
  String? repairedModelId;

  @override
  Future<void> startDownload({
    required ModelCatalogEntry entry,
    required ModelSourceEntry source,
  }) async {
    startedEntry = entry;
    startedSource = source;
  }

  @override
  Future<void> revalidateInstalledModel(String modelId) async {
    revalidatedModelId = modelId;
  }

  @override
  Future<void> repairInstalledModel(String modelId) async {
    repairedModelId = modelId;
  }
}

class _RecordingActiveLocalLlmSelectionController implements ActiveLocalLlmSelectionController {
  _RecordingActiveLocalLlmSelectionController();

  String? selectedModelId;

  @override
  Future<void> setActiveLocalLlmModel(String? modelId) async {
    selectedModelId = modelId;
  }
}

const _bgeEmbeddingCatalogEntry = ModelCatalogEntry(
  id: 'bge-small-zh',
  type: 'embedding',
  tier: 'mvp',
  displayName: 'BGE Small 中文 Embedding',
  description: '用于本地中文语义检索的 BGE 小型 embedding 模型。',
  sizeBytes: 10485760,
  minRamMb: 512,
  recommendedTier: 'mvp',
  sources: <ModelSourceEntry>[
    ModelSourceEntry(
      id: 'hf-xenova-pinned',
      label: 'HuggingFace Xenova（revision pinned）',
      url: 'https://huggingface.co/Xenova/bge-small-zh-v1.5/resolve/75c43b069aac4d136ba6bc1122f995fedcfd2781/onnx/model.onnx',
      checksum: 'sha256:abc',
      signature: 'signed',
      signatureAlgorithm: 'RSA-SHA256',
      keyId: 'key-1',
    ),
    ModelSourceEntry(
      id: 'hf-xenova-main',
      label: 'HuggingFace Xenova（main fallback）',
      url: 'https://huggingface.co/Xenova/bge-small-zh-v1.5/resolve/main/onnx/model.onnx',
      checksum: 'sha256:def',
    ),
  ],
);

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

  testWidgets('ModelManagementPage shows MiniCPM multimodal artifacts and enabled download action', (
    tester,
  ) async {
    late _RecordingModelDownloadController controller;
    const entry = ModelCatalogEntry(
      id: 'minicpm_v_4_6_q4_k_m',
      type: 'multimodal_llm',
      tier: 'local_multimodal',
      displayName: 'MiniCPM-V 4.6 Q4_K_M Multimodal',
      description: 'Requires LLM GGUF plus mmproj-model-f16.gguf.',
      sizeBytes: 1516275776,
      minRamMb: 6144,
      recommendedTier: 'vision_language_local',
      sources: <ModelSourceEntry>[
        ModelSourceEntry(
          id: 'minicpm-v-4-6-q4-k-m-llm',
          label: 'MiniCPM-V 4.6 Q4_K_M 主模型',
          role: 'model',
          url: 'https://example.com/MiniCPM-V-4_6-Q4_K_M.gguf',
        ),
        ModelSourceEntry(
          id: 'minicpm-v-4-6-mmproj-f16',
          label: 'mmproj-model-f16.gguf',
          role: 'mmproj',
          url: 'https://example.com/mmproj-model-f16.gguf',
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          modelCatalogEntriesProvider.overrideWith((ref) async => const <ModelCatalogEntry>[entry]),
          modelDownloadTasksProvider.overrideWith((ref) async => const <ModelDownloadTask>[]),
          modelRegistryEntriesProvider.overrideWith((ref) async => const <ModelRegistryEntry>[]),
          activeModelSelectionProvider.overrideWith(
            (ref) async => const ActiveModelSelection(activeEmbeddingModelId: null),
          ),
          embeddingRuntimeStatesProvider.overrideWith((ref) async => const <String, EmbeddingEngineState>{}),
          modelDownloadControllerProvider.overrideWith((ref) {
            controller = _RecordingModelDownloadController(ref: ref);
            return controller;
          }),
        ],
        child: const MaterialApp(home: ModelManagementPage()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('主模型：MiniCPM-V 4.6 Q4_K_M 主模型'), findsOneWidget);
    expect(find.text('视觉投影：mmproj-model-f16.gguf'), findsOneWidget);
    expect(find.textContaining('本地多模态推理'), findsOneWidget);
    final startDownload = find.widgetWithText(FilledButton, '开始下载');
    expect(startDownload, findsOneWidget);

    await tester.ensureVisible(startDownload);
    await tester.pumpAndSettle();
    await tester.tap(startDownload);
    await tester.pump();

    expect(controller.startedEntry?.id, 'minicpm_v_4_6_q4_k_m');
    expect(controller.startedSource?.id, 'minicpm-v-4-6-q4-k-m-llm');
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

  testWidgets('ModelManagementPage shows 当前本地LLM for a ready active llm model', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'ai.active_llm_model_id': 'llm-1'});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWith((ref) async => SharedPreferences.getInstance()),
          modelCatalogEntriesProvider.overrideWith((ref) async => const <ModelCatalogEntry>[]),
          modelDownloadTasksProvider.overrideWith((ref) async => const <ModelDownloadTask>[]),
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
          embeddingRuntimeStatesProvider.overrideWith((ref) async => const <String, EmbeddingEngineState>{}),
          activeModelSelectionProvider.overrideWith(
            (ref) async => const ActiveModelSelection(activeEmbeddingModelId: null),
          ),
          modelDownloadControllerProvider.overrideWith((ref) => _FakeModelDownloadController(ref: ref)),
        ],
        child: const MaterialApp(home: ModelManagementPage()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('当前本地LLM'), findsOneWidget);
    expect(find.text('部署状态：本地已就绪，可用于本地问答。'), findsOneWidget);
  });

  testWidgets('ModelManagementPage catalog entry uses llm runtime state for installed unverified llm', (
    tester,
  ) async {
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
          modelDownloadTasksProvider.overrideWith((ref) async => const <ModelDownloadTask>[]),
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
                enabled: false,
                installedAt: null,
                filePresent: true,
              ),
            ],
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
          embeddingRuntimeStatesProvider.overrideWith((ref) async => const <String, EmbeddingEngineState>{}),
          activeModelSelectionProvider.overrideWith(
            (ref) async => const ActiveModelSelection(activeEmbeddingModelId: null),
          ),
          modelDownloadControllerProvider.overrideWith((ref) => _FakeModelDownloadController(ref: ref)),
        ],
        child: const MaterialApp(home: ModelManagementPage()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('部署状态：本地文件已安装，待运行时校验。'), findsOneWidget);
    expect(find.text('部署状态：本地记录存在，但文件缺失，需要重新下载。'), findsNothing);
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

  testWidgets('ModelManagementPage shows corrupted deployment status for a checksum-mismatched model file', (
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

    expect(find.text('部署状态：本地文件校验失败，需要重新下载或修复。'), findsOneWidget);
    expect(find.text('运行时状态：文件损坏'), findsOneWidget);
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

    expect(find.text('任务说明：下载已暂停，可稍后继续或重新开始。'), findsOneWidget);
  });

  testWidgets('ModelManagementPage shows 继续下载 with visible paused progress copy for resumable paused task', (
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

    expect(find.text('下载进度：50%'), findsOneWidget);
    expect(find.text('继续下载'), findsOneWidget);
    expect(find.text('开始下载'), findsNothing);
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

  testWidgets('ModelManagementPage shows 开始下载 for zero-byte paused task (action-hole regression)', (
    tester,
  ) async {
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

    // Must show 开始下载 — this is the action-hole regression
    expect(find.text('开始下载'), findsOneWidget);
    expect(find.text('继续下载'), findsNothing);
  });

  testWidgets('ModelManagementPage shows 开始下载 for zero-byte queued task (action-hole regression)', (
    tester,
  ) async {
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

    // Must show 开始下载 — zero-byte queued should fall back to start, not strand user
    expect(find.text('开始下载'), findsOneWidget);
    expect(find.text('继续下载'), findsNothing);
  });

  testWidgets('ModelManagementPage keeps 重试下载 for failed non-resumable task and hides 开始下载', (
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
    expect(find.text('重试下载'), findsOneWidget);
    expect(find.text('开始下载'), findsNothing);
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

  testWidgets('ModelManagementPage lets the user switch the selected download source', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

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
          modelDownloadTasksProvider.overrideWith((ref) async => const <ModelDownloadTask>[]),
          modelRegistryEntriesProvider.overrideWith((ref) async => const <ModelRegistryEntry>[]),
          activeModelSelectionProvider.overrideWith(
            (ref) async => const ActiveModelSelection(activeEmbeddingModelId: null),
          ),
          embeddingRuntimeStatesProvider.overrideWith((ref) async => const <String, EmbeddingEngineState>{}),
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

    final dropdownFinder = find.byType(DropdownButton<String>).first;
    await tester.scrollUntilVisible(dropdownFinder, 200);
    await tester.tap(dropdownFinder);
    await tester.pumpAndSettle();
    await tester.tap(find.text('备用镜像').last);
    await tester.pumpAndSettle();

    // After switching, the source label updates and dropdown item is selected.
    expect(find.textContaining('备用镜像'), findsAtLeast(1));
  });

  testWidgets('ModelManagementPage starts download with the selected source', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

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
          modelDownloadTasksProvider.overrideWith((ref) async => const <ModelDownloadTask>[]),
          modelRegistryEntriesProvider.overrideWith((ref) async => const <ModelRegistryEntry>[]),
          activeModelSelectionProvider.overrideWith(
            (ref) async => const ActiveModelSelection(activeEmbeddingModelId: null),
          ),
          embeddingRuntimeStatesProvider.overrideWith((ref) async => const <String, EmbeddingEngineState>{}),
          modelDownloadControllerProvider.overrideWith((ref) {
            controller = _RecordingModelDownloadController(ref: ref);
            return controller;
          }),
        ],
        child: const MaterialApp(home: ModelManagementPage()),
      ),
    );

    await tester.pumpAndSettle();

    final dropdownFinder = find.byType(DropdownButton<String>).first;
    await tester.scrollUntilVisible(dropdownFinder, 200);
    await tester.tap(dropdownFinder);
    await tester.pumpAndSettle();
    await tester.tap(find.text('备用镜像').last);
    await tester.pumpAndSettle();

    final downloadButtonFinder = find.text('开始下载');
    await tester.scrollUntilVisible(downloadButtonFinder, 200);
    await tester.tap(downloadButtonFinder);
    await tester.pumpAndSettle();

    expect(controller.startedSource?.id, 'source-b');
    expect(controller.startedSource?.label, '备用镜像');
  });

  testWidgets('ModelManagementPage prefers active downloading task over stale failed task from another source', (
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
          modelRegistryEntriesProvider.overrideWith((ref) async => const <ModelRegistryEntry>[]),
          activeModelSelectionProvider.overrideWith(
            (ref) async => const ActiveModelSelection(activeEmbeddingModelId: null),
          ),
          embeddingRuntimeStatesProvider.overrideWith((ref) async => const <String, EmbeddingEngineState>{}),
          modelDownloadControllerProvider.overrideWith((ref) => _FakeModelDownloadController(ref: ref)),
        ],
        child: const MaterialApp(home: ModelManagementPage()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('当前来源：备用镜像'), findsOneWidget);
    expect(find.text('source-a failed'), findsNothing);
  });

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

    testWidgets('installed model maintenance actions are rendered outside the ListTile body', (tester) async {
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
              (ref) async => const ActiveModelSelection(activeEmbeddingModelId: null),
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
            embeddingRuntimeStatesProvider.overrideWith((ref) async => const <String, EmbeddingEngineState>{}),
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
    });

    testWidgets('healthy installed model row does not expose active 修复 button', (tester) async {
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

      // 修复 button should not appear for healthy models
      expect(find.text('修复'), findsNothing);
    });

    testWidgets('broken installed model row exposes enabled 修复 button', (tester) async {
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
              (ref) async => const ActiveModelSelection(activeEmbeddingModelId: null),
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
      final button = tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '修复'));
      expect(button.onPressed, isNotNull);
    });

    testWidgets('tapping 校验 calls revalidateInstalledModel with model id', (tester) async {
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

    testWidgets('tapping 修复 calls repairInstalledModel with model id', (tester) async {
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
              (ref) async => const ActiveModelSelection(activeEmbeddingModelId: null),
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

  testWidgets('catalog source list uses formatSourceLabelWithTrust for source titles and removes duplicate trailing trust hint', (
    tester,
  ) async {
    // Milestone 6: 推荐来源 ListTile rows should use formatSourceLabelWithTrust for title.
    // The trust suffix "(已签名)" moves into the title; the standalone trailing "已签名" is removed.
    // This avoids showing trust twice in the same row.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          modelCatalogEntriesProvider.overrideWith(
            (ref) async => const [
              ModelCatalogEntry(
                id: 'trust-model-1',
                type: 'embedding',
                tier: 'mvp',
                displayName: 'Signed Embedding Model',
                description: 'A model with artifact trust declaration.',
                sizeBytes: 10485760,
                minRamMb: 512,
                recommendedTier: 'mvp',
                sources: <ModelSourceEntry>[
                  ModelSourceEntry(
                    id: 'trust-source-1',
                    label: 'Signed Source',
                    url: 'https://example.com/signed.onnx',
                    checksum: 'sha256:signed123',
                    signature: 'base64:signedsig==',
                    signatureAlgorithm: 'RSA-SHA256',
                    keyId: 'signer-key-1',
                  ),
                  ModelSourceEntry(
                    id: 'trust-source-2',
                    label: 'Unsigned Source',
                    url: 'https://example.com/unsigned.onnx',
                    checksum: 'sha256:unsigned123',
                  ),
                ],
              ),
            ],
          ),
          modelDownloadTasksProvider.overrideWith((ref) async => const <ModelDownloadTask>[]),
          modelRegistryEntriesProvider.overrideWith((ref) async => const <ModelRegistryEntry>[]),
          activeModelSelectionProvider.overrideWith(
            (ref) async => const ActiveModelSelection(activeEmbeddingModelId: null),
          ),
          embeddingRuntimeStatesProvider.overrideWith((ref) async => const <String, EmbeddingEngineState>{}),
          modelDownloadControllerProvider.overrideWith((ref) => _FakeModelDownloadController(ref: ref)),
        ],
        child: const MaterialApp(home: ModelManagementPage()),
      ),
    );

    await tester.pumpAndSettle();

    // Verify the 推荐来源 section renders
    expect(find.text('推荐来源'), findsOneWidget);

    // Title uses formatSourceLabelWithTrust: signed source shows trust suffix in title.
    // Multiple widgets may show the trust label (dropdown + list tile title) — verify at least one.
    expect(find.text('Signed Source (已签名)'), findsWidgets);
    // Unsigned source remains plain (no trust suffix in title)
    expect(find.text('Unsigned Source'), findsWidgets);

    // The standalone trailing "已签名" text is removed from the ListTile row.
    // Trust is now only shown in the title, not as a separate trailing widget.
    // We verify the old duplicate pattern is gone by checking the row does not contain
    // a standalone "已签名" after the title (only the download-status text remains in trailing).
    expect(find.text('已签名'), findsNothing);
  });

  testWidgets('current-source text shows trust suffix for signed source', (tester) async {
    // This test verifies Milestone 6: signed sources show trust hint in selector/current-source text
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          modelCatalogEntriesProvider.overrideWith(
            (ref) async => const [
              ModelCatalogEntry(
                id: 'trust-model-1',
                type: 'embedding',
                tier: 'mvp',
                displayName: 'Signed Embedding Model',
                description: 'A model with artifact trust declaration.',
                sizeBytes: 10485760,
                minRamMb: 512,
                recommendedTier: 'mvp',
                sources: <ModelSourceEntry>[
                  ModelSourceEntry(
                    id: 'trust-source-1',
                    label: 'Signed Source',
                    url: 'https://example.com/signed.onnx',
                    checksum: 'sha256:signed123',
                    signature: 'base64:signedsig==',
                    signatureAlgorithm: 'RSA-SHA256',
                    keyId: 'signer-key-1',
                  ),
                ],
              ),
            ],
          ),
          modelDownloadTasksProvider.overrideWith((ref) async => const <ModelDownloadTask>[]),
          modelRegistryEntriesProvider.overrideWith((ref) async => const <ModelRegistryEntry>[]),
          activeModelSelectionProvider.overrideWith(
            (ref) async => const ActiveModelSelection(activeEmbeddingModelId: null),
          ),
          embeddingRuntimeStatesProvider.overrideWith((ref) async => const <String, EmbeddingEngineState>{}),
          modelDownloadControllerProvider.overrideWith((ref) => _FakeModelDownloadController(ref: ref)),
        ],
        child: const MaterialApp(home: ModelManagementPage()),
      ),
    );

    await tester.pumpAndSettle();

    // The section header appears, and the source label appears.
    expect(find.textContaining('Signed Source (已签名)'), findsAtLeast(2));
  });

  testWidgets('current-source text shows no trust suffix for unsigned source', (tester) async {
    // Unsigned sources should NOT show trust hint in selector/current-source text
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          modelCatalogEntriesProvider.overrideWith(
            (ref) async => const [
              ModelCatalogEntry(
                id: 'unsigned-model-1',
                type: 'embedding',
                tier: 'mvp',
                displayName: 'Unsigned Embedding Model',
                description: 'A model without artifact trust declaration.',
                sizeBytes: 10485760,
                minRamMb: 512,
                recommendedTier: 'mvp',
                sources: <ModelSourceEntry>[
                  ModelSourceEntry(
                    id: 'unsigned-source-1',
                    label: 'Unsigned Source',
                    url: 'https://example.com/unsigned.onnx',
                    checksum: 'sha256:unsigned123',
                  ),
                ],
              ),
            ],
          ),
          modelDownloadTasksProvider.overrideWith((ref) async => const <ModelDownloadTask>[]),
          modelRegistryEntriesProvider.overrideWith((ref) async => const <ModelRegistryEntry>[]),
          activeModelSelectionProvider.overrideWith(
            (ref) async => const ActiveModelSelection(activeEmbeddingModelId: null),
          ),
          embeddingRuntimeStatesProvider.overrideWith((ref) async => const <String, EmbeddingEngineState>{}),
          modelDownloadControllerProvider.overrideWith((ref) => _FakeModelDownloadController(ref: ref)),
        ],
        child: const MaterialApp(home: ModelManagementPage()),
      ),
    );

    await tester.pumpAndSettle();

    // The section header "当前下载源" appears.
    expect(find.text('当前下载源'), findsOneWidget);
    // Source label text (no trust suffix) appears.
    expect(find.text('Unsigned Source'), findsAtLeast(1));
    // It should NOT include trust indicator (已签名) anywhere.
    expect(find.textContaining('已签名'), findsNothing);
  });

  testWidgets('dropdown item shows trust suffix for signed source in selector', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          modelCatalogEntriesProvider.overrideWith(
            (ref) async => const [
              ModelCatalogEntry(
                id: 'trust-model-1',
                type: 'embedding',
                tier: 'mvp',
                displayName: 'Signed Embedding Model',
                description: 'A model with artifact trust declaration.',
                sizeBytes: 10485760,
                minRamMb: 512,
                recommendedTier: 'mvp',
                sources: <ModelSourceEntry>[
                  ModelSourceEntry(
                    id: 'signed-source',
                    label: 'Signed Source',
                    url: 'https://example.com/signed.onnx',
                    checksum: 'sha256:signed123',
                    signature: 'base64:signedsig==',
                    signatureAlgorithm: 'RSA-SHA256',
                    keyId: 'signer-key-1',
                  ),
                  ModelSourceEntry(
                    id: 'unsigned-source',
                    label: 'Unsigned Source',
                    url: 'https://example.com/unsigned.onnx',
                    checksum: 'sha256:unsigned123',
                  ),
                ],
              ),
            ],
          ),
          modelDownloadTasksProvider.overrideWith((ref) async => const <ModelDownloadTask>[]),
          modelRegistryEntriesProvider.overrideWith((ref) async => const <ModelRegistryEntry>[]),
          activeModelSelectionProvider.overrideWith(
            (ref) async => const ActiveModelSelection(activeEmbeddingModelId: null),
          ),
          embeddingRuntimeStatesProvider.overrideWith((ref) async => const <String, EmbeddingEngineState>{}),
          modelDownloadControllerProvider.overrideWith((ref) => _FakeModelDownloadController(ref: ref)),
        ],
        child: const MaterialApp(home: ModelManagementPage()),
      ),
    );

    await tester.pumpAndSettle();

    // Open dropdown
    final dropdownFinder = find.byType(DropdownButton<String>).first;
    await tester.scrollUntilVisible(dropdownFinder, 200);
    await tester.tap(dropdownFinder);
    await tester.pumpAndSettle();

    // Signed source in dropdown should show trust suffix (may appear multiple times in dropdown overlay)
    final signedItemFinder = find.textContaining(RegExp(r'Signed Source.*已签名'));
    expect(signedItemFinder, findsWidgets);
    // Unsigned source in dropdown should NOT show trust suffix
    final unsignedItemWithTrust = find.textContaining(RegExp(r'Unsigned Source.*已签名'));
    expect(unsignedItemWithTrust, findsNothing);
  });

  testWidgets('catalog entry shows trust explainer caption when at least one source declares artifact trust', (
    tester,
  ) async {
    // When a catalog entry has at least one source that declares artifact trust,
    // an explanatory caption about "已签名" meaning should appear near the source selector area.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          modelCatalogEntriesProvider.overrideWith(
            (ref) async => const [
              ModelCatalogEntry(
                id: 'trust-model-1',
                type: 'embedding',
                tier: 'mvp',
                displayName: 'Signed Embedding Model',
                description: 'A model with artifact trust declaration.',
                sizeBytes: 10485760,
                minRamMb: 512,
                recommendedTier: 'mvp',
                sources: <ModelSourceEntry>[
                  ModelSourceEntry(
                    id: 'trust-source-1',
                    label: 'Signed Source',
                    url: 'https://example.com/signed.onnx',
                    checksum: 'sha256:signed123',
                    signature: 'base64:signedsig==',
                    signatureAlgorithm: 'RSA-SHA256',
                    keyId: 'signer-key-1',
                  ),
                  ModelSourceEntry(
                    id: 'unsigned-source-2',
                    label: 'Unsigned Source',
                    url: 'https://example.com/unsigned.onnx',
                    checksum: 'sha256:unsigned123',
                  ),
                ],
              ),
            ],
          ),
          modelDownloadTasksProvider.overrideWith((ref) async => const <ModelDownloadTask>[]),
          modelRegistryEntriesProvider.overrideWith((ref) async => const <ModelRegistryEntry>[]),
          activeModelSelectionProvider.overrideWith(
            (ref) async => const ActiveModelSelection(activeEmbeddingModelId: null),
          ),
          embeddingRuntimeStatesProvider.overrideWith((ref) async => const <String, EmbeddingEngineState>{}),
          modelDownloadControllerProvider.overrideWith((ref) => _FakeModelDownloadController(ref: ref)),
        ],
        child: const MaterialApp(home: ModelManagementPage()),
      ),
    );

    await tester.pumpAndSettle();

    // The trust explainer caption must appear because at least one source declares artifact trust.
    // The copy clarifies that "已签名" only means the source declares signature metadata
    // and the current version has not completed signature verification.
    expect(
      find.textContaining(RegExp(r'已签名.*仅表示|说明：.*已签名')),
      findsOneWidget,
    );
  });

  testWidgets('ModelManagementPage shows trust-aware source label in status card for signed source', (
    tester,
  ) async {
    // Milestone 6: The status card's "当前来源：..." line should show trust suffix for signed sources.
    // This mirrors the selector/current-source trust behavior.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          modelCatalogEntriesProvider.overrideWith(
            (ref) async => const [
              ModelCatalogEntry(
                id: 'trust-model-1',
                type: 'embedding',
                tier: 'mvp',
                displayName: 'Signed Embedding Model',
                description: 'A model with artifact trust declaration.',
                sizeBytes: 10485760,
                minRamMb: 512,
                recommendedTier: 'mvp',
                sources: <ModelSourceEntry>[
                  ModelSourceEntry(
                    id: 'signed-source-1',
                    label: 'Signed Mirror',
                    url: 'https://example.com/signed.onnx',
                    checksum: 'sha256:signed123',
                    signature: 'base64:signedsig==',
                    signatureAlgorithm: 'RSA-SHA256',
                    keyId: 'signer-key-1',
                  ),
                ],
              ),
            ],
          ),
          modelDownloadTasksProvider.overrideWith(
            (ref) async => [
              ModelDownloadTask(
                id: 'task-1',
                modelId: 'trust-model-1',
                sourceId: 'signed-source-1',
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
          modelRegistryEntriesProvider.overrideWith((ref) async => const <ModelRegistryEntry>[]),
          activeModelSelectionProvider.overrideWith(
            (ref) async => const ActiveModelSelection(activeEmbeddingModelId: null),
          ),
          embeddingRuntimeStatesProvider.overrideWith((ref) async => const <String, EmbeddingEngineState>{}),
          modelDownloadControllerProvider.overrideWith((ref) => _FakeModelDownloadController(ref: ref)),
        ],
        child: const MaterialApp(home: ModelManagementPage()),
      ),
    );

    await tester.pumpAndSettle();

    // The status card source label must include trust suffix for signed source
    expect(find.text('当前来源：Signed Mirror (已签名)'), findsOneWidget);
    // Plain label without trust suffix should NOT appear
    expect(find.text('当前来源：Signed Mirror'), findsNothing);
  });

  testWidgets('ModelManagementPage shows plain source label in status card for unsigned source', (
    tester,
  ) async {
    // Unsigned sources should NOT show trust suffix in status card
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          modelCatalogEntriesProvider.overrideWith(
            (ref) async => const [
              ModelCatalogEntry(
                id: 'unsigned-model-1',
                type: 'embedding',
                tier: 'mvp',
                displayName: 'Unsigned Embedding Model',
                description: 'A model without artifact trust.',
                sizeBytes: 10485760,
                minRamMb: 512,
                recommendedTier: 'mvp',
                sources: <ModelSourceEntry>[
                  ModelSourceEntry(
                    id: 'unsigned-source-1',
                    label: 'Unsigned Mirror',
                    url: 'https://example.com/unsigned.onnx',
                    checksum: 'sha256:unsigned123',
                  ),
                ],
              ),
            ],
          ),
          modelDownloadTasksProvider.overrideWith(
            (ref) async => [
              ModelDownloadTask(
                id: 'task-1',
                modelId: 'unsigned-model-1',
                sourceId: 'unsigned-source-1',
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
          modelRegistryEntriesProvider.overrideWith((ref) async => const <ModelRegistryEntry>[]),
          activeModelSelectionProvider.overrideWith(
            (ref) async => const ActiveModelSelection(activeEmbeddingModelId: null),
          ),
          embeddingRuntimeStatesProvider.overrideWith((ref) async => const <String, EmbeddingEngineState>{}),
          modelDownloadControllerProvider.overrideWith((ref) => _FakeModelDownloadController(ref: ref)),
        ],
        child: const MaterialApp(home: ModelManagementPage()),
      ),
    );

    await tester.pumpAndSettle();

    // The status card source label for unsigned source should NOT include trust suffix
    expect(find.text('当前来源：Unsigned Mirror'), findsOneWidget);
    expect(find.textContaining('当前来源：Unsigned Mirror (已签名)'), findsNothing);
  });

  group('local contextual trust caption for current effective source', () {
    testWidgets('shows local trust caption below source selector when effective source is signed', (
      tester,
    ) async {
      // Milestone 6: When the current/effective source declares artifact trust,
      // a local contextual caption appears directly below the source selector row.
      // This caption is tied to the current source, distinct from the generic explainer.
      // The caption should be a concise Chinese note about the current source's trust status.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            modelCatalogEntriesProvider.overrideWith(
              (ref) async => const [
                ModelCatalogEntry(
                  id: 'trust-model-1',
                  type: 'embedding',
                  tier: 'mvp',
                  displayName: 'Signed Model',
                  description: 'Model with signed source.',
                  sizeBytes: 10485760,
                  minRamMb: 512,
                  recommendedTier: 'mvp',
                  sources: <ModelSourceEntry>[
                    ModelSourceEntry(
                      id: 'signed-src',
                      label: 'Signed Mirror',
                      url: 'https://example.com/signed.onnx',
                      checksum: 'sha256:signed',
                      signature: 'base64:sig',
                      signatureAlgorithm: 'RSA-SHA256',
                      keyId: 'key-1',
                    ),
                  ],
                ),
              ],
            ),
            modelDownloadTasksProvider.overrideWith((ref) async => const <ModelDownloadTask>[]),
            modelRegistryEntriesProvider.overrideWith((ref) async => const <ModelRegistryEntry>[]),
            activeModelSelectionProvider.overrideWith(
              (ref) async => const ActiveModelSelection(activeEmbeddingModelId: null),
            ),
            embeddingRuntimeStatesProvider.overrideWith((ref) async => const <String, EmbeddingEngineState>{}),
            modelDownloadControllerProvider.overrideWith((ref) => _FakeModelDownloadController(ref: ref)),
          ],
          child: const MaterialApp(home: ModelManagementPage()),
        ),
      );

      await tester.pumpAndSettle();

      // The local trust caption should appear as a concise Chinese note tied to current source.
      // Expected caption: "已签名来源声明" or similar - short, local to current source.
      // This is distinct from the generic explainer which contains "仅表示" and "不代表".
      expect(find.text('已签名来源声明'), findsOneWidget);
    });

    testWidgets('omits local trust caption when effective source is unsigned', (
      tester,
    ) async {
      // When the current/effective source does NOT declare artifact trust,
      // no local trust caption should appear below the source selector.
      // The generic explainer (if any) explains trust for other sources.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            modelCatalogEntriesProvider.overrideWith(
              (ref) async => const [
                ModelCatalogEntry(
                  id: 'unsigned-model-1',
                  type: 'embedding',
                  tier: 'mvp',
                  displayName: 'Unsigned Model',
                  description: 'Model with unsigned source.',
                  sizeBytes: 10485760,
                  minRamMb: 512,
                  recommendedTier: 'mvp',
                  sources: <ModelSourceEntry>[
                    ModelSourceEntry(
                      id: 'unsigned-src',
                      label: 'Plain Mirror',
                      url: 'https://example.com/unsigned.onnx',
                      checksum: 'sha256:unsigned',
                    ),
                  ],
                ),
              ],
            ),
            modelDownloadTasksProvider.overrideWith((ref) async => const <ModelDownloadTask>[]),
            modelRegistryEntriesProvider.overrideWith((ref) async => const <ModelRegistryEntry>[]),
            activeModelSelectionProvider.overrideWith(
              (ref) async => const ActiveModelSelection(activeEmbeddingModelId: null),
            ),
            embeddingRuntimeStatesProvider.overrideWith((ref) async => const <String, EmbeddingEngineState>{}),
            modelDownloadControllerProvider.overrideWith((ref) => _FakeModelDownloadController(ref: ref)),
          ],
          child: const MaterialApp(home: ModelManagementPage()),
        ),
      );

      await tester.pumpAndSettle();

      // The local trust caption should NOT appear for unsigned source
      expect(find.text('已签名来源声明'), findsNothing);
    });

    testWidgets('shows local caption for current signed source alongside generic explainer for mixed sources', (
      tester,
    ) async {
      // When there are multiple sources and the current one is signed,
      // both the local caption (for current) and generic explainer (for any signed) should appear.
      // The local caption is tied to current source; generic explains broader context.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            modelCatalogEntriesProvider.overrideWith(
              (ref) async => const [
                ModelCatalogEntry(
                  id: 'mixed-model',
                  type: 'embedding',
                  tier: 'mvp',
                  displayName: 'Mixed Trust Model',
                  description: 'Model with mixed sources.',
                  sizeBytes: 10485760,
                  minRamMb: 512,
                  recommendedTier: 'mvp',
                  sources: <ModelSourceEntry>[
                    ModelSourceEntry(
                      id: 'signed-src',
                      label: 'Signed Mirror',
                      url: 'https://example.com/signed.onnx',
                      checksum: 'sha256:signed',
                      signature: 'base64:sig',
                      signatureAlgorithm: 'RSA-SHA256',
                      keyId: 'key-1',
                    ),
                    ModelSourceEntry(
                      id: 'unsigned-src',
                      label: 'Unsigned Mirror',
                      url: 'https://example.com/unsigned.onnx',
                      checksum: 'sha256:unsigned',
                    ),
                  ],
                ),
              ],
            ),
            modelDownloadTasksProvider.overrideWith((ref) async => const <ModelDownloadTask>[]),
            modelRegistryEntriesProvider.overrideWith((ref) async => const <ModelRegistryEntry>[]),
            activeModelSelectionProvider.overrideWith(
              (ref) async => const ActiveModelSelection(activeEmbeddingModelId: null),
            ),
            embeddingRuntimeStatesProvider.overrideWith((ref) async => const <String, EmbeddingEngineState>{}),
            modelDownloadControllerProvider.overrideWith((ref) => _FakeModelDownloadController(ref: ref)),
          ],
          child: const MaterialApp(home: ModelManagementPage()),
        ),
      );

      await tester.pumpAndSettle();

      // Local caption appears for current (signed) source
      expect(find.text('已签名来源声明'), findsOneWidget);
      // Generic explainer also appears (explains trust for any signed source)
      expect(find.textContaining(RegExp(r'已签名仅表示来源')), findsOneWidget);
    });
  });

  group('Milestone 6b: trust caption deduplication — single signed source hides generic explainer', () {
    testWidgets('(a) single signed source → shows only local caption, hides generic explainer', (
      tester,
    ) async {
      // When an entry has exactly ONE source and that source is signed,
      // the UI should show only the short local caption ("已签名来源声明")
      // and suppress the generic explainer to avoid redundant copy.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            modelCatalogEntriesProvider.overrideWith(
              (ref) async => const [
                ModelCatalogEntry(
                  id: 'single-signed-model',
                  type: 'embedding',
                  tier: 'mvp',
                  displayName: 'Single Signed Model',
                  description: 'Model with one signed source.',
                  sizeBytes: 10485760,
                  minRamMb: 512,
                  recommendedTier: 'mvp',
                  sources: <ModelSourceEntry>[
                    ModelSourceEntry(
                      id: 'single-signed-src',
                      label: 'Signed Only Source',
                      url: 'https://example.com/signed.onnx',
                      checksum: 'sha256:signed',
                      signature: 'base64:sig',
                      signatureAlgorithm: 'RSA-SHA256',
                      keyId: 'key-1',
                    ),
                  ],
                ),
              ],
            ),
            modelDownloadTasksProvider.overrideWith((ref) async => const <ModelDownloadTask>[]),
            modelRegistryEntriesProvider.overrideWith((ref) async => const <ModelRegistryEntry>[]),
            activeModelSelectionProvider.overrideWith(
              (ref) async => const ActiveModelSelection(activeEmbeddingModelId: null),
            ),
            embeddingRuntimeStatesProvider.overrideWith((ref) async => const <String, EmbeddingEngineState>{}),
            modelDownloadControllerProvider.overrideWith((ref) => _FakeModelDownloadController(ref: ref)),
          ],
          child: const MaterialApp(home: ModelManagementPage()),
        ),
      );

      await tester.pumpAndSettle();

      // Local caption shows for the signed source
      expect(find.text('已签名来源声明'), findsOneWidget);
      // Generic explainer is HIDDEN in the single-signed-source case
      expect(find.textContaining(RegExp(r'已签名仅表示来源')), findsNothing);
    });

    testWidgets('(b) multiple sources with at least one signed → generic explainer shown', (
      tester,
    ) async {
      // When multiple sources exist and at least one is signed,
      // the generic explainer should appear (even though only one is signed).
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            modelCatalogEntriesProvider.overrideWith(
              (ref) async => const [
                ModelCatalogEntry(
                  id: 'multi-source-model',
                  type: 'embedding',
                  tier: 'mvp',
                  displayName: 'Multi Source Model',
                  description: 'Model with multiple sources.',
                  sizeBytes: 10485760,
                  minRamMb: 512,
                  recommendedTier: 'mvp',
                  sources: <ModelSourceEntry>[
                    ModelSourceEntry(
                      id: 'signed-src',
                      label: 'Signed Source',
                      url: 'https://example.com/signed.onnx',
                      checksum: 'sha256:signed',
                      signature: 'base64:sig',
                      signatureAlgorithm: 'RSA-SHA256',
                      keyId: 'key-1',
                    ),
                    ModelSourceEntry(
                      id: 'unsigned-src',
                      label: 'Unsigned Source',
                      url: 'https://example.com/unsigned.onnx',
                      checksum: 'sha256:unsigned',
                    ),
                  ],
                ),
              ],
            ),
            modelDownloadTasksProvider.overrideWith((ref) async => const <ModelDownloadTask>[]),
            modelRegistryEntriesProvider.overrideWith((ref) async => const <ModelRegistryEntry>[]),
            activeModelSelectionProvider.overrideWith(
              (ref) async => const ActiveModelSelection(activeEmbeddingModelId: null),
            ),
            embeddingRuntimeStatesProvider.overrideWith((ref) async => const <String, EmbeddingEngineState>{}),
            modelDownloadControllerProvider.overrideWith((ref) => _FakeModelDownloadController(ref: ref)),
          ],
          child: const MaterialApp(home: ModelManagementPage()),
        ),
      );

      await tester.pumpAndSettle();

      // Generic explainer must appear in multi-source case
      expect(find.textContaining(RegExp(r'已签名仅表示来源')), findsOneWidget);
    });

    testWidgets('(c) mixed sources, effective signed → both local caption AND generic explainer', (
      tester,
    ) async {
      // When the effective/current source is signed in a mixed-source entry,
      // BOTH the short local caption and the generic explainer should appear.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            modelCatalogEntriesProvider.overrideWith(
              (ref) async => const [
                ModelCatalogEntry(
                  id: 'mixed-model',
                  type: 'embedding',
                  tier: 'mvp',
                  displayName: 'Mixed Trust Model',
                  description: 'Model with mixed sources.',
                  sizeBytes: 10485760,
                  minRamMb: 512,
                  recommendedTier: 'mvp',
                  sources: <ModelSourceEntry>[
                    ModelSourceEntry(
                      id: 'signed-src',
                      label: 'Signed Mirror',
                      url: 'https://example.com/signed.onnx',
                      checksum: 'sha256:signed',
                      signature: 'base64:sig',
                      signatureAlgorithm: 'RSA-SHA256',
                      keyId: 'key-1',
                    ),
                    ModelSourceEntry(
                      id: 'unsigned-src',
                      label: 'Unsigned Mirror',
                      url: 'https://example.com/unsigned.onnx',
                      checksum: 'sha256:unsigned',
                    ),
                  ],
                ),
              ],
            ),
            modelDownloadTasksProvider.overrideWith((ref) async => const <ModelDownloadTask>[]),
            modelRegistryEntriesProvider.overrideWith((ref) async => const <ModelRegistryEntry>[]),
            activeModelSelectionProvider.overrideWith(
              (ref) async => const ActiveModelSelection(activeEmbeddingModelId: null),
            ),
            embeddingRuntimeStatesProvider.overrideWith((ref) async => const <String, EmbeddingEngineState>{}),
            modelDownloadControllerProvider.overrideWith((ref) => _FakeModelDownloadController(ref: ref)),
          ],
          child: const MaterialApp(home: ModelManagementPage()),
        ),
      );

      await tester.pumpAndSettle();

      // Both captions appear in this case
      expect(find.text('已签名来源声明'), findsOneWidget);
      expect(find.textContaining(RegExp(r'已签名仅表示来源')), findsOneWidget);
    });

    testWidgets('(d) effective unsigned but another source signed → ONLY generic explainer', (
      tester,
    ) async {
      // When the effective/current source is unsigned but another source is signed,
      // ONLY the generic explainer should appear (no local caption since current is unsigned).
      await tester.binding.setSurfaceSize(const Size(1000, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            modelCatalogEntriesProvider.overrideWith(
              (ref) async => const [
                ModelCatalogEntry(
                  id: 'mixed-model',
                  type: 'embedding',
                  tier: 'mvp',
                  displayName: 'Mixed Trust Model',
                  description: 'Model with mixed sources.',
                  sizeBytes: 10485760,
                  minRamMb: 512,
                  recommendedTier: 'mvp',
                  sources: <ModelSourceEntry>[
                    ModelSourceEntry(
                      id: 'unsigned-src',
                      label: 'Unsigned Mirror',
                      url: 'https://example.com/unsigned.onnx',
                      checksum: 'sha256:unsigned',
                    ),
                    ModelSourceEntry(
                      id: 'signed-src',
                      label: 'Signed Mirror',
                      url: 'https://example.com/signed.onnx',
                      checksum: 'sha256:signed',
                      signature: 'base64:sig',
                      signatureAlgorithm: 'RSA-SHA256',
                      keyId: 'key-1',
                    ),
                  ],
                ),
              ],
            ),
            modelDownloadTasksProvider.overrideWith((ref) async => const <ModelDownloadTask>[]),
            modelRegistryEntriesProvider.overrideWith((ref) async => const <ModelRegistryEntry>[]),
            activeModelSelectionProvider.overrideWith(
              (ref) async => const ActiveModelSelection(activeEmbeddingModelId: null),
            ),
            embeddingRuntimeStatesProvider.overrideWith((ref) async => const <String, EmbeddingEngineState>{}),
            modelDownloadControllerProvider.overrideWith((ref) => _FakeModelDownloadController(ref: ref)),
          ],
          child: const MaterialApp(home: ModelManagementPage()),
        ),
      );

      await tester.pumpAndSettle();

      // The unsigned effective source shows generic explainer but NOT the local caption.
      // Note: the unsigned source is first so it's selected by default.
      expect(find.text('已签名来源声明'), findsNothing);
      expect(find.textContaining(RegExp(r'已签名仅表示来源')), findsOneWidget);
    });
  });

  testWidgets('ModelManagementPage allows activating a ready installed local llm', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller = _RecordingActiveLocalLlmSelectionController();

    await tester.binding.setSurfaceSize(const Size(1000, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWith((ref) async => SharedPreferences.getInstance()),
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
          modelDownloadTasksProvider.overrideWith((ref) async => const <ModelDownloadTask>[]),
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
          embeddingRuntimeStatesProvider.overrideWith((ref) async => const <String, EmbeddingEngineState>{}),
          activeModelSelectionProvider.overrideWith(
            (ref) async => const ActiveModelSelection(activeEmbeddingModelId: null),
          ),
          activeLocalLlmSelectionControllerProvider.overrideWithValue(controller),
          modelDownloadControllerProvider.overrideWith((ref) => _FakeModelDownloadController(ref: ref)),
        ],
        child: const MaterialApp(home: ModelManagementPage()),
      ),
    );

    await tester.pumpAndSettle();

    final buttonFinder = find.widgetWithText(OutlinedButton, '设为当前本地LLM');
    await tester.scrollUntilVisible(buttonFinder, 200);
    await tester.tap(buttonFinder);
    await tester.pump();

    expect(controller.selectedModelId, 'llm-1');
  });

  testWidgets('ModelManagementPage disables local llm activation when runtime is degraded', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWith((ref) async => SharedPreferences.getInstance()),
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
          modelDownloadTasksProvider.overrideWith((ref) async => const <ModelDownloadTask>[]),
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
                ready: false,
                reason: 'probe failed',
                status: LlmRuntimeStatus.degraded,
              ),
            },
          ),
          embeddingRuntimeStatesProvider.overrideWith((ref) async => const <String, EmbeddingEngineState>{}),
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
      find.widgetWithText(OutlinedButton, '设为当前本地LLM'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('ModelManagementPage renders current source and selector in separate vertical sections', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          modelCatalogEntriesProvider.overrideWith((ref) async => const [_bgeEmbeddingCatalogEntry]),
          modelDownloadTasksProvider.overrideWith((ref) async => const <ModelDownloadTask>[]),
          modelRegistryEntriesProvider.overrideWith((ref) async => const <ModelRegistryEntry>[]),
          activeModelSelectionProvider.overrideWith(
            (ref) async => const ActiveModelSelection(activeEmbeddingModelId: null),
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
  });

  testWidgets('ModelManagementPage shows active download status section with compact staged copy', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          modelCatalogEntriesProvider.overrideWith((ref) async => const [_bgeEmbeddingCatalogEntry]),
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
          modelRegistryEntriesProvider.overrideWith((ref) async => const <ModelRegistryEntry>[]),
          activeModelSelectionProvider.overrideWith(
            (ref) async => const ActiveModelSelection(activeEmbeddingModelId: null),
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
  });
}
