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

  _EvaluatedGeneration _evaluateGeneration({
    required String query,
    required List<double> queryVector,
    required EmbeddingIndexSet indexSet,
    required EffectiveSearchPolicy policy,
    required SearchOperation operation,
    required SecretItem? secret,
    required NoteItem? note,
  }) {
    final sourceVaultId = secret?.vaultId ?? note?.vaultId;
    if (sourceVaultId == null || sourceVaultId != indexSet.vaultId) {
      return const _EvaluatedGeneration.corrupt();
    }
    if (indexSet.chunks.isEmpty) {
      return const _EvaluatedGeneration.empty();
    }
    if (queryVector.length != indexSet.vectorDimension) {
      return const _EvaluatedGeneration.corrupt();
    }

    final scored =
        <
          ({
            EmbeddingChunk chunk,
            double rawSimilarity,
            double weight,
            double threshold,
          })
        >[];
    for (final chunk in indexSet.chunks) {
      if (!policy.allows(chunk.sourceField, operation)) {
        continue;
      }
      final decoded = Float32VectorCodec.decode(
        chunk.vectorBlob,
        expectedDimension: indexSet.vectorDimension,
      );
      if (!decoded.isValid) {
        return const _EvaluatedGeneration.corrupt();
      }
      final rawSimilarity = _cosineSimilarity(queryVector, decoded.values);
      final threshold = _qualityPolicy.minimumRawSimilarityFor(
        chunk.sourceField,
      );
      if (rawSimilarity < threshold) {
        continue;
      }
      final weight = _qualityPolicy.rankingWeightFor(chunk.sourceField);
      scored.add((
        chunk: chunk,
        rawSimilarity: rawSimilarity,
        weight: weight,
        threshold: threshold,
      ));
    }
    if (scored.isEmpty) {
      return const _EvaluatedGeneration.empty();
    }

    final chunkTexts = _chunkTexts(policy: policy, secret: secret, note: note);
    final evidence = <SearchEvidence>[];
    for (final score in scored) {
      final chunk = score.chunk;
      final text =
          chunkTexts[_coordinate(chunk.sourceField, chunk.fieldChunkIndex)];
      if (text == null) {
        return const _EvaluatedGeneration.corrupt();
      }
      evidence.add(
        SearchEvidence(
          kind: SearchEvidenceKind.semantic,
          sourceField: chunk.sourceField,
          fieldChunkIndex: chunk.fieldChunkIndex,
          summary: _summaryFor(chunk.sourceField, text),
          rawSimilarity: score.rawSimilarity,
          weight: score.weight,
          rankingScore: score.rawSimilarity * score.weight,
          threshold: score.threshold,
          modelRevisionHash: indexSet.modelRevisionHash,
          fingerprintVersion: indexSet.fingerprintVersion,
          indexConfigVersion: indexSet.indexConfigVersion,
          indexConfigEpoch: indexSet.indexConfigEpoch,
          chunkSchemaVersion: indexSet.chunkSchemaVersion,
          vectorFormatVersion: indexSet.vectorFormatVersion,
        ),
      );
    }
    evidence.sort(_compareEvidence);
    final top = evidence.take(2).toList(growable: false);
    final aggregate =
        top.fold<double>(0, (sum, item) => sum + item.rankingScore!) /
        top.length;
    final primary = evidence.first;
    final item = _resultItem(
      secret: secret,
      note: note,
      preview: primary.summary,
      hitSummary: top.map((item) => item.summary).join('；'),
      hitField: _legacyField(primary.sourceField),
    );
    return _EvaluatedGeneration.result(
      SemanticSearchResult(
        item: item,
        score: aggregate,
        hitSummary: top.map((item) => item.summary).join('；'),
        hitField: _legacyField(primary.sourceField),
        primaryRawSimilarity: primary.rawSimilarity,
        evidence: List<SearchEvidence>.unmodifiable(evidence),
        queryAffinity: _queryAffinity(query, primary.sourceField),
        fieldQualityTier: _fieldQualityTier(primary.sourceField),
      ),
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

  SearchResultItem _resultItem({
    required SecretItem? secret,
    required NoteItem? note,
    required String preview,
    required String hitSummary,
    required SemanticHitField hitField,
  }) {
    if (secret != null) {
      return SearchResultItem(
        id: secret.id,
        type: SearchResultType.secret,
        title: secret.title,
        preview: preview,
        tags: secret.tags,
        favorite: secret.favorite,
        updatedAt: secret.updatedAt,
        matchSources: const <SearchMatchSource>{SearchMatchSource.semantic},
        semanticHitSummary: hitSummary,
        semanticHitField: hitField,
      );
    }
    final item = note!;
    return SearchResultItem(
      id: item.id,
      type: SearchResultType.note,
      title: item.title,
      preview: preview,
      tags: item.tags,
      favorite: item.favorite,
      updatedAt: item.updatedAt,
      matchSources: const <SearchMatchSource>{SearchMatchSource.semantic},
      semanticHitSummary: hitSummary,
      semanticHitField: hitField,
    );
  }

  Map<String, String> _chunkTexts({
    required EffectiveSearchPolicy policy,
    required SecretItem? secret,
    required NoteItem? note,
  }) {
    final document = secret != null
        ? _projector.projectSecret(secret, policy)
        : _projector.projectNote(note!, policy);
    return <String, String>{
      for (final chunk in _chunker.chunk(
        document,
        maxChunkLength: policy.configuration.maxChunkLength,
      ))
        _coordinate(chunk.field, chunk.fieldChunkIndex): chunk.text,
    };
  }

  String _summaryFor(SearchSourceField field, String text) {
    return switch (field) {
      SearchSourceField.secretTitle ||
      SearchSourceField.noteTitle => '标题：$text',
      SearchSourceField.secretUsername => '账号：$text',
      SearchSourceField.secretWebsiteUrl => '网址：$text',
      SearchSourceField.secretNote => '附注：${_truncate(text)}',
      SearchSourceField.secretTags || SearchSourceField.noteTags => '标签：$text',
      SearchSourceField.noteSummary => '摘要：${_truncate(text)}',
      SearchSourceField.noteBody => '正文：${_truncate(text)}',
      SearchSourceField.secretPassword => '',
    };
  }

  String _truncate(String value, {int maxRunes = 72}) {
    final normalized = canonicalText(value);
    final runes = normalized.runes.toList(growable: false);
    if (runes.length <= maxRunes) {
      return normalized;
    }
    return '${String.fromCharCodes(runes.take(maxRunes))}…';
  }

  String _coordinate(SearchSourceField field, int fieldChunkIndex) {
    return '${field.wireName}:$fieldChunkIndex';
  }

  double _cosineSimilarity(List<double> left, List<double> right) {
    var dot = 0.0;
    var leftNorm = 0.0;
    var rightNorm = 0.0;
    for (var index = 0; index < left.length; index++) {
      dot += left[index] * right[index];
      leftNorm += left[index] * left[index];
      rightNorm += right[index] * right[index];
    }
    if (leftNorm == 0 || rightNorm == 0) {
      return -1;
    }
    return dot / (math.sqrt(leftNorm) * math.sqrt(rightNorm));
  }

  int _compareEvidence(SearchEvidence left, SearchEvidence right) {
    final score = right.rankingScore!.compareTo(left.rankingScore!);
    if (score != 0) {
      return score;
    }
    final field = _fieldPriority(
      right.sourceField,
    ).compareTo(_fieldPriority(left.sourceField));
    return field != 0
        ? field
        : left.fieldChunkIndex!.compareTo(right.fieldChunkIndex!);
  }

  int _compareCandidates(
    SemanticSearchResult left,
    SemanticSearchResult right,
  ) {
    var result = right.queryAffinity.compareTo(left.queryAffinity);
    result = result != 0
        ? result
        : right.fieldQualityTier.compareTo(left.fieldQualityTier);
    result = result != 0 ? result : right.score.compareTo(left.score);
    result = result != 0
        ? result
        : _fieldPriority(
            right.evidence.first.sourceField,
          ).compareTo(_fieldPriority(left.evidence.first.sourceField));
    result = result != 0
        ? result
        : (right.item.favorite ? 1 : 0).compareTo(left.item.favorite ? 1 : 0);
    result = result != 0
        ? result
        : right.item.updatedAt.compareTo(left.item.updatedAt);
    result = result != 0
        ? result
        : left.item.type.index.compareTo(right.item.type.index);
    return result != 0 ? result : left.item.id.compareTo(right.item.id);
  }

  int _queryAffinity(String query, SearchSourceField field) {
    if (query.contains('@') && field == SearchSourceField.secretUsername) {
      return 1;
    }
    if ((query.contains('://') || query.contains('.') || query.contains('/')) &&
        field == SearchSourceField.secretWebsiteUrl) {
      return 1;
    }
    if (RegExp(r'^[a-zA-Z0-9_-]{1,24}$').hasMatch(query) &&
        (field == SearchSourceField.secretTags ||
            field == SearchSourceField.noteTags)) {
      return 1;
    }
    return 0;
  }

  int _fieldQualityTier(SearchSourceField field) {
    return switch (field) {
      SearchSourceField.secretTitle ||
      SearchSourceField.noteTitle ||
      SearchSourceField.secretUsername ||
      SearchSourceField.noteSummary => 2,
      _ => 1,
    };
  }

  int _fieldPriority(SearchSourceField field) {
    return switch (field) {
      SearchSourceField.secretTitle || SearchSourceField.noteTitle => 6,
      SearchSourceField.secretUsername || SearchSourceField.noteSummary => 5,
      SearchSourceField.secretWebsiteUrl || SearchSourceField.secretNote => 4,
      SearchSourceField.secretTags || SearchSourceField.noteTags => 3,
      SearchSourceField.noteBody => 2,
      SearchSourceField.secretPassword => 0,
    };
  }

  SemanticHitField _legacyField(SearchSourceField field) {
    return switch (field) {
      SearchSourceField.secretTitle ||
      SearchSourceField.noteTitle => SemanticHitField.title,
      SearchSourceField.secretUsername => SemanticHitField.username,
      SearchSourceField.secretWebsiteUrl => SemanticHitField.url,
      SearchSourceField.secretNote => SemanticHitField.secretNote,
      SearchSourceField.noteSummary => SemanticHitField.summary,
      SearchSourceField.noteBody => SemanticHitField.noteBody,
      SearchSourceField.secretTags ||
      SearchSourceField.noteTags => SemanticHitField.tags,
      SearchSourceField.secretPassword => SemanticHitField.secretNote,
    };
  }

  DatabaseSessionKeyStore get _keys {
    final store = _sessionKeyStore;
    if (store == null) {
      throw StateError('Search index session keys are unavailable.');
    }
    return store;
  }
}

class _EvaluatedGeneration {
  const _EvaluatedGeneration.result(this.result) : corrupt = false;

  const _EvaluatedGeneration.empty() : result = null, corrupt = false;

  const _EvaluatedGeneration.corrupt() : result = null, corrupt = true;

  final SemanticSearchResult? result;
  final bool corrupt;
}
