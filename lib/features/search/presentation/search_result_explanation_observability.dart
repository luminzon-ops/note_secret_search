part of 'search_result_explanation.dart';

SearchObservabilitySummary buildSearchObservabilitySummary(
  List<SearchResultItem> unifiedResults, {
  List<SemanticSearchResult> semanticResults = const <SemanticSearchResult>[],
  SearchFusionDiagnostics? fusionDiagnostics,
}) {
  var dualCount = 0;
  var keywordPrimaryCount = 0;
  var semanticAssistCount = 0;

  final fieldCounts = <SemanticHitField, int>{};
  final semanticEvidence = <SearchEvidence>[];

  for (final item in unifiedResults) {
    switch (classifySearchResultHit(item)) {
      case SearchResultHitLabel.dual:
        dualCount++;
        break;
      case SearchResultHitLabel.keywordPrimary:
        keywordPrimaryCount++;
        break;
      case SearchResultHitLabel.semanticAssist:
        semanticAssistCount++;
        break;
    }

    if (item.matchSources.contains(SearchMatchSource.semantic)) {
      final evidence = item.evidence
          .where((item) => item.kind == SearchEvidenceKind.semantic)
          .toList(growable: false);
      if (evidence.isNotEmpty) {
        semanticEvidence.addAll(evidence);
        for (final item in evidence) {
          final field = _semanticHitField(item.sourceField);
          fieldCounts.update(field, (count) => count + 1, ifAbsent: () => 1);
        }
      } else if (item.semanticHitField case final field?) {
        fieldCounts.update(field, (count) => count + 1, ifAbsent: () => 1);
      }
    }
  }

  final tierCounts = countSemanticExplanationTiers(unifiedResults);
  final dominantSignal = _resolveDominantSignal(
    dualCount: dualCount,
    keywordPrimaryCount: keywordPrimaryCount,
    semanticAssistCount: semanticAssistCount,
  );
  final dominantField = _resolveDominantField(fieldCounts);
  final reminderHint = _buildReminderHint(
    dominantSignal: dominantSignal,
    dominantField: dominantField,
    dualCount: dualCount,
    keywordPrimaryCount: keywordPrimaryCount,
    semanticAssistCount: semanticAssistCount,
    highQualitySemanticCount: tierCounts.highQualityCount,
    assistSemanticCount: tierCounts.assistCount,
  );

  final semanticFieldBreakdown = fieldCounts.isEmpty
      ? null
      : '字段分布：${fieldCounts.entries.map((entry) => '${_semanticFieldObservabilityLabel(entry.key)} ${entry.value} 条').join('，')}。';
  final semanticVersionBreakdown = _buildSemanticVersionBreakdown(
    semanticEvidence,
  );
  final diagnostics =
      fusionDiagnostics ??
      const SearchFusionService().diagnoseFinalResults(
        unifiedResults: unifiedResults,
        semanticResults: semanticResults,
      );
  final semanticOnlyFilteringBreakdown = _buildSemanticOnlyFilteringBreakdown(
    diagnostics,
  );
  final semanticOnlyFilteringReason = semanticOnlyFilteringBreakdown == null
      ? null
      : '过滤原因：低质量补充语义线索 '
            '${diagnostics.rejectionCount(SearchFusionRejectionReason.weakSemanticAssist)} 条，'
            '结果上限截断 '
            '${diagnostics.rejections.where((item) => item.reason == SearchFusionRejectionReason.finalResultLimit).length} 条。';

  return SearchObservabilitySummary(
    hitBreakdown:
        '命中结构：双命中 $dualCount 条，关键词优先 $keywordPrimaryCount 条，语义命中 $semanticAssistCount 条。',
    semanticTierBreakdown:
        '语义分层：重点 ${tierCounts.highQualityCount} 条，补充线索 ${tierCounts.assistCount} 条。',
    dominantSignalHint: _buildDominantSignalHint(
      dominantSignal,
      switch (dominantSignal) {
        SearchResultHitLabel.dual => dualCount,
        SearchResultHitLabel.keywordPrimary => keywordPrimaryCount,
        SearchResultHitLabel.semanticAssist => semanticAssistCount,
      },
    ),
    semanticFieldBreakdown: semanticFieldBreakdown,
    semanticVersionBreakdown: semanticVersionBreakdown,
    semanticOnlyFilteringBreakdown: semanticOnlyFilteringBreakdown,
    semanticOnlyFilteringReason: semanticOnlyFilteringReason,
    dominantFieldHint: dominantField == null
        ? null
        : _buildDominantFieldHint(dominantField, fieldCounts[dominantField]!),
    reminderHint: reminderHint,
  );
}

String? _buildSemanticVersionBreakdown(List<SearchEvidence> evidence) {
  final versions =
      <
        ({int fingerprint, int configuration, int epoch, int chunk, int vector})
      >{};
  final modelRevisions = <String>{};
  for (final item in evidence) {
    final fingerprint = item.fingerprintVersion;
    final configuration = item.indexConfigVersion;
    final epoch = item.indexConfigEpoch;
    final chunk = item.chunkSchemaVersion;
    final vector = item.vectorFormatVersion;
    if (fingerprint != null &&
        configuration != null &&
        epoch != null &&
        chunk != null &&
        vector != null) {
      versions.add((
        fingerprint: fingerprint,
        configuration: configuration,
        epoch: epoch,
        chunk: chunk,
        vector: vector,
      ));
    }
    if (item.modelRevisionHash case final revision? when revision.isNotEmpty) {
      modelRevisions.add(revision);
    }
  }
  if (versions.isEmpty) {
    return null;
  }

  final ordered = versions.toList(growable: false)
    ..sort(
      (left, right) =>
          '${left.fingerprint}:${left.configuration}:${left.epoch}:'
                  '${left.chunk}:${left.vector}'
              .compareTo(
                '${right.fingerprint}:${right.configuration}:${right.epoch}:'
                '${right.chunk}:${right.vector}',
              ),
    );
  final versionText = ordered
      .map(
        (item) =>
            '指纹 v${item.fingerprint}，配置 v${item.configuration}/e${item.epoch}，'
            '分块 v${item.chunk}，向量 v${item.vector}',
      )
      .join('；');
  final revisionText = modelRevisions.isEmpty
      ? ''
      : '；模型修订 ${modelRevisions.length} 组';
  return '索引版本：$versionText$revisionText。';
}

