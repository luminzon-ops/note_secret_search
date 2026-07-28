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
import 'package:note_secret_search/features/search/application/search_index_write_fence.dart';
import 'package:note_secret_search/features/search/domain/embedding_chunk.dart';
import 'package:note_secret_search/features/search/domain/embedding_engine.dart';
import 'package:note_secret_search/features/search/domain/embedding_index_repository.dart';
import 'package:note_secret_search/features/search/domain/embedding_index_set.dart';
import 'package:note_secret_search/features/search/domain/effective_search_policy.dart';
import 'package:note_secret_search/features/search/domain/float32_vector_codec.dart';
import 'package:note_secret_search/features/search/domain/search_configuration.dart';
import 'package:note_secret_search/features/search/domain/search_corpus_reader.dart';
import 'package:note_secret_search/features/search/domain/search_index_document.dart';
import 'package:note_secret_search/features/search/domain/search_index_status.dart';
import 'package:note_secret_search/features/secrets/domain/secret_item.dart';

part 'search_index_service_corpus.dart';
part 'search_index_service_status.dart';
part 'search_index_service_write.dart';

class SearchIndexService {
  SearchIndexService({
    required EmbeddingIndexRepository repository,
    EmbeddingIndexCorpusRepository? corpusRepository,
    required CryptoService cryptoService,
    required EmbeddingEngine embeddingEngine,
    DatabaseSessionKeyStore? sessionKeyStore,
    SearchIndexWriteFence? writeFence,
    SearchIndexChunker chunker = const SearchIndexChunker(),
    DateTime Function()? clock,
  }) : _repository = repository,
       _corpusRepository =
           corpusRepository ??
           (repository is EmbeddingIndexCorpusRepository
               ? repository as EmbeddingIndexCorpusRepository
               : null),
       _projector = SearchIndexProjector(cryptoService: cryptoService),
       _embeddingEngine = embeddingEngine,
       _sessionKeyStore = sessionKeyStore,
       _writeFence = writeFence,
       _chunker = chunker,
       _clock = clock ?? DateTime.now;

  final EmbeddingIndexRepository _repository;
  final EmbeddingIndexCorpusRepository? _corpusRepository;
  final SearchIndexProjector _projector;
  final EmbeddingEngine _embeddingEngine;
  final DatabaseSessionKeyStore? _sessionKeyStore;
  final SearchIndexWriteFence? _writeFence;
  final SearchIndexChunker _chunker;
  final DateTime Function() _clock;

  Future<SearchIndexStatus> buildStatus({
    required List<SecretItem> secrets,
    required List<NoteItem> notes,
    required ModelRegistryEntry? activeEmbeddingModel,
    required String modelRevisionHash,
    required SearchConfiguration configuration,
  }) {
    return _buildStatus(
      secrets: secrets,
      notes: notes,
      activeEmbeddingModel: activeEmbeddingModel,
      modelRevisionHash: modelRevisionHash,
      configuration: configuration,
    );
  }

  Future<SearchIndexStatus> buildCorpusStatus({
    required String activeVaultId,
    required SearchCorpusReader corpus,
    required ModelRegistryEntry? activeEmbeddingModel,
    required String modelRevisionHash,
    required SearchConfiguration configuration,
  }) {
    return _buildCorpusStatus(
      activeVaultId: activeVaultId,
      corpus: corpus,
      activeEmbeddingModel: activeEmbeddingModel,
      modelRevisionHash: modelRevisionHash,
      configuration: configuration,
    );
  }

  Future<int> indexCorpusPending({
    required String activeVaultId,
    required SearchCorpusReader corpus,
    required ModelRegistryEntry activeEmbeddingModel,
    required String modelRevisionHash,
    required SearchConfiguration configuration,
  }) async {
    final writeContext = _captureWriteContext();
    try {
      return await _indexCorpusPending(
        activeVaultId: activeVaultId,
        corpus: corpus,
        activeEmbeddingModel: activeEmbeddingModel,
        modelRevisionHash: modelRevisionHash,
        configuration: configuration,
        writeContext: writeContext,
      );
    } finally {
      writeContext.release();
    }
  }

  Future<void> indexPendingItems({
    required List<SearchIndexPendingItem> items,
    required ModelRegistryEntry activeEmbeddingModel,
    required String modelRevisionHash,
    required SearchConfiguration configuration,
  }) async {
    final writeContext = _captureWriteContext();
    try {
      await _replacePendingItems(
        items: items,
        activeEmbeddingModel: activeEmbeddingModel,
        modelRevisionHash: modelRevisionHash,
        configuration: configuration,
        writeContext: writeContext,
      );
    } finally {
      writeContext.release();
    }
  }
}
