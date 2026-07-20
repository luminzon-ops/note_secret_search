import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:note_secret_search/core/security/crypto_service.dart';
import 'package:note_secret_search/core/security/database_session_keys.dart';
import 'package:note_secret_search/core/security/search_index_fingerprint.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/notes/domain/note_item.dart';
import 'package:note_secret_search/features/search/application/search_index_chunker.dart';
import 'package:note_secret_search/features/search/application/search_index_projector.dart';
import 'package:note_secret_search/features/search/domain/embedding_chunk.dart';
import 'package:note_secret_search/features/search/domain/embedding_engine.dart';
import 'package:note_secret_search/features/search/domain/embedding_index_repository.dart';
import 'package:note_secret_search/features/search/domain/embedding_index_set.dart';
import 'package:note_secret_search/features/search/domain/effective_search_policy.dart';
import 'package:note_secret_search/features/search/domain/float32_vector_codec.dart';
import 'package:note_secret_search/features/search/domain/search_configuration.dart';
import 'package:note_secret_search/features/search/domain/search_index_document.dart';
import 'package:note_secret_search/features/search/domain/search_index_status.dart';
import 'package:note_secret_search/features/secrets/domain/secret_item.dart';

class SearchIndexService {
  SearchIndexService({
    required EmbeddingIndexRepository repository,
    required CryptoService cryptoService,
    required EmbeddingEngine embeddingEngine,
    DatabaseSessionKeyStore? sessionKeyStore,
    SearchIndexChunker chunker = const SearchIndexChunker(),
    DateTime Function()? clock,
  }) : _repository = repository,
       _projector = SearchIndexProjector(cryptoService: cryptoService),
       _embeddingEngine = embeddingEngine,
       _sessionKeyStore = sessionKeyStore,
       _chunker = chunker,
       _clock = clock ?? DateTime.now;

  final EmbeddingIndexRepository _repository;
  final SearchIndexProjector _projector;
  final EmbeddingEngine _embeddingEngine;
  final DatabaseSessionKeyStore? _sessionKeyStore;
  final SearchIndexChunker _chunker;
  final DateTime Function() _clock;

  Future<SearchIndexStatus> buildStatus({
    required List<SecretItem> secrets,
    required List<NoteItem> notes,
    required ModelRegistryEntry? activeEmbeddingModel,
    required String modelRevisionHash,
    required SearchConfiguration configuration,
  }) async {
    if (activeEmbeddingModel == null) {
      return const SearchIndexStatus(
        engineReady: false,
        engineReason: '尚未配置可用的本地 embedding 模型。',
        hasActiveEmbeddingModel: false,
        pendingItems: <SearchIndexPendingItem>[],
      );
    }

    final engineState = await _embeddingEngine.getState(activeEmbeddingModel);
    if (!configuration.allowLocalEmbedding) {
      return SearchIndexStatus(
        engineReady: engineState.ready,
        engineReason: engineState.reason,
        hasActiveEmbeddingModel: true,
        pendingItems: const <SearchIndexPendingItem>[],
      );
    }

    final policy = EffectiveSearchPolicy(configuration);
    final configHash = _configurationHash(configuration);
    final pending = <SearchIndexPendingItem>[];
    for (final secret in secrets) {
      final document = _projector.projectSecret(secret, policy);
      final item = await _pendingItem(
        document: document,
        model: activeEmbeddingModel,
        modelRevisionHash: modelRevisionHash,
        configuration: configuration,
        configHash: configHash,
      );
      if (item != null) {
        pending.add(item);
      }
    }
    for (final note in notes) {
      final document = _projector.projectNote(note, policy);
      final item = await _pendingItem(
        document: document,
        model: activeEmbeddingModel,
        modelRevisionHash: modelRevisionHash,
        configuration: configuration,
        configHash: configHash,
      );
      if (item != null) {
        pending.add(item);
      }
    }

    pending.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    return SearchIndexStatus(
      engineReady: engineState.ready,
      engineReason: engineState.reason,
      hasActiveEmbeddingModel: true,
      pendingItems: pending,
    );
  }

