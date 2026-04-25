import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/security/crypto_service.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/notes/domain/note_item.dart';
import 'package:note_secret_search/features/search/application/semantic_quality_policy.dart';
import 'package:note_secret_search/features/search/application/semantic_search_service.dart';
import 'package:note_secret_search/features/search/domain/embedding_chunk.dart';
import 'package:note_secret_search/features/search/domain/embedding_engine.dart';
import 'package:note_secret_search/features/search/domain/search_repository.dart';
import 'package:note_secret_search/features/search/domain/search_result_item.dart';
import 'package:note_secret_search/features/search/domain/search_scope.dart';
import 'package:note_secret_search/features/secrets/domain/secret_item.dart';

class _FakeCryptoService implements CryptoService {
  const _FakeCryptoService();

  @override
  String decryptNullable(List<int>? ciphertext) {
    if (ciphertext == null) {
      return '';
    }
    return String.fromCharCodes(ciphertext);
  }

  @override
  List<int>? encryptNullable(String? plaintext) => plaintext?.codeUnits;
}

class _FakeSearchRepository implements SearchRepository {
  _FakeSearchRepository({required this.chunksBySource});

  final Map<String, List<EmbeddingChunk>> chunksBySource;

  @override
  Future<List<EmbeddingChunk>> getChunksBySource(
    String sourceId,
    SearchSourceType sourceType,
    String modelId,
  ) async {
    return chunksBySource[sourceId] ?? const <EmbeddingChunk>[];
  }

  @override
  Future<SearchScopeConfig> loadScopeConfig() async => const SearchScopeConfig.defaults();

  @override
  Future<void> removeChunksBySource(String sourceId, SearchSourceType sourceType) async {}

  @override
  Future<void> saveScopeConfig(SearchScopeConfig config) async {}

  @override
  Future<void> upsertEmbeddingChunks(List<EmbeddingChunk> chunks) async {}
}

class _FakeEmbeddingEngine implements EmbeddingEngine {
  const _FakeEmbeddingEngine({required this.values});

  final List<double> values;

  @override
  Future<EmbeddingVector> embed(EmbeddingRequest request) async {
    return EmbeddingVector(values: values, tokenCount: request.text.length);
  }

  @override
  Future<EmbeddingEngineState> getState(ModelRegistryEntry model) async {
    return const EmbeddingEngineState(
      ready: true,
      reason: 'ready',
      status: EmbeddingRuntimeStatus.ready,
    );
  }
}

const _model = ModelRegistryEntry(
  id: 'embed-1',
  type: 'embedding',
  provider: 'builtin',
  name: 'MiniLM',
  version: '1.0',
  sizeBytes: 1024,
  quantization: 'Q8',
  minRamMb: 512,
  recommendedTier: 'mvp',
  localPath: '/models/minilm.onnx',
  checksum: 'abc',
  enabled: true,
  installedAt: null,
  filePresent: true,
);

List<int> _vectorBlob(List<double> values) => utf8.encode(jsonEncode(values));

EmbeddingChunk _chunk({
  required String sourceId,
  required SearchSourceType sourceType,
  required int chunkIndex,
  required List<double> vector,
}) {
  return EmbeddingChunk(
    id: '$sourceId-$chunkIndex',
    sourceId: sourceId,
    sourceType: sourceType,
    modelId: _model.id,
    chunkIndex: chunkIndex,
    plainTextHash: 'hash-$sourceId-$chunkIndex',
    tokenCount: 4,
    createdAt: DateTime(2026, 4, 23),
    updatedAt: DateTime(2026, 4, 23),
    vectorBlob: _vectorBlob(vector),
  );
}

List<EmbeddingChunk> _noteSummaryOnlyChunks({
  required String sourceId,
  required List<double> summaryVector,
}) {
  return [
    _chunk(
      sourceId: sourceId,
      sourceType: SearchSourceType.note,
      chunkIndex: 0,
      vector: const [0, 1],
    ),
    _chunk(
      sourceId: sourceId,
      sourceType: SearchSourceType.note,
      chunkIndex: 1,
      vector: summaryVector,
    ),
  ];
}

