part of 'semantic_search_service.dart';

typedef _SemanticSourceHydrator =
    Future<_SemanticSourceMaps> Function(List<EmbeddingIndexSet> page);

class _SemanticSourceMaps {
  const _SemanticSourceMaps({required this.secretById, required this.noteById});

  final Map<String, SecretItem> secretById;
  final Map<String, NoteItem> noteById;
}

extension _SemanticSearchPaging on SemanticSearchService {
  Future<List<SemanticSearchResult>> _searchPages({
    required String activeVaultId,
    required String normalizedQuery,
    required List<double> queryVector,
    required EffectiveSearchPolicy policy,
    required SearchOperation operation,
    required EmbeddingIndexCompatibility compatibility,
    required _SemanticSourceHydrator hydrate,
  }) async {
    while (await _repository.purgeIncompatibleIndexSets(
          compatibility,
          batchSize: 100,
        ) ==
        100) {}

    final candidates = <SemanticSearchResult>[];
    final corruptSetIds = <String>{};
    String? afterId;
    while (true) {
      final pageResult = await _loadIndexSetPage(
        compatibility,
        afterId: afterId,
        limit: 100,
      );
      final page = pageResult.sets;
      final sources = page.isEmpty
          ? const _SemanticSourceMaps(
              secretById: <String, SecretItem>{},
              noteById: <String, NoteItem>{},
            )
          : await hydrate(page);
      for (final indexSet in page) {
        if (indexSet.vaultId != activeVaultId) {
          continue;
        }
        final evaluated = _evaluateGeneration(
          query: normalizedQuery,
          queryVector: queryVector,
          indexSet: indexSet,
          policy: policy,
          operation: operation,
          secret: indexSet.sourceKey.type == SearchSourceType.secret
              ? sources.secretById[indexSet.sourceKey.id]
              : null,
          note: indexSet.sourceKey.type == SearchSourceType.note
              ? sources.noteById[indexSet.sourceKey.id]
              : null,
        );
        if (evaluated.corrupt) {
          corruptSetIds.add(indexSet.id);
        } else if (evaluated.result != null) {
          candidates.add(evaluated.result!);
        }
      }
      candidates.sort(_compareCandidates);
      if (candidates.length > 100) {
        candidates.removeRange(100, candidates.length);
      }
      final nextId = pageResult.nextAfterId;
      if (nextId == null) {
        if (!pageResult.reachedEnd) {
          throw StateError('Embedding corpus page did not provide a cursor.');
        }
        break;
      }
      if (afterId != null && nextId.compareTo(afterId) <= 0) {
        throw StateError('Embedding corpus page cursor did not advance.');
      }
      afterId = nextId;
      if (pageResult.reachedEnd) {
        break;
      }
    }

    for (var offset = 0; offset < corruptSetIds.length; offset += 100) {
      await _repository.purgeIndexSetsByIds(
        corruptSetIds.skip(offset).take(100),
      );
    }
    candidates.sort(_compareCandidates);
    return List<SemanticSearchResult>.unmodifiable(candidates.take(100));
  }

  Future<EmbeddingIndexSetPage> _loadIndexSetPage(
    EmbeddingIndexCompatibility compatibility, {
    String? afterId,
    int limit = 100,
  }) async {
    final repository = _repository;
    if (repository is PagedEmbeddingIndexCorpusRepository) {
      final pagedRepository = repository as PagedEmbeddingIndexCorpusRepository;
      return pagedRepository.getCompatibleIndexSetPage(
        compatibility,
        afterId: afterId,
        limit: limit,
      );
    }
    final sets = await repository.getCompatibleIndexSets(
      compatibility,
      afterId: afterId,
      limit: limit,
    );
    return EmbeddingIndexSetPage(
      sets: sets,
      nextAfterId: sets.isEmpty ? null : sets.last.id,
      reachedEnd: sets.length < limit,
    );
  }
}