  Future<void> indexPendingItems({
    required List<SearchIndexPendingItem> items,
    required ModelRegistryEntry activeEmbeddingModel,
    required String modelRevisionHash,
    required SearchConfiguration configuration,
  }) async {
    for (final item in items) {
      final document = item.document;
      if (document == null ||
          item.configurationEpoch != configuration.configurationEpoch ||
          item.modelRevisionHash != modelRevisionHash) {
        throw const EmbeddingIndexStaleWriteException();
      }
      final textChunks = _chunker.chunk(
        document,
        maxChunkLength: configuration.maxChunkLength,
      );
      final now = _clock();
      final setId = _setId(document.sourceKey, activeEmbeddingModel.id);
      final embeddedChunks = <EmbeddingChunk>[];
      int? vectorDimension;
      for (final textChunk in textChunks) {
        final vector = await _embeddingEngine.embed(
          EmbeddingRequest(model: activeEmbeddingModel, text: textChunk.text),
        );
        final dimension = vector.values.length;
        if (dimension == 0 ||
            (vectorDimension != null && vectorDimension != dimension)) {
          throw StateError('Embedding vector dimensions are inconsistent.');
        }
        vectorDimension = dimension;
        final chunkFingerprint = _withFingerprintKey(
          (key) => chunkFingerprintBytes(
            key: key,
            sourceType: document.sourceKey.type.name,
            sourceId: document.sourceKey.id,
            sourceField: textChunk.field.wireName,
            fieldChunkIndex: textChunk.fieldChunkIndex,
            text: textChunk.text,
          ),
        );
        embeddedChunks.add(
          EmbeddingChunk(
            id: _chunkId(setId, textChunk.field, textChunk.fieldChunkIndex),
            indexSetId: setId,
            sourceField: textChunk.field,
            fieldChunkIndex: textChunk.fieldChunkIndex,
            chunkFingerprint: chunkFingerprint,
            vectorBlob: Float32VectorCodec.encode(vector.values),
            tokenCount: vector.tokenCount,
            createdAt: now,
          ),
        );
      }
      final sourceFingerprint = _sourceFingerprint(document);
      await _repository.replaceIndexSet(
        EmbeddingIndexSet(
          id: setId,
          sourceKey: document.sourceKey,
          vaultId: document.vaultId,
          modelId: activeEmbeddingModel.id,
          modelRevisionHash: modelRevisionHash,
          sourceUpdatedAt: document.updatedAt,
          sourceFingerprint: sourceFingerprint,
          fingerprintKeyId: _keys.requireCurrent().requireKeyId(),
          fingerprintVersion: searchIndexFingerprintVersion,
          indexConfigVersion: searchIndexConfigurationVersion,
          indexConfigEpoch: configuration.configurationEpoch,
          indexConfigHash: _configurationHash(configuration),
          chunkSchemaVersion: 1,
          vectorFormatVersion: float32VectorFormatVersion,
          vectorDimension: vectorDimension ?? 0,
          chunks: embeddedChunks,
          createdAt: now,
        ),
      );
    }
  }

  Future<SearchIndexPendingItem?> _pendingItem({
    required SearchIndexDocument document,
    required ModelRegistryEntry model,
    required String modelRevisionHash,
    required SearchConfiguration configuration,
    required String configHash,
  }) async {
    final sourceFingerprint = _sourceFingerprint(document);
    final keyId = _keys.requireCurrent().requireKeyId();
    final current = await _repository.getIndexSetBySource(
      document.sourceKey,
      model.id,
    );
    if (current != null &&
        current.vaultId == document.vaultId &&
        current.modelRevisionHash == modelRevisionHash &&
        current.sourceUpdatedAt == document.updatedAt &&
        _bytesEqual(current.sourceFingerprint, sourceFingerprint) &&
        current.fingerprintKeyId == keyId &&
        current.fingerprintVersion == searchIndexFingerprintVersion &&
        current.indexConfigVersion == searchIndexConfigurationVersion &&
        current.indexConfigEpoch == configuration.configurationEpoch &&
        current.indexConfigHash == configHash &&
        current.chunkSchemaVersion == 1 &&
        current.vectorFormatVersion == float32VectorFormatVersion) {
      return null;
    }
    return SearchIndexPendingItem(
      sourceId: document.sourceKey.id,
      sourceType: document.sourceKey.type,
      title: document.title,
      updatedAt: document.updatedAt,
      document: document,
      sourceFingerprint: sourceFingerprint,
      configurationEpoch: configuration.configurationEpoch,
      modelRevisionHash: modelRevisionHash,
    );
  }

  List<int> _sourceFingerprint(SearchIndexDocument document) {
    return _withFingerprintKey(
      (key) => structuredSourceFingerprintBytes(
        key: key,
        sourceType: document.sourceKey.type.name,
        sourceId: document.sourceKey.id,
        vaultId: document.vaultId,
        fields: document.fields.map(
          (field) => (id: field.field.wireName, values: field.values),
        ),
      ),
    );
  }

  T _withFingerprintKey<T>(T Function(Uint8List key) consume) {
    return _keys.requireCurrent().withSearchIndexFingerprintKey(consume);
  }

  DatabaseSessionKeyStore get _keys {
    final store = _sessionKeyStore;
    if (store == null) {
      throw StateError('Search index session keys are unavailable.');
    }
    return store;
  }

  String _configurationHash(SearchConfiguration configuration) {
    return sha256
        .convert(utf8.encode(jsonEncode(configuration.indexProjectionJson())))
        .toString();
  }

  String _setId(SearchSourceKey key, String modelId) {
    final digest = sha256
        .convert(
          utf8.encode(jsonEncode(<String>[key.type.name, key.id, modelId])),
        )
        .toString();
    return 'embedding-set-$digest';
  }

  String _chunkId(String setId, SearchSourceField field, int fieldChunkIndex) {
    return '$setId:${field.wireName}:$fieldChunkIndex';
  }

  bool _bytesEqual(List<int> left, List<int> right) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) {
        return false;
      }
    }
    return true;
  }
}