String? _buildSemanticOnlyFilteringBreakdown(
  SearchFusionDiagnostics diagnostics,
) {
  if (diagnostics.semanticOnlyCandidateCount == 0 ||
      diagnostics.rejections.isEmpty) {
    return null;
  }

  final filteredSemanticOnlyCount = diagnostics.rejections
      .where((item) => item.semanticOnly)
      .length;
  return '语义过滤：语义直达候选 '
      '${diagnostics.semanticOnlyCandidateCount} 条，保留 '
      '${diagnostics.keptSemanticOnlyCount} 条，过滤 '
      '$filteredSemanticOnlyCount 条。';
}

String? _buildReminderHint({
  required SearchResultHitLabel dominantSignal,
  required SemanticHitField? dominantField,
  required int dualCount,
  required int keywordPrimaryCount,
  required int semanticAssistCount,
  required int highQualitySemanticCount,
  required int assistSemanticCount,
}) {
  final weakSemanticParticipation =
      dualCount + semanticAssistCount <= keywordPrimaryCount;
  if (dominantSignal == SearchResultHitLabel.keywordPrimary &&
      weakSemanticParticipation) {
    return '当前结果主要由关键词命中主导，语义链路参与较弱。';
  }

  const assistFields = <SemanticHitField>{
    SemanticHitField.url,
    SemanticHitField.secretNote,
    SemanticHitField.noteBody,
    SemanticHitField.tags,
  };
  if (dominantField != null && assistFields.contains(dominantField)) {
    return '当前语义参与主要来自辅助字段，建议谨慎判断结果质量。';
  }

  const highValueFields = <SemanticHitField>{
    SemanticHitField.title,
    SemanticHitField.username,
    SemanticHitField.summary,
  };
  if (dominantField != null &&
      highValueFields.contains(dominantField) &&
      highQualitySemanticCount + assistSemanticCount > 1 &&
      highQualitySemanticCount > assistSemanticCount) {
    return '当前语义命中集中在高价值字段，可优先检查前排结果。';
  }

  return null;
}

SearchResultHitLabel _resolveDominantSignal({
  required int dualCount,
  required int keywordPrimaryCount,
  required int semanticAssistCount,
}) {
  final counts = <SearchResultHitLabel, int>{
    SearchResultHitLabel.dual: dualCount,
    SearchResultHitLabel.keywordPrimary: keywordPrimaryCount,
    SearchResultHitLabel.semanticAssist: semanticAssistCount,
  };

  const priority = <SearchResultHitLabel>[
    SearchResultHitLabel.dual,
    SearchResultHitLabel.keywordPrimary,
    SearchResultHitLabel.semanticAssist,
  ];

  var dominant = SearchResultHitLabel.dual;
  var dominantCount = -1;
  for (final label in priority) {
    final count = counts[label] ?? 0;
    if (count > dominantCount) {
      dominant = label;
      dominantCount = count;
    }
  }

  return dominant;
}

String _buildDominantSignalHint(SearchResultHitLabel label, int count) {
  switch (label) {
    case SearchResultHitLabel.dual:
      return '当前结果主要由双命中主导（$count 条）。';
    case SearchResultHitLabel.keywordPrimary:
      return '当前结果主要由关键词命中主导（$count 条）。';
    case SearchResultHitLabel.semanticAssist:
      return '当前结果主要由语义召回主导（$count 条）。';
  }
}

SemanticHitField? _resolveDominantField(
  Map<SemanticHitField, int> fieldCounts,
) {
  if (fieldCounts.isEmpty) {
    return null;
  }

  const priority = <SemanticHitField>[
    SemanticHitField.title,
    SemanticHitField.username,
    SemanticHitField.summary,
    SemanticHitField.url,
    SemanticHitField.secretNote,
    SemanticHitField.noteBody,
    SemanticHitField.tags,
  ];

  var dominant = priority.first;
  var dominantCount = -1;
  for (final field in priority) {
    final count = fieldCounts[field] ?? 0;
    if (count > dominantCount) {
      dominant = field;
      dominantCount = count;
    }
  }

  return dominantCount > 0 ? dominant : null;
}

String _buildDominantFieldHint(SemanticHitField field, int count) {
  return '当前语义命中主要集中在${_semanticFieldObservabilityLabel(field)}字段（$count 条）。';
}

String _semanticFieldObservabilityLabel(SemanticHitField field) {
  switch (field) {
    case SemanticHitField.title:
      return '标题';
    case SemanticHitField.username:
      return '账号';
    case SemanticHitField.url:
      return '网址';
    case SemanticHitField.secretNote:
      return '附注';
    case SemanticHitField.summary:
      return '摘要';
    case SemanticHitField.noteBody:
      return '正文';
    case SemanticHitField.tags:
      return '标签';
  }
}

SemanticHitField _semanticHitField(SearchSourceField field) {
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
