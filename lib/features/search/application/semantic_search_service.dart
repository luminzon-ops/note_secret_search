import 'dart:convert';
import 'dart:math' as math;

import 'package:note_secret_search/core/security/crypto_service.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/notes/domain/note_item.dart';
import 'package:note_secret_search/features/search/domain/embedding_chunk.dart';
import 'package:note_secret_search/features/search/domain/embedding_engine.dart';
import 'package:note_secret_search/features/search/domain/search_result_item.dart';
import 'package:note_secret_search/features/search/domain/search_scope.dart';
import 'package:note_secret_search/features/search/domain/search_repository.dart';
import 'package:note_secret_search/features/search/domain/semantic_search_result.dart';
import 'package:note_secret_search/features/secrets/domain/secret_item.dart';
import 'package:note_secret_search/features/search/application/semantic_quality_policy.dart';

class SemanticSearchService {
  const SemanticSearchService({
    required SearchRepository repository,
    required EmbeddingEngine embeddingEngine,
    required CryptoService cryptoService,
    SemanticQualityPolicy qualityPolicy = const SemanticQualityPolicy.conservativeMvp(),
  })  : _repository = repository,
        _embeddingEngine = embeddingEngine,
        _cryptoService = cryptoService,
        _qualityPolicy = qualityPolicy;

  final SearchRepository _repository;
  final EmbeddingEngine _embeddingEngine;
  final CryptoService _cryptoService;
  final SemanticQualityPolicy _qualityPolicy;

