import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/search/application/search_fusion_service.dart';
import 'package:note_secret_search/features/search/domain/embedding_chunk.dart';
import 'package:note_secret_search/features/search/domain/search_result_item.dart';
import 'package:note_secret_search/features/search/domain/semantic_search_result.dart';

SearchResultItem _keywordItem(
  String id, {
  SearchResultType type = SearchResultType.secret,
  bool favorite = false,
  DateTime? updatedAt,
  List<SearchSourceField> keywordHitFields = const <SearchSourceField>[],
}) {
  return SearchResultItem(
    id: id,
    type: type,
    title: 'Title $id',
    preview: 'Preview $id',
    tags: const <String>[],
    favorite: favorite,
    updatedAt: updatedAt ?? DateTime(2026, 4, 22),
    matchSources: const {SearchMatchSource.keyword},
    keywordHitFields: keywordHitFields,
  );
}

SemanticSearchResult _semanticResult(
  String id, {
  SearchResultType type = SearchResultType.secret,
  required double score,
  required SemanticHitField hitField,
  bool favorite = false,
  DateTime? updatedAt,
  List<SearchEvidence> evidence = const <SearchEvidence>[],
}) {
  return SemanticSearchResult(
    item: SearchResultItem(
      id: id,
      type: type,
      title: 'Title $id',
      preview: 'Preview $id',
      tags: const <String>[],
      favorite: favorite,
      updatedAt: updatedAt ?? DateTime(2026, 4, 22),
    ),
    score: score,
    hitSummary: '${hitField.name}: $id',
    hitField: hitField,
    primaryRawSimilarity: 0.88,
    evidence: evidence,
  );
}