List<EmbeddingChunk> _noteBodyOnlyChunks({
  required String sourceId,
  required List<double> bodyVector,
}) {
  return [
    _chunk(
      sourceId: sourceId,
      sourceType: SearchSourceType.note,
      chunkIndex: 0,
      vector: const [0, 1],
    ),
    _chunk(
      sourceId: sourceId,
      sourceType: SearchSourceType.note,
      chunkIndex: 1,
      vector: const [0, 1],
    ),
    _chunk(
      sourceId: sourceId,
      sourceType: SearchSourceType.note,
      chunkIndex: 2,
      vector: bodyVector,
    ),
  ];
}

List<EmbeddingChunk> _noteTagsOnlyChunks({
  required String sourceId,
  required List<double> tagsVector,
}) {
  return [
    _chunk(
      sourceId: sourceId,
      sourceType: SearchSourceType.note,
      chunkIndex: 0,
      vector: const [0, 1],
    ),
    _chunk(
      sourceId: sourceId,
      sourceType: SearchSourceType.note,
      chunkIndex: 1,
      vector: const [0, 1],
    ),
    _chunk(
      sourceId: sourceId,
      sourceType: SearchSourceType.note,
      chunkIndex: 2,
      vector: const [0, 1],
    ),
    _chunk(
      sourceId: sourceId,
      sourceType: SearchSourceType.note,
      chunkIndex: 3,
      vector: tagsVector,
    ),
  ];
}

List<EmbeddingChunk> _secretUsernameOnlyChunks({
  required String sourceId,
  required List<double> usernameVector,
}) {
  return [
    _chunk(
      sourceId: sourceId,
      sourceType: SearchSourceType.secret,
      chunkIndex: 0,
      vector: const [0, 1],
    ),
    _chunk(
      sourceId: sourceId,
      sourceType: SearchSourceType.secret,
      chunkIndex: 1,
      vector: usernameVector,
    ),
  ];
}

List<EmbeddingChunk> _secretUrlOnlyChunks({
  required String sourceId,
  required List<double> urlVector,
}) {
  return [
    _chunk(
      sourceId: sourceId,
      sourceType: SearchSourceType.secret,
      chunkIndex: 0,
      vector: const [0, 1],
    ),
    _chunk(
      sourceId: sourceId,
      sourceType: SearchSourceType.secret,
      chunkIndex: 1,
      vector: const [0, 1],
    ),
    _chunk(
      sourceId: sourceId,
      sourceType: SearchSourceType.secret,
      chunkIndex: 2,
      vector: urlVector,
    ),
  ];
}

SecretItem _secretItem() {
  return SecretItem(
    id: 'secret-1',
    vaultId: 'vault-1',
    title: 'Bank Account',
    usernameCiphertext: 'alice@example.com'.codeUnits,
    passwordCiphertext: 'secret'.codeUnits,
    websiteUrlCiphertext: 'bank.example.com'.codeUnits,
    noteCiphertext: 'important bank note'.codeUnits,
    tags: const ['finance'],
    categoryId: null,
    favorite: false,
    createdAt: DateTime(2026, 4, 23),
    updatedAt: DateTime(2026, 4, 23),
  );
}

SecretItem _secretItemWith({
  required String id,
  required String title,
  required String username,
  required String website,
  String note = 'important bank note',
  List<String> tags = const ['finance'],
}) {
  return SecretItem(
    id: id,
    vaultId: 'vault-1',
    title: title,
    usernameCiphertext: username.codeUnits,
    passwordCiphertext: 'secret'.codeUnits,
    websiteUrlCiphertext: website.codeUnits,
    noteCiphertext: note.codeUnits,
    tags: tags,
    categoryId: null,
    favorite: false,
    createdAt: DateTime(2026, 4, 23),
    updatedAt: DateTime(2026, 4, 23),
  );
}

NoteItem _noteItem({
  String id = 'note-1',
  String title = 'Recovery Guide',
  String summary = 'backup code summary',
  String content = 'recovery steps and backup codes',
  List<String> tags = const ['backup'],
}) {
  return NoteItem(
    id: id,
    vaultId: 'vault-1',
    title: title,
    contentCiphertext: content.codeUnits,
    summaryCacheCiphertext: summary.codeUnits,
    tags: tags,
    categoryId: null,
    favorite: false,
    createdAt: DateTime(2026, 4, 23),
    updatedAt: DateTime(2026, 4, 23),
  );
}