  Future<List<SemanticSearchResult>> search({
    required String query,
    required SearchScopeConfig scope,
    required ModelRegistryEntry activeEmbeddingModel,
    required List<SecretItem> secrets,
    required List<NoteItem> notes,
  }) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty || !scope.allowLocalEmbedding) {
      return const <SemanticSearchResult>[];
    }

    final queryVector = await _embeddingEngine.embed(
      EmbeddingRequest(model: activeEmbeddingModel, text: normalizedQuery),
    );

    final candidates = <SemanticSearchResult>[];
    candidates.addAll(await _matchSecrets(queryVector.values, activeEmbeddingModel.id, secrets));
    candidates.addAll(await _matchNotes(queryVector.values, activeEmbeddingModel.id, notes));
    candidates.sort((a, b) {
      final queryAwareSort = _queryAwareFieldPriority(normalizedQuery, b.hitField).compareTo(
        _queryAwareFieldPriority(normalizedQuery, a.hitField),
      );
      if (queryAwareSort != 0) {
        return queryAwareSort;
      }

      final qualitySort = _semanticFieldQualityTier(b.hitField).compareTo(
        _semanticFieldQualityTier(a.hitField),
      );
      if (qualitySort != 0) {
        return qualitySort;
      }
      return b.score.compareTo(a.score);
    });
    return candidates.take(5).toList(growable: false);
  }

  Future<List<SemanticSearchResult>> _matchSecrets(
    List<double> queryVector,
    String modelId,
    List<SecretItem> secrets,
  ) async {
    final results = <SemanticSearchResult>[];
    for (final item in secrets) {
      final chunks = await _repository.getChunksBySource(item.id, SearchSourceType.secret, modelId);
      if (chunks.isEmpty) {
        continue;
      }

      final aggregatedMatch =
          _aggregateChunkMatches(queryVector, chunks, _secretChunkSummaries(item, chunks.length));
      if (aggregatedMatch == null || aggregatedMatch.score <= 0) {
        continue;
      }

      final username = _cryptoService.decryptNullable(item.usernameCiphertext);
      final note = _cryptoService.decryptNullable(item.noteCiphertext);

      results.add(
        SemanticSearchResult(
          item: SearchResultItem(
            id: item.id,
            type: SearchResultType.secret,
            title: item.title,
            preview: username.isNotEmpty ? username : note,
            tags: item.tags,
            favorite: item.favorite,
            updatedAt: item.updatedAt,
            semanticHitSummary: aggregatedMatch.summary,
            semanticHitField: aggregatedMatch.field,
          ),
          score: aggregatedMatch.score,
          hitSummary: aggregatedMatch.summary,
          hitField: aggregatedMatch.field,
        ),
      );
    }
    return results;
  }

  Future<List<SemanticSearchResult>> _matchNotes(
    List<double> queryVector,
    String modelId,
    List<NoteItem> notes,
  ) async {
    final results = <SemanticSearchResult>[];
    for (final item in notes) {
      final chunks = await _repository.getChunksBySource(item.id, SearchSourceType.note, modelId);
      if (chunks.isEmpty) {
        continue;
      }

      final aggregatedMatch =
          _aggregateChunkMatches(queryVector, chunks, _noteChunkSummaries(item, chunks.length));
      if (aggregatedMatch == null || aggregatedMatch.score <= 0) {
        continue;
      }

      final summary = _cryptoService.decryptNullable(item.summaryCacheCiphertext);
      final content = _cryptoService.decryptNullable(item.contentCiphertext);

      results.add(
        SemanticSearchResult(
          item: SearchResultItem(
            id: item.id,
            type: SearchResultType.note,
            title: item.title,
            preview: summary.isNotEmpty ? summary : content,
            tags: item.tags,
            favorite: item.favorite,
            updatedAt: item.updatedAt,
            semanticHitSummary: aggregatedMatch.summary,
            semanticHitField: aggregatedMatch.field,
          ),
          score: aggregatedMatch.score,
          hitSummary: aggregatedMatch.summary,
          hitField: aggregatedMatch.field,
        ),
      );
    }
    return results;
  }

  _ChunkMatch? _aggregateChunkMatches(
    List<double> queryVector,
    List<EmbeddingChunk> chunks,
    List<_ChunkDescriptor> chunkSummaries,
  ) {
    final matches = <_ChunkMatch>[];
    for (var index = 0; index < chunks.length; index++) {
      final chunk = chunks[index];
      if (chunk.vectorBlob == null) {
        continue;
      }
      final vector = _decodeVector(chunk.vectorBlob!);
      final rawScore = _cosineSimilarity(queryVector, vector);
      if (rawScore <= 0) {
        continue;
      }
      final descriptor = index < chunkSummaries.length
          ? chunkSummaries[index]
          : _ChunkDescriptor(
              summary: '命中分片 ${chunk.chunkIndex + 1}',
              field: SemanticHitField.noteBody,
            );
      final weightedScore = rawScore * _semanticFieldWeight(descriptor.field);
      if (!_passesSemanticQualityGate(weightedScore, descriptor.field)) {
        continue;
      }
      matches.add(
        _ChunkMatch(score: weightedScore, summary: descriptor.summary, field: descriptor.field),
      );
    }

    if (matches.isEmpty) {
      return null;
    }

    matches.sort((a, b) => b.score.compareTo(a.score));
    final topMatches = matches.take(2).toList(growable: false);
    final combinedScore = topMatches.fold<double>(0, (sum, match) => sum + match.score) /
        topMatches.length;
    final combinedSummary = topMatches.map((match) => match.summary).join('；');
    return _ChunkMatch(
      score: combinedScore,
      summary: combinedSummary,
      field: topMatches.first.field,
    );
  }

  List<_ChunkDescriptor> _secretChunkSummaries(SecretItem item, int chunkCount) {
    final username = _cryptoService.decryptNullable(item.usernameCiphertext);
    final website = _cryptoService.decryptNullable(item.websiteUrlCiphertext);
    final note = _cryptoService.decryptNullable(item.noteCiphertext);

    final candidates = <_ChunkDescriptor>[
      _ChunkDescriptor(summary: '标题：${item.title}', field: SemanticHitField.title),
      if (username.isNotEmpty)
        _ChunkDescriptor(summary: '账号：$username', field: SemanticHitField.username),
      if (website.isNotEmpty)
        _ChunkDescriptor(summary: '网址：$website', field: SemanticHitField.url),
      if (note.isNotEmpty)
        _ChunkDescriptor(
          summary: '附注：${_truncate(note)}',
          field: SemanticHitField.secretNote,
        ),
      if (item.tags.isNotEmpty)
        _ChunkDescriptor(summary: '标签：${item.tags.join('、')}', field: SemanticHitField.tags),
    ];

    return _expandSummaries(candidates, chunkCount);
  }

  List<_ChunkDescriptor> _noteChunkSummaries(NoteItem item, int chunkCount) {
    final summary = _cryptoService.decryptNullable(item.summaryCacheCiphertext);
    final content = _cryptoService.decryptNullable(item.contentCiphertext);
    final paragraphs = content
        .split(RegExp(r'\n{2,}'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);

    final candidates = <_ChunkDescriptor>[
      _ChunkDescriptor(summary: '标题：${item.title}', field: SemanticHitField.title),
      if (summary.isNotEmpty)
        _ChunkDescriptor(summary: '摘要：${_truncate(summary)}', field: SemanticHitField.summary),
      ...paragraphs.map(
        (part) => _ChunkDescriptor(
          summary: '正文：${_truncate(part)}',
          field: SemanticHitField.noteBody,
        ),
      ),
      if (item.tags.isNotEmpty)
        _ChunkDescriptor(summary: '标签：${item.tags.join('、')}', field: SemanticHitField.tags),
    ];

    return _expandSummaries(candidates, chunkCount);
  }

  List<_ChunkDescriptor> _expandSummaries(List<_ChunkDescriptor> candidates, int chunkCount) {
    if (candidates.isEmpty) {
      return List<_ChunkDescriptor>.generate(
        chunkCount,
        (index) => _ChunkDescriptor(
          summary: '命中分片 ${index + 1}',
          field: SemanticHitField.noteBody,
        ),
      );
    }

    final summaries = <_ChunkDescriptor>[];
    for (var index = 0; index < chunkCount; index++) {
      summaries.add(candidates[index % candidates.length]);
    }
    return summaries;
  }

  String _truncate(String value, {int maxLength = 72}) {
    final normalized = value.trim();
    if (normalized.length <= maxLength) {
      return normalized;
    }
    return '${normalized.substring(0, maxLength)}…';
  }

  List<double> _decodeVector(List<int> blob) {
    final decoded = jsonDecode(utf8.decode(blob));
    if (decoded is! List) {
      return const <double>[];
    }
    return decoded.map((value) => (value as num).toDouble()).toList(growable: false);
  }

  double _cosineSimilarity(List<double> left, List<double> right) {
    if (left.isEmpty || right.isEmpty || left.length != right.length) {
      return 0;
    }

    var dot = 0.0;
    var leftNorm = 0.0;
    var rightNorm = 0.0;
    for (var index = 0; index < left.length; index++) {
      dot += left[index] * right[index];
      leftNorm += left[index] * left[index];
      rightNorm += right[index] * right[index];
    }

    if (leftNorm == 0 || rightNorm == 0) {
      return 0;
    }

    return dot / (math.sqrt(leftNorm) * math.sqrt(rightNorm));
  }

  double _semanticFieldWeight(SemanticHitField field) {
    switch (field) {
      case SemanticHitField.title:
        return 1.16;
      case SemanticHitField.username:
      case SemanticHitField.summary:
        return 1.1;
      case SemanticHitField.url:
      case SemanticHitField.secretNote:
        return 1.04;
      case SemanticHitField.tags:
        return 0.96;
      case SemanticHitField.noteBody:
        return 0.92;
    }
  }

  bool _passesSemanticQualityGate(double score, SemanticHitField field) {
    return score >= _qualityPolicy.minimumThresholdFor(field);
  }

  int _queryAwareFieldPriority(String query, SemanticHitField field) {
    if (_isAccountLikeQuery(query) && field == SemanticHitField.username) {
      return 1;
    }

    if (_isUrlLikeQuery(query) && field == SemanticHitField.url) {
      return 1;
    }

    if (_isTagLikeQuery(query) && field == SemanticHitField.tags) {
      return 1;
    }

    return 0;
  }

  bool _isUrlLikeQuery(String query) {
    return query.contains('://') || query.contains('.') || query.contains('/');
  }

  bool _isAccountLikeQuery(String query) {
    return query.contains('@');
  }

  bool _isTagLikeQuery(String query) {
    if (query.isEmpty || query.length > 24) {
      return false;
    }

    if (query.contains(' ') || query.contains('@') || _isUrlLikeQuery(query)) {
      return false;
    }

    return RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(query);
  }

  int _semanticFieldQualityTier(SemanticHitField field) {
    switch (field) {
      case SemanticHitField.title:
      case SemanticHitField.username:
      case SemanticHitField.summary:
        return 1;
      case SemanticHitField.url:
      case SemanticHitField.secretNote:
      case SemanticHitField.tags:
      case SemanticHitField.noteBody:
        return 0;
    }
  }
}

class _ChunkMatch {
  const _ChunkMatch({
    required this.score,
    required this.summary,
    required this.field,
  });

  final double score;
  final String summary;
  final SemanticHitField field;
}

class _ChunkDescriptor {
  const _ChunkDescriptor({
    required this.summary,
    required this.field,
  });

  final String summary;
  final SemanticHitField field;
}
