part of 'semantic_search_service_test.dart';

SemanticSearchService _service(_CorpusRepository repository) {
  final keys = DatabaseSessionKeyStore()
    ..replace(
      DatabaseSessionKeys(
        databaseKey: Uint8List(32),
        fieldKey: Uint8List(32),
        keyId: 'key-1',
        searchIndexFingerprintKey: Uint8List(32),
      ),
    );
  return SemanticSearchService(
    repository: repository,
    embeddingEngine: const _EmbeddingEngine(),
    cryptoService: const _CryptoService(),
    sessionKeyStore: keys,
  );
}

class _CorpusRepository implements EmbeddingIndexCorpusRepository {
  _CorpusRepository(this.sets);

  final List<EmbeddingIndexSet> sets;
  final List<String> purgedIds = <String>[];

  @override
  Future<List<EmbeddingIndexSet>> getCompatibleIndexSets(
    EmbeddingIndexCompatibility compatibility, {
    String? afterId,
    int limit = 100,
  }) async {
    final ordered = sets.toList(growable: false)
      ..sort((left, right) => left.id.compareTo(right.id));
    return ordered
        .where((set) => afterId == null || set.id.compareTo(afterId) > 0)
        .take(limit)
        .toList(growable: false);
  }

  @override
  Future<int> purgeIncompatibleIndexSets(
    EmbeddingIndexCompatibility compatibility, {
    int batchSize = 100,
  }) async => 0;

  @override
  Future<int> purgeIndexSetsByIds(Iterable<String> indexSetIds) async {
    purgedIds.addAll(indexSetIds);
    return indexSetIds.length;
  }

  @override
  Future<int> purgeAllIndexSets({int batchSize = 100}) async => 0;
}

class _IdHydrationSecretRepository
    implements SecretRepository, SecretSearchReader {
  _IdHydrationSecretRepository(this.item);

  final SecretItem item;
  final List<List<String>> requestedBatches = <List<String>>[];

  @override
  Future<List<SecretItem>> listByVaultIds(
    String vaultId,
    Iterable<String> ids,
  ) async {
    requestedBatches.add(List<String>.from(ids));
    return ids.contains(item.id) ? <SecretItem>[item] : const <SecretItem>[];
  }

  @override
  Future<List<SecretItem>> listByVaultPage(
    String vaultId, {
    String? afterId,
    int limit = searchSourcePageSize,
  }) async {
    return const <SecretItem>[];
  }

  @override
  Future<List<SecretItem>> listByVault(String vaultId) {
    throw StateError('unbounded secret load');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _EmptyNoteRepository implements NoteRepository, NoteSearchReader {
  @override
  Future<List<NoteItem>> listByVaultIds(
    String vaultId,
    Iterable<String> ids,
  ) async {
    return const <NoteItem>[];
  }

  @override
  Future<List<NoteItem>> listByVaultPage(
    String vaultId, {
    String? afterId,
    int limit = searchSourcePageSize,
  }) async {
    return const <NoteItem>[];
  }

  @override
  Future<List<NoteItem>> listByVault(String vaultId) {
    throw StateError('unbounded note load');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _EmbeddingEngine implements EmbeddingEngine {
  const _EmbeddingEngine();

  @override
  Future<EmbeddingVector> embed(EmbeddingRequest request) async {
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

class _CryptoService implements CryptoService {
  const _CryptoService();

  @override
  String decryptNullable(
    List<int>? ciphertext, {
    required FieldCryptoContext context,
  }) {
    return ciphertext == null ? '' : String.fromCharCodes(ciphertext);
  }

  @override
  Uint8List? encryptNullable(
    String? plaintext, {
    required FieldCryptoContext context,
  }) {
    throw UnimplementedError();
  }
}

EmbeddingIndexSet _set({
  required SearchSourceKey sourceKey,
  required List<({SearchSourceField field, List<double> vector})> chunks,
  Uint8List? overrideBlob,
  String vaultId = 'vault-1',
}) {
  final id = 'set-${sourceKey.type.name}-${sourceKey.id}';
  final fieldCounts = <SearchSourceField, int>{};
  final storedChunks = <EmbeddingChunk>[];
  for (var index = 0; index < chunks.length; index++) {
    final field = chunks[index].field;
    final fieldChunkIndex = fieldCounts.update(
      field,
      (value) => value + 1,
      ifAbsent: () => 0,
    );
    storedChunks.add(
      EmbeddingChunk(
        id: '$id-$index',
        indexSetId: id,
        sourceField: field,
        fieldChunkIndex: fieldChunkIndex,
        chunkFingerprint: Uint8List(32),
        vectorBlob:
            overrideBlob ?? Float32VectorCodec.encode(chunks[index].vector),
        tokenCount: 1,
        createdAt: DateTime.fromMillisecondsSinceEpoch(1),
      ),
    );
  }
  return EmbeddingIndexSet(
    id: id,
    sourceKey: sourceKey,
    vaultId: vaultId,
    modelId: _model.id,
    modelRevisionHash: 'a' * 64,
    sourceUpdatedAt: DateTime.fromMillisecondsSinceEpoch(1),
    sourceFingerprint: Uint8List(32),
    fingerprintKeyId: 'key-1',
    fingerprintVersion: 1,
    indexConfigVersion: 1,
    indexConfigEpoch: 1,
    indexConfigHash: 'b' * 64,
    chunkSchemaVersion: 1,
    vectorFormatVersion: 1,
    vectorDimension: 2,
    chunks: storedChunks,
    createdAt: DateTime.fromMillisecondsSinceEpoch(1),
  );
}

List<double> _unitVectorWithCosine(double cosine) {
  return <double>[cosine, math.sqrt(1 - cosine * cosine)];
}

Uint8List _nanVectorBlob() {
  final data = ByteData(8)
    ..setFloat32(0, double.nan, Endian.little)
    ..setFloat32(4, 0, Endian.little);
  return data.buffer.asUint8List();
}

SecretItem _secret(
  String id, {
  String vaultId = 'vault-1',
  DateTime? deletedAt,
}) {
  final now = DateTime.fromMillisecondsSinceEpoch(1);
  return SecretItem(
    id: id,
    vaultId: vaultId,
    title: 'Title $id',
    usernameCiphertext: 'alice@example.test'.codeUnits,
    passwordCiphertext: 'password'.codeUnits,
    websiteUrlCiphertext: 'https://example.test'.codeUnits,
    noteCiphertext: 'MFA enabled'.codeUnits,
    tags: const <String>['work'],
    categoryId: null,
    favorite: false,
    createdAt: now,
    updatedAt: now,
    deletedAt: deletedAt,
  );
}

NoteItem _note(String id, {String body = 'Body text'}) {
  final now = DateTime.fromMillisecondsSinceEpoch(1);
  return NoteItem(
    id: id,
    vaultId: 'vault-1',
    title: 'Title $id',
    contentCiphertext: body.codeUnits,
    summaryCacheCiphertext: 'Summary text'.codeUnits,
    tags: const <String>['work'],
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
