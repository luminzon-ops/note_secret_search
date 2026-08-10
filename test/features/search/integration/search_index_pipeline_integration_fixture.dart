part of 'search_index_pipeline_integration_test.dart';

SecretItem _secret(CryptoService crypto) {
  final timestamp = DateTime.fromMillisecondsSinceEpoch(1000);
  return SecretItem(
    id: _sharedSourceId,
    vaultId: 'default',
    title: 'Personal mail account',
    usernameCiphertext: crypto.encryptField(
      'alice@example.test',
      field: EncryptedDatabaseField.secretUsername,
      rowId: _sharedSourceId,
    ),
    passwordCiphertext: crypto.encryptField(
      'password-only-value',
      field: EncryptedDatabaseField.secretPassword,
      rowId: _sharedSourceId,
    ),
    websiteUrlCiphertext: crypto.encryptField(
      'https://mail.example.test',
      field: EncryptedDatabaseField.secretWebsiteUrl,
      rowId: _sharedSourceId,
    ),
    noteCiphertext: crypto.encryptField(
      'MFA enabled',
      field: EncryptedDatabaseField.secretNote,
      rowId: _sharedSourceId,
    ),
    tags: const <String>['Mail'],
    categoryId: null,
    favorite: false,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

List<NoteItem> _notes(CryptoService crypto) {
  return <NoteItem>[
    _note(
      crypto,
      id: _sharedSourceId,
      title: 'Recovery plan',
      summary: 'Recovery mailbox instructions',
      body: 'Keep the offline recovery codes nearby.',
      tag: 'Recovery',
      updatedAt: 2000,
    ),
    for (var index = 1; index <= 4; index++)
      _note(
        crypto,
        id: 'candidate-$index',
        title: 'Candidate $index',
        summary: 'Candidate summary $index',
        body: 'Candidate body $index',
        tag: 'Candidate',
        updatedAt: 2000 - index,
      ),
    _note(
      crypto,
      id: 'weak-assist',
      title: 'Weak assist',
      summary: 'No strong semantic evidence',
      body: 'No strong body evidence',
      tag: 'weak-assist-tag',
      updatedAt: 1900,
    ),
  ];
}

NoteItem _note(
  CryptoService crypto, {
  required String id,
  required String title,
  required String summary,
  required String body,
  required String tag,
  required int updatedAt,
}) {
  final created = DateTime.fromMillisecondsSinceEpoch(1000);
  return NoteItem(
    id: id,
    vaultId: 'default',
    title: title,
    contentCiphertext: crypto.encryptField(
      body,
      field: EncryptedDatabaseField.noteContent,
      rowId: id,
    )!,
    summaryCacheCiphertext: crypto.encryptField(
      summary,
      field: EncryptedDatabaseField.noteSummary,
      rowId: id,
    ),
    tags: <String>[tag],
    categoryId: null,
    favorite: false,
    createdAt: created,
    updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAt),
  );
}

Future<void> _insertStaleGenerations({
  required TestAppDatabase database,
  required SearchConfiguration configuration,
}) {
  return database.transaction((db) async {
    for (var index = 0; index < 101; index++) {
      final suffix = index.toString().padLeft(3, '0');
      final sourceId = 'stale-source-$suffix';
      await db.insert(DatabaseSchema.secretItems, <String, Object?>{
        'id': sourceId,
        'vault_id': 'default',
        'title': 'Stale source $suffix',
        'favorite': 0,
        'created_at': 1,
        'updated_at': 1,
      });
      await db.insert(DatabaseSchema.embeddingIndexSets, <String, Object?>{
        'id': 'stale-set-$suffix',
        'source_type': 'secret',
        'source_id': sourceId,
        'vault_id': 'default',
        'model_id': _embeddingModel.id,
        'model_revision_hash': _staleModelRevision,
        'source_updated_at': 1,
        'source_fingerprint': Uint8List(32),
        'fingerprint_key_id': 'phase4-key',
        'fingerprint_version': 1,
        'index_config_version': 1,
        'index_config_epoch': configuration.configurationEpoch,
        'index_config_hash':
            'cccccccccccccccccccccccccccccccc'
            'cccccccccccccccccccccccccccccccc',
        'chunk_schema_version': 1,
        'vector_format_version': 1,
        'vector_dimension': 0,
        'chunk_count': 0,
        'created_at': 1,
      });
    }
  });
}

class _IncrementingNonceSource implements FieldNonceSource {
  int _value = 0;

  @override
  Uint8List nextNonce() {
    final start = _value++;
    return Uint8List.fromList(
      List<int>.generate(12, (index) => (start + index) & 0xff),
    );
  }
}

class _DeterministicEmbeddingEngine implements EmbeddingEngine {
  final List<String> indexedTexts = <String>[];

  @override
  Future<EmbeddingVector> embed(EmbeddingRequest request) async {
    final text = request.text;
    final values = switch (text) {
      'alice@example.test' => const <double>[1, 0],
      'Recovery mailbox instructions' => _vectorFromXAxisCosine(0.98),
      'Candidate summary 1' => _vectorFromXAxisCosine(0.96),
      'Candidate summary 2' => _vectorFromXAxisCosine(0.94),
      'Candidate summary 3' => _vectorFromXAxisCosine(0.92),
      'Candidate summary 4' => _vectorFromXAxisCosine(0.90),
      'weak-assist-query' => const <double>[0, 1],
      'weak-assist-tag' => _vectorFromYAxisCosine(0.91),
      'password-only-value' => const <double>[-1, 0],
      _ => const <double>[0, -1],
    };
    if (text != 'alice@example.test' && text != 'password-only-value') {
      indexedTexts.add(text);
    } else if (text == 'alice@example.test' && !indexedTexts.contains(text)) {
      indexedTexts.add(text);
    }
    return EmbeddingVector(values: values, tokenCount: 1);
  }

  List<double> _vectorFromXAxisCosine(double cosine) {
    return <double>[cosine, math.sqrt((1 - cosine * cosine).abs())];
  }

  List<double> _vectorFromYAxisCosine(double cosine) {
    return <double>[math.sqrt((1 - cosine * cosine).abs()), cosine];
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

const _embeddingModel = ModelRegistryEntry(
  id: 'embedding-model',
  type: 'embedding',
  provider: 'builtin',
  name: 'Deterministic embedding',
  version: '1',
  sizeBytes: 1,
  quantization: 'fp32',
  minRamMb: 1,
  recommendedTier: 'test',
  localPath: 'E:/models/embedding.onnx',
  checksum: 'verified-checksum',
  enabled: true,
  installedAt: null,
  filePresent: true,
  integrityStatus: ModelIntegrityStatus.valid,
);
