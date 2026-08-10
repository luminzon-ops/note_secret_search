import 'dart:math' as math;

import 'package:note_secret_search/core/security/crypto_service.dart';
import 'package:note_secret_search/core/security/database_session_keys.dart';
import 'package:note_secret_search/core/security/search_index_fingerprint.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/notes/domain/note_item.dart';
import 'package:note_secret_search/features/search/application/search_index_chunker.dart';
import 'package:note_secret_search/features/search/application/search_index_projector.dart';
import 'package:note_secret_search/features/search/application/semantic_quality_policy.dart';
import 'package:note_secret_search/features/search/domain/effective_search_policy.dart';
import 'package:note_secret_search/features/search/domain/embedding_chunk.dart';
import 'package:note_secret_search/features/search/domain/embedding_engine.dart';
import 'package:note_secret_search/features/search/domain/embedding_index_repository.dart';
import 'package:note_secret_search/features/search/domain/embedding_index_set.dart';
import 'package:note_secret_search/features/search/domain/float32_vector_codec.dart';
import 'package:note_secret_search/features/search/domain/search_configuration.dart';
import 'package:note_secret_search/features/search/domain/search_corpus_reader.dart';
import 'package:note_secret_search/features/search/domain/search_result_item.dart';
import 'package:note_secret_search/features/search/domain/semantic_search_result.dart';
import 'package:note_secret_search/features/secrets/domain/secret_item.dart';

part 'semantic_search_service_paging.dart';
part 'semantic_search_service_scoring.dart';

class SemanticSearchService {
  SemanticSearchService({
    required EmbeddingIndexCorpusRepository repository,
    required EmbeddingEngine embeddingEngine,
    required CryptoService cryptoService,
    DatabaseSessionKeyStore? sessionKeyStore,
    SearchIndexChunker chunker = const SearchIndexChunker(),
    SemanticQualityPolicy qualityPolicy =
        const SemanticQualityPolicy.conservativeMvp(),
  }) : _repository = repository,
       _embeddingEngine = embeddingEngine,
       _projector = SearchIndexProjector(cryptoService: cryptoService),
       _sessionKeyStore = sessionKeyStore,
       _chunker = chunker,
       _qualityPolicy = qualityPolicy;

  final EmbeddingIndexCorpusRepository _repository;
  final EmbeddingEngine _embeddingEngine;
  final SearchIndexProjector _projector;
  final DatabaseSessionKeyStore? _sessionKeyStore;
  final SearchIndexChunker _chunker;
  final SemanticQualityPolicy _qualityPolicy;

  Future<List<SemanticSearchResult>> search({
    required String activeVaultId,
    required String query,
    required SearchConfiguration configuration,
    required String modelRevisionHash,
    required ModelRegistryEntry activeEmbeddingModel,
    required List<SecretItem> secrets,
    required List<NoteItem> notes,
    SearchOperation operation = SearchOperation.semanticSearch,
  }) async {
    final normalizedQuery = query.trim();
    final policy = EffectiveSearchPolicy(configuration);
    if (normalizedQuery.isEmpty) {
      return const <SemanticSearchResult>[];
    }
    if (!configuration.allowLocalEmbedding) {
      while (await _repository.purgeAllIndexSets(batchSize: 100) == 100) {}
      return const <SemanticSearchResult>[];
    }

    final queryVector = await _embeddingEngine.embed(
      EmbeddingRequest(model: activeEmbeddingModel, text: normalizedQuery),
    );
    if (queryVector.values.isEmpty ||
        queryVector.values.any((value) => !value.isFinite)) {
      return const <SemanticSearchResult>[];
    }

    final scopedSecrets = secrets.where(
      (secret) => secret.vaultId == activeVaultId && secret.deletedAt == null,
    );
    final scopedNotes = notes.where(
      (note) => note.vaultId == activeVaultId && note.deletedAt == null,
    );
    final secretById = <String, SecretItem>{
      for (final secret in scopedSecrets) secret.id: secret,
    };
    final noteById = <String, NoteItem>{
      for (final note in scopedNotes) note.id: note,
    };
    final compatibility = _compatibility(
      vaultId: activeVaultId,
      model: activeEmbeddingModel,
      modelRevisionHash: modelRevisionHash,
      configuration: configuration,
    );
    return _searchPages(
      activeVaultId: activeVaultId,
      normalizedQuery: normalizedQuery,
      queryVector: queryVector.values,
      policy: policy,
      operation: operation,
      compatibility: compatibility,
      hydrate: (_) async =>
          _SemanticSourceMaps(secretById: secretById, noteById: noteById),
    );
  }

