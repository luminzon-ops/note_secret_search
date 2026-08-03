part of 'search_settings_page_test.dart';

const _installedSearchSettingsModelDigest =
    'sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _installedSearchSettingsModel = ModelRegistryEntry(
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
  checksum: _installedSearchSettingsModelDigest,
  enabled: true,
  installedAt: null,
  filePresent: true,
  integrityStatus: ModelIntegrityStatus.valid,
  releaseId: 'release-1',
  catalogVersion: 1,
  catalogDigest:
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  generation: 1,
  revisionRoot: 'revisions/1',
  artifacts: <ModelArtifactPath>[
    ModelArtifactPath(
      artifactId: 'model',
      releaseId: 'release-1',
      role: 'model',
      sourceId: 'test-source',
      localPath: '/data/models/minilm.onnx',
      relativePath: 'runtime/model.onnx',
      expectedChecksum: _installedSearchSettingsModelDigest,
      verifiedChecksum: _installedSearchSettingsModelDigest,
      expectedSizeBytes: 10485760,
      verifiedSizeBytes: 10485760,
      state: 'installed',
      verifiedAt: 1,
    ),
  ],
);

class _RecordingSearchRefreshRunner implements SearchRefreshRunner {
  _RecordingSearchRefreshRunner({this.error});

  int refreshCalls = 0;
  final Object? error;

  @override
  Future<SearchRefreshExecutionResult> execute({
    required String query,
    required SearchIndexTaskState taskState,
    required SearchIndexTaskStateWriter onTaskState,
    required SearchRefreshPhaseWriter onReloading,
    required SearchRefreshFeedbackWriter onFeedback,
  }) async {
    refreshCalls++;
    if (error != null) {
      throw error!;
    }
    return SearchRefreshExecutionResult.completed;
  }
}

class _RecordingSearchSettingsUseCase extends SearchSettingsUseCase {
  _RecordingSearchSettingsUseCase({this.scopeRequiresReindex = false})
    : super(
         writeFence: SearchIndexWriteFence(),
         loadConfiguration: () async => SearchConfiguration.defaults(),
         loadRepository: () async => throw UnimplementedError(),
         invalidateConfiguration: () {},
       );

  final bool scopeRequiresReindex;
  SearchIndexSettings? lastIndexSettings;
  SearchScopeConfig? lastScope;

  @override
  Future<SearchSettingsSaveResult> saveIndexSettings(
    SearchIndexSettings settings,
  ) async {
    lastIndexSettings = settings;
    return SearchSettingsSaveResult(
      savedConfiguration: SearchConfiguration.defaults(),
      requiresReindex: true,
    );
  }

  @override
  Future<SearchSettingsSaveResult> saveScope(SearchScopeConfig scope) async {
    lastScope = scope;
    return SearchSettingsSaveResult(
      savedConfiguration: SearchConfiguration.defaults(),
      requiresReindex: scopeRequiresReindex,
    );
  }
}

Future<void> _selectChunkLength(WidgetTester tester, int value) async {
  await tester.tap(find.byType(DropdownButton<int>));
  await tester.pumpAndSettle();
  await tester.tap(find.text('$value').hitTestable());
  await tester.pumpAndSettle();
}
