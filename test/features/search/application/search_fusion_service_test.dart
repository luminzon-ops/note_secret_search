import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/search/application/search_fusion_service.dart';
import 'package:note_secret_search/features/search/domain/search_result_item.dart';
import 'package:note_secret_search/features/search/domain/semantic_search_result.dart';

SearchResultItem _keywordItem(
  String id, {
  bool favorite = false,
  DateTime? updatedAt,
}) {
  return SearchResultItem(
    id: id,
    type: SearchResultType.secret,
    title: 'Title $id',
    preview: 'Preview $id',
    tags: const <String>[],
    favorite: favorite,
    updatedAt: updatedAt ?? DateTime(2026, 4, 22),
    matchSources: const {SearchMatchSource.keyword},
  );
}

SemanticSearchResult _semanticResult(
  String id, {
  required double score,
  required SemanticHitField hitField,
  bool favorite = false,
  DateTime? updatedAt,
}) {
  return SemanticSearchResult(
    item: SearchResultItem(
      id: id,
      type: SearchResultType.secret,
      title: 'Title $id',
      preview: 'Preview $id',
      tags: const <String>[],
      favorite: favorite,
      updatedAt: updatedAt ?? DateTime(2026, 4, 22),
    ),
    score: score,
    hitSummary: '${hitField.name}: $id',
    hitField: hitField,
  );
}

void main() {
  const service = SearchFusionService();

  test('ranks dual-hit high-quality result above semantic-only assist result even with lower score', () {
    final results = service.fuse(
      keywordResults: [_keywordItem('dual')],
      semanticResults: [
        _semanticResult('dual', score: 0.72, hitField: SemanticHitField.title),
        _semanticResult('assist', score: 0.95, hitField: SemanticHitField.tags),
      ],
    );

    expect(results.map((item) => item.id).toList(), ['dual', 'assist']);
  });

  test('ranks semantic-only high-quality result above semantic-only assist result', () {
    final results = service.fuse(
      keywordResults: const <SearchResultItem>[],
      semanticResults: [
        _semanticResult('assist', score: 0.95, hitField: SemanticHitField.noteBody),
        _semanticResult('high', score: 0.70, hitField: SemanticHitField.summary),
      ],
    );

    expect(results.map((item) => item.id).toList(), ['high', 'assist']);
  });

  test('ranks dual-hit assist result above keyword-only result', () {
    final results = service.fuse(
      keywordResults: [_keywordItem('dual'), _keywordItem('keyword-only')],
      semanticResults: [_semanticResult('dual', score: 0.68, hitField: SemanticHitField.tags)],
    );

    expect(results.map((item) => item.id).toList(), ['dual', 'keyword-only']);
  });

  test('keeps higher semantic score first when results share the same quality tier', () {
    final results = service.fuse(
      keywordResults: const <SearchResultItem>[],
      semanticResults: [
        _semanticResult('lower', score: 0.78, hitField: SemanticHitField.summary),
        _semanticResult('higher', score: 0.91, hitField: SemanticHitField.title),
      ],
    );

    expect(results.map((item) => item.id).toList(), ['higher', 'lower']);
  });

  test('filters weak semantic-only assist results from unified search', () {
    final results = service.fuse(
      keywordResults: const <SearchResultItem>[],
      semanticResults: [
        _semanticResult('assist', score: 0.89, hitField: SemanticHitField.tags),
        _semanticResult('high', score: 0.74, hitField: SemanticHitField.summary),
      ],
    );

    expect(results.map((item) => item.id).toList(), ['high']);
  });

  test('keeps very high-score semantic-only assist results in unified search', () {
    final results = service.fuse(
      keywordResults: const <SearchResultItem>[],
      semanticResults: [
        _semanticResult('assist', score: 0.90, hitField: SemanticHitField.tags),
        _semanticResult('high', score: 0.74, hitField: SemanticHitField.summary),
      ],
    );

    expect(results.map((item) => item.id).toList(), ['high', 'assist']);
  });

  test('keeps dual-hit assist results even when assist field is weak', () {
    final results = service.fuse(
      keywordResults: [_keywordItem('dual')],
      semanticResults: [_semanticResult('dual', score: 0.89, hitField: SemanticHitField.tags)],
    );

    expect(results.map((item) => item.id).toList(), ['dual']);
    expect(results.first.matchSources, containsAll(<SearchMatchSource>{SearchMatchSource.keyword, SearchMatchSource.semantic}));
  });
}
