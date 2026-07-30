part of 'semantic_search_service_test.dart';

void _runSemanticSearchPagingCases() {
  test(
    'paged semantic corpus hydrates current generation sources in one ID batch',
    () async {
      final repository = _CorpusRepository(<EmbeddingIndexSet>[
        _set(
          sourceKey: const SearchSourceKey.secret('secret-1'),
          chunks: <({SearchSourceField field, List<double> vector})>[
            (
              field: SearchSourceField.secretTitle,
              vector: const <double>[1, 0],
            ),
          ],
        ),
      ]);
      final sources = _IdHydrationSecretRepository(_secret('secret-1'));
      final service = _service(repository);

      final results = await service.searchCorpus(
        activeVaultId: 'vault-1',
        query: 'query',
        configuration: SearchConfiguration.defaults(),
        modelRevisionHash: 'a' * 64,
        activeEmbeddingModel: _model,
        corpus: SearchCorpusReader(
          secretRepository: sources,
          noteRepository: _EmptyNoteRepository(),
        ),
      );

      expect(results.map((result) => result.item.id), const <String>[
        'secret-1',
      ]);
      expect(sources.requestedBatches, const <List<String>>[
        <String>['secret-1'],
      ]);
    },
  );
}
