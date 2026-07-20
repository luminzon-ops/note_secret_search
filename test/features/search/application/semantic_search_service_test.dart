import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/security/crypto_service.dart';
import 'package:note_secret_search/core/security/database_session_keys.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/notes/domain/note_item.dart';
import 'package:note_secret_search/features/search/application/semantic_search_service.dart';
import 'package:note_secret_search/features/search/domain/embedding_chunk.dart';
import 'package:note_secret_search/features/search/domain/embedding_engine.dart';
import 'package:note_secret_search/features/search/domain/embedding_index_repository.dart';
import 'package:note_secret_search/features/search/domain/embedding_index_set.dart';
import 'package:note_secret_search/features/search/domain/float32_vector_codec.dart';
import 'package:note_secret_search/features/search/domain/search_configuration.dart';
import 'package:note_secret_search/features/secrets/domain/secret_item.dart';

void main() {
  test('raw field threshold is applied before ranking weight', () async {
    final repository = _CorpusRepository(<EmbeddingIndexSet>[
      _set(
        sourceKey: const SearchSourceKey.secret('secret-title'),
        chunks: <({SearchSourceField field, List<double> vector})>[
          (
            field: SearchSourceField.secretTitle,
            vector: _unitVectorWithCosine(0.819),
          ),
        ],
      ),
      _set(
        sourceKey: const SearchSourceKey.note('note-body'),
        chunks: <({SearchSourceField field, List<double> vector})>[
          (
            field: SearchSourceField.noteBody,
            vector: _unitVectorWithCosine(0.901),
          ),
        ],
      ),
    ]);
    final service = _service(repository);

    final results = await service.search(
      query: 'query',
      configuration: SearchConfiguration.defaults(),
      modelRevisionHash: 'a' * 64,
      activeEmbeddingModel: _model,
      secrets: <SecretItem>[_secret('secret-title')],
      notes: <NoteItem>[_note('note-body')],
    );

    expect(results.map((result) => result.item.id), const <String>[
      'note-body',
    ]);
    expect(results.single.primaryRawSimilarity, closeTo(0.901, 0.00001));
    expect(
      results.single.evidence.single.sourceField,
      SearchSourceField.noteBody,
    );
  });

  test(
    'field metadata drives top-two aggregation and primary evidence',
    () async {
      final repository = _CorpusRepository(<EmbeddingIndexSet>[
        _set(
          sourceKey: const SearchSourceKey.secret('secret-1'),
          chunks: <({SearchSourceField field, List<double> vector})>[
            (
              field: SearchSourceField.secretNote,
              vector: _unitVectorWithCosine(0.88),
            ),
            (
              field: SearchSourceField.secretTitle,
              vector: _unitVectorWithCosine(1),
            ),
            (
              field: SearchSourceField.secretUsername,
              vector: _unitVectorWithCosine(0.90),
            ),
          ],
        ),
      ]);
      final service = _service(repository);

      final results = await service.search(
        query: 'alice@example.test',
        configuration: SearchConfiguration.defaults(),
        modelRevisionHash: 'a' * 64,
        activeEmbeddingModel: _model,
        secrets: <SecretItem>[_secret('secret-1')],
        notes: const <NoteItem>[],
      );

      expect(results, hasLength(1));
      expect(results.single.evidence, hasLength(3));
      expect(
        results.single.evidence.first.sourceField,
        SearchSourceField.secretTitle,
      );
      expect(results.single.score, closeTo((1.16 + 0.99) / 2, 0.00001));
      expect(results.single.hitSummary, contains('标题'));
      expect(results.single.hitSummary, contains('账号'));
    },
  );

  test('corrupt generation is purged without hiding valid results', () async {
    final corrupt = _set(
      sourceKey: const SearchSourceKey.secret('secret-corrupt'),
      chunks: <({SearchSourceField field, List<double> vector})>[
        (field: SearchSourceField.secretTitle, vector: const <double>[1, 0]),
      ],
      overrideBlob: _nanVectorBlob(),
    );
    final valid = _set(
      sourceKey: const SearchSourceKey.secret('secret-valid'),
      chunks: <({SearchSourceField field, List<double> vector})>[
        (field: SearchSourceField.secretTitle, vector: const <double>[1, 0]),
      ],
    );
    final repository = _CorpusRepository(<EmbeddingIndexSet>[corrupt, valid]);
    final service = _service(repository);

    final results = await service.search(
      query: 'query',
      configuration: SearchConfiguration.defaults(),
      modelRevisionHash: 'a' * 64,
      activeEmbeddingModel: _model,
      secrets: <SecretItem>[_secret('secret-corrupt'), _secret('secret-valid')],
      notes: const <NoteItem>[],
    );

    expect(results.map((result) => result.item.id), const ['secret-valid']);
    expect(repository.purgedIds, contains(corrupt.id));
  });

  test('semantic scope excludes disabled fields', () async {
    final repository = _CorpusRepository(<EmbeddingIndexSet>[
      _set(
        sourceKey: const SearchSourceKey.note('note-1'),
        chunks: <({SearchSourceField field, List<double> vector})>[
          (field: SearchSourceField.noteBody, vector: const <double>[1, 0]),
        ],
      ),
    ]);
    final service = _service(repository);

    final results = await service.search(
      query: 'query',
      configuration: SearchConfiguration.defaults().copyWith(
        includeNoteBody: false,
      ),
      modelRevisionHash: 'a' * 64,
      activeEmbeddingModel: _model,
      secrets: const <SecretItem>[],
      notes: <NoteItem>[_note('note-1')],
    );

    expect(results, isEmpty);
  });

  test(
    'non-index source timestamp changes keep a compatible generation visible',
    () async {
      final repository = _CorpusRepository(<EmbeddingIndexSet>[
        _set(
          sourceKey: const SearchSourceKey.secret('secret-1'),
          chunks: <({SearchSourceField field, List<double> vector})>[
            (
              field: SearchSourceField.secretTitle,
              vector: const <double>[1, 0],
            ),
          ],
        ),
      ]);
      final service = _service(repository);
      final source = _secret('secret-1');
      final timestampOnlyUpdate = SecretItem(
        id: source.id,
        vaultId: source.vaultId,
        title: source.title,
        usernameCiphertext: source.usernameCiphertext,
        passwordCiphertext: source.passwordCiphertext,
        websiteUrlCiphertext: source.websiteUrlCiphertext,
        noteCiphertext: source.noteCiphertext,
        tags: source.tags,
        categoryId: 'category-only-change',
        favorite: true,
        createdAt: source.createdAt,
        updatedAt: source.updatedAt.add(const Duration(seconds: 1)),
      );

      final results = await service.search(
        query: 'query',
        configuration: SearchConfiguration.defaults(),
        modelRevisionHash: 'a' * 64,
        activeEmbeddingModel: _model,
        secrets: <SecretItem>[timestampOnlyUpdate],
        notes: const <NoteItem>[],
      );

      expect(results.map((result) => result.item.id), const ['secret-1']);
      expect(repository.purgedIds, isEmpty);
    },
  );

  test(
    'semantic results are deterministically capped at one hundred',
    () async {
      final sets = <EmbeddingIndexSet>[
        for (var index = 0; index < 101; index++)
          _set(
            sourceKey: SearchSourceKey.secret(
              'secret-${index.toString().padLeft(3, '0')}',
            ),
            chunks: <({SearchSourceField field, List<double> vector})>[
              (
                field: SearchSourceField.secretTitle,
                vector: const <double>[1, 0],
              ),
            ],
          ),
      ];
      final repository = _CorpusRepository(sets);
      final service = _service(repository);

      final results = await service.search(
        query: 'query',
        configuration: SearchConfiguration.defaults(),
        modelRevisionHash: 'a' * 64,
        activeEmbeddingModel: _model,
        secrets: <SecretItem>[
          for (var index = 0; index < 101; index++)
            _secret('secret-${index.toString().padLeft(3, '0')}'),
        ],
        notes: const <NoteItem>[],
      );

      expect(results, hasLength(100));
      expect(results.first.item.id, 'secret-000');
      expect(results.last.item.id, 'secret-099');
    },
  );
}

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
}) {
  final id = 'set-${sourceKey.type.name}-${sourceKey.id}';
  return EmbeddingIndexSet(
    id: id,
    sourceKey: sourceKey,
    vaultId: 'vault-1',
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
    chunks: <EmbeddingChunk>[
      for (var index = 0; index < chunks.length; index++)
        EmbeddingChunk(
          id: '$id-$index',
          indexSetId: id,
          sourceField: chunks[index].field,
          fieldChunkIndex: index,
          chunkFingerprint: Uint8List(32),
          vectorBlob:
              overrideBlob ?? Float32VectorCodec.encode(chunks[index].vector),
          tokenCount: 1,
          createdAt: DateTime.fromMillisecondsSinceEpoch(1),
        ),
    ],
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

SecretItem _secret(String id) {
  final now = DateTime.fromMillisecondsSinceEpoch(1);
  return SecretItem(
    id: id,
    vaultId: 'vault-1',
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
  );
}

NoteItem _note(String id) {
  final now = DateTime.fromMillisecondsSinceEpoch(1);
  return NoteItem(
    id: id,
    vaultId: 'vault-1',
    title: 'Title $id',
    contentCiphertext: 'Body text'.codeUnits,
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