void main() {
  test('Semantic quality policy uses stricter thresholds for weaker fields', () {
    const policy = SemanticQualityPolicy.conservativeMvp();

    expect(
      policy.minimumThresholdFor(SemanticHitField.title),
      lessThan(policy.minimumThresholdFor(SemanticHitField.noteBody)),
    );
    expect(
      policy.minimumThresholdFor(SemanticHitField.tags),
      greaterThanOrEqualTo(policy.minimumThresholdFor(SemanticHitField.noteBody)),
    );
  });

  test('SemanticSearchService keeps a strong title hit above the quality gate', () async {
    final service = SemanticSearchService(
      repository: _FakeSearchRepository(
        chunksBySource: {
          'secret-1': [
            _chunk(
              sourceId: 'secret-1',
              sourceType: SearchSourceType.secret,
              chunkIndex: 0,
              vector: const [1, 0],
            ),
          ],
        },
      ),
      embeddingEngine: const _FakeEmbeddingEngine(values: <double>[1, 0]),
      cryptoService: const _FakeCryptoService(),
    );

    final results = await service.search(
      query: 'bank account',
      scope: const SearchScopeConfig.defaults(),
      activeEmbeddingModel: _model,
      secrets: [_secretItem()],
      notes: const <NoteItem>[],
    );

    expect(results, hasLength(1));
    expect(results.first.item.id, 'secret-1');
    expect(results.first.hitField, SemanticHitField.title);
  });

  test('SemanticSearchService filters a weak tags-only hit below the conservative quality gate', () async {
    final service = SemanticSearchService(
      repository: _FakeSearchRepository(
        chunksBySource: {
          'note-1': [
            _chunk(
              sourceId: 'note-1',
              sourceType: SearchSourceType.note,
              chunkIndex: 3,
              vector: const [0.25, 0.9682458366],
            ),
          ],
        },
      ),
      embeddingEngine: const _FakeEmbeddingEngine(values: <double>[1, 0]),
      cryptoService: const _FakeCryptoService(),
    );

    final results = await service.search(
      query: 'backup tag',
      scope: const SearchScopeConfig.defaults(),
      activeEmbeddingModel: _model,
      secrets: const <SecretItem>[],
      notes: [_noteItem()],
    );

    expect(results, isEmpty);
  });

  test('SemanticSearchService applies a stricter gate to note-body hits than title hits', () async {
    final service = SemanticSearchService(
      repository: _FakeSearchRepository(
        chunksBySource: {
          'note-1': [
            _chunk(
              sourceId: 'note-1',
              sourceType: SearchSourceType.note,
              chunkIndex: 2,
              vector: const [0.7, 0.7141428429],
            ),
          ],
        },
      ),
      embeddingEngine: const _FakeEmbeddingEngine(values: <double>[1, 0]),
      cryptoService: const _FakeCryptoService(),
    );

    final results = await service.search(
      query: 'backup steps',
      scope: const SearchScopeConfig.defaults(),
      activeEmbeddingModel: _model,
      secrets: const <SecretItem>[],
      notes: [_noteItem()],
    );

    expect(results, isEmpty);
  });

  test('SemanticSearchService keeps high-quality field hits inside semantic top-k before lower-priority fields', () async {
    final service = SemanticSearchService(
      repository: _FakeSearchRepository(
        chunksBySource: {
          'note-summary': _noteSummaryOnlyChunks(
            sourceId: 'note-summary',
            summaryVector: const [0.8090909091, 0.5876836192],
          ),
          'note-assist-1': _noteBodyOnlyChunks(
            sourceId: 'note-assist-1',
            bodyVector: const [0.99, 0.1410673598],
          ),
          'note-assist-2': _noteBodyOnlyChunks(
            sourceId: 'note-assist-2',
            bodyVector: const [0.985, 0.1725543390],
          ),
          'note-assist-3': _noteBodyOnlyChunks(
            sourceId: 'note-assist-3',
            bodyVector: const [0.982, 0.1888581482],
          ),
          'note-assist-4': _noteBodyOnlyChunks(
            sourceId: 'note-assist-4',
            bodyVector: const [0.98, 0.1989974874],
          ),
          'note-assist-5': _noteBodyOnlyChunks(
            sourceId: 'note-assist-5',
            bodyVector: const [0.979, 0.2038847714],
          ),
        },
      ),
      embeddingEngine: const _FakeEmbeddingEngine(values: <double>[1, 0]),
      cryptoService: const _FakeCryptoService(),
    );

    final results = await service.search(
      query: 'backup recovery',
      scope: const SearchScopeConfig.defaults(),
      activeEmbeddingModel: _model,
      secrets: const <SecretItem>[],
      notes: [
        _noteItem(id: 'note-summary', title: 'Strong Summary', summary: 'strong semantic summary'),
        _noteItem(id: 'note-assist-1', title: 'Assist 1', content: 'assist body 1'),
        _noteItem(id: 'note-assist-2', title: 'Assist 2', content: 'assist body 2'),
        _noteItem(id: 'note-assist-3', title: 'Assist 3', content: 'assist body 3'),
        _noteItem(id: 'note-assist-4', title: 'Assist 4', content: 'assist body 4'),
        _noteItem(id: 'note-assist-5', title: 'Assist 5', content: 'assist body 5'),
      ],
    );

    expect(results, hasLength(5));
    expect(results.map((result) => result.item.id), contains('note-summary'));
    expect(results.map((result) => result.item.id), isNot(contains('note-assist-5')));
  });

  test('SemanticSearchService still backfills semantic top-k with assist fields when high-quality hits are fewer than k', () async {
    final service = SemanticSearchService(
      repository: _FakeSearchRepository(
        chunksBySource: {
          'note-summary': _noteSummaryOnlyChunks(
            sourceId: 'note-summary',
            summaryVector: const [0.85, 0.5267826876],
          ),
          'note-assist-1': _noteBodyOnlyChunks(
            sourceId: 'note-assist-1',
            bodyVector: const [0.99, 0.1410673598],
          ),
          'note-assist-2': _noteBodyOnlyChunks(
            sourceId: 'note-assist-2',
            bodyVector: const [0.985, 0.1725543390],
          ),
        },
      ),
      embeddingEngine: const _FakeEmbeddingEngine(values: <double>[1, 0]),
      cryptoService: const _FakeCryptoService(),
    );

    final results = await service.search(
      query: 'backup recovery',
      scope: const SearchScopeConfig.defaults(),
      activeEmbeddingModel: _model,
      secrets: const <SecretItem>[],
      notes: [
        _noteItem(id: 'note-summary', title: 'Strong Summary', summary: 'strong semantic summary'),
        _noteItem(id: 'note-assist-1', title: 'Assist 1', content: 'assist body 1'),
        _noteItem(id: 'note-assist-2', title: 'Assist 2', content: 'assist body 2'),
      ],
    );

    expect(results, hasLength(3));
    expect(results.map((result) => result.item.id), ['note-summary', 'note-assist-1', 'note-assist-2']);
  });

  test('SemanticSearchService prefers url semantic hits for URL-like queries', () async {
    final service = SemanticSearchService(
      repository: _FakeSearchRepository(
        chunksBySource: {
          'secret-url': _secretUrlOnlyChunks(
            sourceId: 'secret-url',
            urlVector: const [0.87, 0.4930517214],
          ),
          'note-summary': _noteSummaryOnlyChunks(
            sourceId: 'note-summary',
            summaryVector: const [0.91, 0.4146082488],
          ),
        },
      ),
      embeddingEngine: const _FakeEmbeddingEngine(values: <double>[1, 0]),
      cryptoService: const _FakeCryptoService(),
    );

    final results = await service.search(
      query: 'bank.example.com',
      scope: const SearchScopeConfig.defaults(),
      activeEmbeddingModel: _model,
      secrets: [
        _secretItemWith(
          id: 'secret-url',
          title: 'Bank Login',
          username: 'alice@example.com',
          website: 'bank.example.com',
        ),
      ],
      notes: [
        _noteItem(id: 'note-summary', title: 'Recovery Guide', summary: 'bank recovery summary'),
      ],
    );

    expect(results, hasLength(2));
    expect(results.first.item.id, 'secret-url');
    expect(results.first.hitField, SemanticHitField.url);
  });

  test('SemanticSearchService prefers username semantic hits for account-like queries', () async {
    final service = SemanticSearchService(
      repository: _FakeSearchRepository(
        chunksBySource: {
          'secret-username': _secretUsernameOnlyChunks(
            sourceId: 'secret-username',
            usernameVector: const [0.86, 0.5102940329],
          ),
          'note-summary': _noteSummaryOnlyChunks(
            sourceId: 'note-summary',
            summaryVector: const [0.91, 0.4146082488],
          ),
        },
      ),
      embeddingEngine: const _FakeEmbeddingEngine(values: <double>[1, 0]),
      cryptoService: const _FakeCryptoService(),
    );

    final results = await service.search(
      query: 'alice@example.com',
      scope: const SearchScopeConfig.defaults(),
      activeEmbeddingModel: _model,
      secrets: [
        _secretItemWith(
          id: 'secret-username',
          title: 'Bank Login',
          username: 'alice@example.com',
          website: 'bank.example.com',
        ),
      ],
      notes: [
        _noteItem(id: 'note-summary', title: 'Recovery Guide', summary: 'bank recovery summary'),
      ],
    );

    expect(results, hasLength(2));
    expect(results.first.item.id, 'secret-username');
    expect(results.first.hitField, SemanticHitField.username);
  });

  test('SemanticSearchService prefers tags semantic hits for tag-like queries', () async {
    final service = SemanticSearchService(
      repository: _FakeSearchRepository(
        chunksBySource: {
          'note-tags': _noteTagsOnlyChunks(
            sourceId: 'note-tags',
            tagsVector: const [0.94, 0.3411744422],
          ),
          'note-summary': _noteSummaryOnlyChunks(
            sourceId: 'note-summary',
            summaryVector: const [0.91, 0.4146082488],
          ),
        },
      ),
      embeddingEngine: const _FakeEmbeddingEngine(values: <double>[1, 0]),
      cryptoService: const _FakeCryptoService(),
    );

    final results = await service.search(
      query: 'backup',
      scope: const SearchScopeConfig.defaults(),
      activeEmbeddingModel: _model,
      secrets: const <SecretItem>[],
      notes: [
        _noteItem(id: 'note-tags', title: 'Backup Labels', tags: const ['backup']),
        _noteItem(id: 'note-summary', title: 'Recovery Guide', summary: 'backup recovery summary'),
      ],
    );

    expect(results, hasLength(2));
    expect(results.first.item.id, 'note-tags');
    expect(results.first.hitField, SemanticHitField.tags);
  });

  test('SemanticSearchService does not boost tags for non-tag-like queries', () async {
    final service = SemanticSearchService(
      repository: _FakeSearchRepository(
        chunksBySource: {
          'note-tags': _noteTagsOnlyChunks(
            sourceId: 'note-tags',
            tagsVector: const [0.94, 0.3411744422],
          ),
          'note-summary': _noteSummaryOnlyChunks(
            sourceId: 'note-summary',
            summaryVector: const [0.91, 0.4146082488],
          ),
        },
      ),
      embeddingEngine: const _FakeEmbeddingEngine(values: <double>[1, 0]),
      cryptoService: const _FakeCryptoService(),
    );

    final results = await service.search(
      query: 'backup steps',
      scope: const SearchScopeConfig.defaults(),
      activeEmbeddingModel: _model,
      secrets: const <SecretItem>[],
      notes: [
        _noteItem(id: 'note-tags', title: 'Backup Labels', tags: const ['backup']),
        _noteItem(id: 'note-summary', title: 'Recovery Guide', summary: 'backup recovery summary'),
      ],
    );

    expect(results, hasLength(2));
    expect(results.first.item.id, 'note-summary');
    expect(results.first.hitField, SemanticHitField.summary);
  });
}