void main() {
  const service = SearchFusionService();

  test(
    'ranks dual-hit high-quality result above semantic-only assist result even with lower score',
    () {
      final results = service.fuse(
        keywordResults: [_keywordItem('dual')],
        semanticResults: [
          _semanticResult(
            'dual',
            score: 0.72,
            hitField: SemanticHitField.title,
          ),
          _semanticResult(
            'assist',
            score: 0.95,
            hitField: SemanticHitField.tags,
          ),
        ],
      );

      expect(results.map((item) => item.id).toList(), ['dual', 'assist']);
    },
  );

  test(
    'ranks semantic-only high-quality result above semantic-only assist result',
    () {
      final results = service.fuse(
        keywordResults: const <SearchResultItem>[],
        semanticResults: [
          _semanticResult(
            'assist',
            score: 0.95,
            hitField: SemanticHitField.noteBody,
          ),
          _semanticResult(
            'high',
            score: 0.70,
            hitField: SemanticHitField.summary,
          ),
        ],
      );

      expect(results.map((item) => item.id).toList(), ['high', 'assist']);
    },
  );

  test('ranks dual-hit assist result above keyword-only result', () {
    final results = service.fuse(
      keywordResults: [_keywordItem('dual'), _keywordItem('keyword-only')],
      semanticResults: [
        _semanticResult('dual', score: 0.68, hitField: SemanticHitField.tags),
      ],
    );

    expect(results.map((item) => item.id).toList(), ['dual', 'keyword-only']);
  });

  test(
    'keeps higher semantic score first when results share the same quality tier',
    () {
      final results = service.fuse(
        keywordResults: const <SearchResultItem>[],
        semanticResults: [
          _semanticResult(
            'lower',
            score: 0.78,
            hitField: SemanticHitField.summary,
          ),
          _semanticResult(
            'higher',
            score: 0.91,
            hitField: SemanticHitField.title,
          ),
        ],
      );

      expect(results.map((item) => item.id).toList(), ['higher', 'lower']);
    },
  );

  test('filters weak semantic-only assist results from unified search', () {
    final results = service.fuse(
      keywordResults: const <SearchResultItem>[],
      semanticResults: [
        _semanticResult('assist', score: 0.89, hitField: SemanticHitField.tags),
        _semanticResult(
          'high',
          score: 0.74,
          hitField: SemanticHitField.summary,
        ),
      ],
    );

    expect(results.map((item) => item.id).toList(), ['high']);
  });

  test(
    'keeps very high-score semantic-only assist results in unified search',
    () {
      final results = service.fuse(
        keywordResults: const <SearchResultItem>[],
        semanticResults: [
          _semanticResult(
            'assist',
            score: 0.90,
            hitField: SemanticHitField.tags,
          ),
          _semanticResult(
            'high',
            score: 0.74,
            hitField: SemanticHitField.summary,
          ),
        ],
      );

      expect(results.map((item) => item.id).toList(), ['high', 'assist']);
    },
  );

  test('keeps dual-hit assist results even when assist field is weak', () {
    final results = service.fuse(
      keywordResults: [_keywordItem('dual')],
      semanticResults: [
        _semanticResult('dual', score: 0.89, hitField: SemanticHitField.tags),
      ],
    );

    expect(results.map((item) => item.id).toList(), ['dual']);
    expect(
      results.first.matchSources,
      containsAll(<SearchMatchSource>{
        SearchMatchSource.keyword,
        SearchMatchSource.semantic,
      }),
    );
  });

  test('typed dedupe preserves a Secret and Note with the same id', () {
    final results = service.fuse(
      keywordResults: <SearchResultItem>[
        _keywordItem('same', type: SearchResultType.secret),
        _keywordItem('same', type: SearchResultType.note),
      ],
      semanticResults: const <SemanticSearchResult>[],
    );

    expect(results, hasLength(2));
    expect(
      results.map((item) => (item.type, item.id)),
      const <(SearchResultType, String)>[
        (SearchResultType.secret, 'same'),
        (SearchResultType.note, 'same'),
      ],
    );
  });

  test('fusion carries raw similarity separately from ranking score', () {
    final results = service.fuse(
      keywordResults: const <SearchResultItem>[],
      semanticResults: <SemanticSearchResult>[
        _semanticResult(
          'semantic',
          score: 1.03,
          hitField: SemanticHitField.title,
        ),
      ],
    );

    expect(results.single.semanticScore, 1.03);
    expect(results.single.semanticRawSimilarity, 0.88);
  });

  test('fusion preserves typed keyword and semantic evidence metadata', () {
    final semanticEvidence = SearchEvidence(
      kind: SearchEvidenceKind.semantic,
      sourceField: SearchSourceField.secretTags,
      fieldChunkIndex: 2,
      summary: '标签：backup',
      rawSimilarity: 0.93,
      weight: 0.96,
      rankingScore: 0.8928,
      threshold: 0.90,
      modelRevisionHash: 'a' * 64,
      fingerprintVersion: 1,
      indexConfigVersion: 1,
      indexConfigEpoch: 7,
      chunkSchemaVersion: 1,
      vectorFormatVersion: 1,
    );

    final results = service.fuse(
      keywordResults: [
        _keywordItem(
          'dual',
          keywordHitFields: const <SearchSourceField>[
            SearchSourceField.secretTitle,
          ],
        ),
      ],
      semanticResults: [
        _semanticResult(
          'dual',
          score: 0.8928,
          hitField: SemanticHitField.tags,
          evidence: <SearchEvidence>[semanticEvidence],
        ),
      ],
    );

    expect(
      results.single.evidence.map(
        (evidence) => (evidence.kind, evidence.sourceField),
      ),
      const <(SearchEvidenceKind, SearchSourceField)>[
        (SearchEvidenceKind.keyword, SearchSourceField.secretTitle),
        (SearchEvidenceKind.semantic, SearchSourceField.secretTags),
      ],
    );
    expect(results.single.evidence.first.summary, isEmpty);
    expect(results.single.evidence.last.modelRevisionHash, 'a' * 64);
    expect(results.single.evidence.last.indexConfigEpoch, 7);
  });

  test('dual-hit ranking uses the strongest keyword or semantic field', () {
    final results = service.fuse(
      keywordResults: [
        _keywordItem(
          'z-title',
          keywordHitFields: const <SearchSourceField>[
            SearchSourceField.secretTitle,
          ],
        ),
        _keywordItem(
          'a-tags',
          keywordHitFields: const <SearchSourceField>[
            SearchSourceField.secretTags,
          ],
        ),
      ],
      semanticResults: [
        _semanticResult(
          'z-title',
          score: 0.91,
          hitField: SemanticHitField.noteBody,
        ),
        _semanticResult(
          'a-tags',
          score: 0.91,
          hitField: SemanticHitField.noteBody,
        ),
      ],
    );

    expect(results.map((item) => item.id), <String>['z-title', 'a-tags']);
  });
}