  Future<List<SemanticSearchResult>> searchCorpus({
    required String activeVaultId,
    required String query,
    required SearchConfiguration configuration,
    required String modelRevisionHash,
    required ModelRegistryEntry activeEmbeddingModel,
    required SearchCorpusReader corpus,
    SearchOperation operation = SearchOperation.semanticSearch,
  }) async {
    final normalizedQuery = query.trim();
    final policy = EffectiveSearchPolicy(configuration);
    if (normalizedQuery.isEmpty) {
      return const <SemanticSearchResult>[];
    }
    if (!configuration.allowLocalEmbedding) {
      while (await _repository.purgeAllIndexSets(batchSize: 100) == 100) {}
      return const <SemanticSearchResult>[];
    }

    final queryVector = await _embeddingEngine.embed(
      EmbeddingRequest(model: activeEmbeddingModel, text: normalizedQuery),
    );
    if (queryVector.values.isEmpty ||
        queryVector.values.any((value) => !value.isFinite)) {
      return const <SemanticSearchResult>[];
    }

    final compatibility = _compatibility(
      vaultId: activeVaultId,
      model: activeEmbeddingModel,
      modelRevisionHash: modelRevisionHash,
      configuration: configuration,
    );
    return _searchPages(
      activeVaultId: activeVaultId,
      normalizedQuery: normalizedQuery,
      queryVector: queryVector.values,
      policy: policy,
      operation: operation,
      compatibility: compatibility,
      hydrate: (page) async {
        final secretIds = <String>[
          for (final set in page)
            if (set.sourceKey.type == SearchSourceType.secret) set.sourceKey.id,
        ];
        final noteIds = <String>[
          for (final set in page)
            if (set.sourceKey.type == SearchSourceType.note) set.sourceKey.id,
        ];
        final secrets = await corpus.secretsByIds(
          vaultId: activeVaultId,
          ids: secretIds,
        );
        final notes = await corpus.notesByIds(
          vaultId: activeVaultId,
          ids: noteIds,
        );
        return _SemanticSourceMaps(
          secretById: <String, SecretItem>{
            for (final secret in secrets)
              if (secret.vaultId == activeVaultId && secret.deletedAt == null)
                secret.id: secret,
          },
          noteById: <String, NoteItem>{
            for (final note in notes)
              if (note.vaultId == activeVaultId && note.deletedAt == null)
                note.id: note,
          },
        );
      },
    );
  }

  EmbeddingIndexCompatibility _compatibility({
    required String vaultId,
    required ModelRegistryEntry model,
    required String modelRevisionHash,
    required SearchConfiguration configuration,
  }) {
    return EmbeddingIndexCompatibility(
      vaultId: vaultId,
      modelId: model.id,
      modelRevisionHash: modelRevisionHash,
      fingerprintKeyId: _keys.requireCurrent().requireKeyId(),
      fingerprintVersion: 1,
      indexConfigVersion: searchIndexConfigurationVersion,
      indexConfigEpoch: configuration.configurationEpoch,
      indexConfigHash: searchIndexConfigurationHash(configuration),
      chunkSchemaVersion: 1,
      vectorFormatVersion: float32VectorFormatVersion,
    );
  }

  DatabaseSessionKeyStore get _keys {
    final store = _sessionKeyStore;
    if (store == null) {
      throw StateError('Search index session keys are unavailable.');
    }
    return store;
  }
}
