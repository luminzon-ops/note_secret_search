import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/security/crypto_service.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/notes/domain/note_item.dart';
import 'package:note_secret_search/features/search/application/semantic_search_service.dart';
import 'package:note_secret_search/features/search/domain/embedding_chunk.dart';
import 'package:note_secret_search/features/search/domain/embedding_engine.dart';
import 'package:note_secret_search/features/search/domain/search_repository.dart';
import 'package:note_secret_search/features/search/domain/search_result_item.dart';
import 'package:note_secret_search/features/search/domain/search_scope.dart';
import 'package:note_secret_search/features/secrets/domain/secret_item.dart';

void main() {
  test('semantic search aggregates top chunk hits into combined summary and stronger score', () async {
    final repository = _FakeSearchRepository(
      chunksBySource: {
        ('secret-1', SearchSourceType.secret, 'embedding-model'): [
          _chunk(
            id: 'c1',
            sourceId: 'secret-1',
            sourceType: SearchSourceType.secret,
            chunkIndex: 0,
            vector: const [1.0, 0.0],
          ),
          _chunk(
            id: 'c2',
            sourceId: 'secret-1',
            sourceType: SearchSourceType.secret,
            chunkIndex: 1,
            vector: const [0.9, 0.1],
          ),
          _chunk(
            id: 'c3',
            sourceId: 'secret-1',
            sourceType: SearchSourceType.secret,
            chunkIndex: 2,
            vector: const [0.1, 0.9],
          ),
        ],
      },
    );

    final service = SemanticSearchService(
      repository: repository,
      embeddingEngine: const _FakeEmbeddingEngine(),
      cryptoService: const MvpCryptoService(),
    );

    final results = await service.search(
      query: 'bank login',
      scope: const SearchScopeConfig.defaults(),
      activeEmbeddingModel: _model(),
      secrets: [
        SecretItem(
          id: 'secret-1',
          vaultId: 'default',
          title: 'Bank Account',
          usernameCiphertext: utf8.encode('alice@example.com'),
          passwordCiphertext: utf8.encode('secret-password'),
          websiteUrlCiphertext: utf8.encode('https://bank.example.com'),
          noteCiphertext: utf8.encode('recovery codes are in drawer'),
          tags: const ['finance'],
          categoryId: null,
          favorite: false,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026, 1, 2),
        ),
      ],
      notes: const <NoteItem>[],
    );

    expect(results, hasLength(1));
    expect(results.first.hitSummary, contains('标题：Bank Account'));
    expect(results.first.hitSummary, contains('账号：alice@example.com'));
    expect(results.first.hitSummary, isNot(contains('网址：https://bank.example.com')));
    expect(results.first.score, greaterThan(0.95));
  });

  test('semantic search prefers higher-priority title hits over slightly stronger tag hits', () async {
    final repository = _FakeSearchRepository(
      chunksBySource: {
        ('note-1', SearchSourceType.note, 'embedding-model'): [
          _chunk(
            id: 'n1',
            sourceId: 'note-1',
            sourceType: SearchSourceType.note,
            chunkIndex: 0,
            vector: const [0.96, 0.28],
          ),
          _chunk(
            id: 'n2',
            sourceId: 'note-1',
            sourceType: SearchSourceType.note,
            chunkIndex: 1,
            vector: const [0.99, 0.12],
          ),
        ],
      },
    );

    final service = SemanticSearchService(
      repository: repository,
      embeddingEngine: const _FakeEmbeddingEngine(),
      cryptoService: const MvpCryptoService(),
    );

    final results = await service.search(
      query: 'bank login',
      scope: const SearchScopeConfig.defaults(),
      activeEmbeddingModel: _model(),
      secrets: const <SecretItem>[],
      notes: [
        NoteItem(
          id: 'note-1',
          vaultId: 'default',
          title: 'Bank Migration Plan',
          contentCiphertext: utf8.encode('Move shared banking checklist into note body.'),
          summaryCacheCiphertext: utf8.encode('Checklist summary'),
          tags: const ['banking'],
          categoryId: null,
          favorite: false,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026, 1, 2),
        ),
      ],
    );

    expect(results, hasLength(1));
    expect(results.first.hitField, SemanticHitField.title);
    expect(results.first.hitSummary, contains('标题：Bank Migration Plan'));
  });
}

EmbeddingChunk _chunk({
  required String id,
  required String sourceId,
  required SearchSourceType sourceType,
  required int chunkIndex,
  required List<double> vector,
}) {
  return EmbeddingChunk(
    id: id,
    sourceType: sourceType,
    sourceId: sourceId,
    chunkIndex: chunkIndex,
    plainTextHash: 'hash-$id',
    modelId: 'embedding-model',
    vectorBlob: utf8.encode(jsonEncode(vector)),
    tokenCount: vector.length,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
}

ModelRegistryEntry _model() {
  return const ModelRegistryEntry(
    id: 'embedding-model',
    type: 'embedding',
    provider: 'builtin',
    name: 'Embedding Model',
    version: '1.0',
    sizeBytes: 1,
    quantization: 'Q8',
    minRamMb: 128,
    recommendedTier: 'mvp',
    localPath: '/tmp/model.onnx',
    checksum: 'abc',
    enabled: true,
    installedAt: null,
    filePresent: true,
  );
}

class _FakeSearchRepository implements SearchRepository {
  _FakeSearchRepository({required this.chunksBySource});

  final Map<(String, SearchSourceType, String), List<EmbeddingChunk>> chunksBySource;

  @override
  Future<List<EmbeddingChunk>> getChunksBySource(
    String sourceId,
    SearchSourceType sourceType,
    String modelId,
  ) async {
    return chunksBySource[(sourceId, sourceType, modelId)] ?? const <EmbeddingChunk>[];
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
  const _FakeEmbeddingEngine();

  @override
  Future<EmbeddingVector> embed(EmbeddingRequest request) async {
    return const EmbeddingVector(values: [1.0, 0.0], tokenCount: 2);
  }

  @override
  Future<EmbeddingEngineState> getState(ModelRegistryEntry model) async {
    return const EmbeddingEngineState(ready: true, reason: 'ok');
  }
}
