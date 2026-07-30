part of 'semantic_search_service.dart';

extension _SemanticSearchScoring on SemanticSearchService {
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
}

class _EvaluatedGeneration {
  const _EvaluatedGeneration.result(this.result) : corrupt = false;

  const _EvaluatedGeneration.empty() : result = null, corrupt = false;

  const _EvaluatedGeneration.corrupt() : result = null, corrupt = true;

  final SemanticSearchResult? result;
  final bool corrupt;
}
