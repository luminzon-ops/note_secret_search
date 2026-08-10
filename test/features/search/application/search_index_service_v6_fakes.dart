part of 'search_index_service_v6_test.dart';

class _RecordingEmbeddingIndexRepository implements EmbeddingIndexRepository {
  EmbeddingIndexSet? current;
  final List<EmbeddingIndexSet> replacements = <EmbeddingIndexSet>[];

  @override
  Future<EmbeddingIndexSet?> getIndexSetBySource(
    SearchSourceKey sourceKey,
    String modelId,
  ) async {
    final value = current;
    return value?.sourceKey == sourceKey && value?.modelId == modelId
        ? value
        : null;
  }

  @override
  Future<void> removeIndexSetsBySource(SearchSourceKey sourceKey) async {
    if (current?.sourceKey == sourceKey) {
      current = null;
    }
  }

  @override
  Future<bool> replaceIndexSet(EmbeddingIndexSet indexSet) async {
    replacements.add(indexSet);
    current = indexSet;
    return true;
  }
}

class _BatchHeaderRepository
    implements EmbeddingIndexRepository, EmbeddingIndexHeaderRepository {
  final List<int> headerBatchSizes = <int>[];
  int fullGenerationReads = 0;

  @override
  Future<Map<SearchSourceKey, EmbeddingIndexSetHeader>>
  getIndexSetHeadersBySources(
    Iterable<SearchSourceKey> sourceKeys,
    String modelId,
  ) async {
    headerBatchSizes.add(sourceKeys.length);
    return const <SearchSourceKey, EmbeddingIndexSetHeader>{};
  }

  @override
  Future<EmbeddingIndexSet?> getIndexSetBySource(
    SearchSourceKey sourceKey,
    String modelId,
  ) async {
    fullGenerationReads++;
    return null;
  }

  @override
  Future<void> removeIndexSetsBySource(SearchSourceKey sourceKey) async {}

  @override
  Future<bool> replaceIndexSet(EmbeddingIndexSet indexSet) async => true;
}

class _RecordingEmbeddingEngine implements EmbeddingEngine {
  final List<String> texts = <String>[];

  @override
  Future<EmbeddingVector> embed(EmbeddingRequest request) async {
    texts.add(request.text);
    return const EmbeddingVector(values: <double>[1, 0], tokenCount: 1);
  }

  @override
  Future<EmbeddingEngineState> getState(ModelRegistryEntry model) async {
    return const EmbeddingEngineState(
      ready: true,
      reason: 'ready',
      status: EmbeddingRuntimeStatus.ready,
      vectorDimension: 2,
    );
  }
}

class _CallbackEmbeddingEngine implements EmbeddingEngine {
  _CallbackEmbeddingEngine({required this.onFirstEmbed});

  final void Function() onFirstEmbed;
  var _called = false;

  @override
  Future<EmbeddingVector> embed(EmbeddingRequest request) async {
    if (!_called) {
      _called = true;
      onFirstEmbed();
    }
    return const EmbeddingVector(values: <double>[1, 0], tokenCount: 1);
  }

  @override
  Future<EmbeddingEngineState> getState(ModelRegistryEntry model) async {
    return const EmbeddingEngineState(
      ready: true,
      reason: 'ready',
      status: EmbeddingRuntimeStatus.ready,
      vectorDimension: 2,
    );
  }
}

class _CancellableEmbeddingEngine implements EmbeddingEngine {
  final Completer<void> started = Completer<void>();
  bool cancelled = false;

  @override
  Future<EmbeddingVector> embed(EmbeddingRequest request) {
    final completer = Completer<EmbeddingVector>();
    if (identical(request.cancellationToken, EmbeddingCancellationToken.none)) {
      completer.completeError(StateError('missing cancellation token'));
      started.complete();
      return completer.future;
    }
    request.cancellationToken.register(() {
      cancelled = true;
      completer.completeError(
        const EmbeddingRuntimeCancelledException(
          stage: 'inference',
          modelId: 'embed-1',
        ),
      );
    });
    started.complete();
    return completer.future;
  }

  @override
  Future<EmbeddingEngineState> getState(ModelRegistryEntry model) async {
    return const EmbeddingEngineState(
      ready: true,
      reason: 'ready',
      status: EmbeddingRuntimeStatus.ready,
      vectorDimension: 2,
    );
  }
}

class _SearchIndexCryptoService implements CryptoService {
  @override
  String decryptNullable(
    List<int>? ciphertext, {
    required FieldCryptoContext context,
  }) {
    return switch (context.column) {
      'username_ciphertext' => 'alice@example.test',
      'password_ciphertext' => 'never-index-this-password',
      'website_url_ciphertext' => 'https://example.test',
      'note_ciphertext' => 'MFA enabled',
      _ => '',
    };
  }

  @override
  Uint8List? encryptNullable(
    String? plaintext, {
    required FieldCryptoContext context,
  }) {
    throw UnimplementedError();
  }
}

SecretItem _secret({String id = 'secret-1'}) {
  final now = DateTime.fromMillisecondsSinceEpoch(1);
  return SecretItem(
    id: id,
    vaultId: 'default',
    title: 'Example account',
    usernameCiphertext: const <int>[1],
    passwordCiphertext: const <int>[2],
    websiteUrlCiphertext: const <int>[3],
    noteCiphertext: const <int>[4],
    tags: const <String>['Work'],
    categoryId: null,
    favorite: false,
    createdAt: now,
    updatedAt: now,
  );
}

const ModelRegistryEntry _model = ModelRegistryEntry(
  id: 'model-1',
  type: 'embedding',
  provider: 'local',
  name: 'Embedding',
  version: '1',
  sizeBytes: 1,
  quantization: 'fp32',
  minRamMb: 1,
  recommendedTier: 'small',
  localPath: 'model.onnx',
  checksum: 'sha256:model',
  enabled: true,
  installedAt: null,
  filePresent: true,
  integrityStatus: ModelIntegrityStatus.valid,
);
