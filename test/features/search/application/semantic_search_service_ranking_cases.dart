part of 'semantic_search_service_test.dart';

void _runSemanticSearchRankingCases() {
  test('raw field threshold is applied before ranking weight', () async {
    final repository = _CorpusRepository(<EmbeddingIndexSet>[
      _set(
        sourceKey: const SearchSourceKey.secret('secret-title'),
        chunks: <({SearchSourceField field, List<double> vector})>[
          (
            field: SearchSourceField.secretTitle,
            vector: _unitVectorWithCosine(0.819),
          ),
        ],
      ),
      _set(
        sourceKey: const SearchSourceKey.note('note-body'),
        chunks: <({SearchSourceField field, List<double> vector})>[
          (
            field: SearchSourceField.noteBody,
            vector: _unitVectorWithCosine(0.901),
          ),
        ],
      ),
    ]);
    final service = _service(repository);

    final results = await service.search(
      activeVaultId: 'vault-1',
      query: 'query',
      configuration: SearchConfiguration.defaults(),
      modelRevisionHash: 'a' * 64,
      activeEmbeddingModel: _model,
      secrets: <SecretItem>[_secret('secret-title')],
      notes: <NoteItem>[_note('note-body')],
    );

    expect(results.map((result) => result.item.id), const <String>[
      'note-body',
    ]);
    expect(results.single.primaryRawSimilarity, closeTo(0.901, 0.00001));
    expect(
      results.single.evidence.single.sourceField,
      SearchSourceField.noteBody,
    );
  });

  test(
    'field metadata drives top-two aggregation and primary evidence',
    () async {
      final repository = _CorpusRepository(<EmbeddingIndexSet>[
        _set(
          sourceKey: const SearchSourceKey.secret('secret-1'),
          chunks: <({SearchSourceField field, List<double> vector})>[
            (
              field: SearchSourceField.secretNote,
              vector: _unitVectorWithCosine(0.88),
            ),
            (
              field: SearchSourceField.secretTitle,
              vector: _unitVectorWithCosine(1),
            ),
            (
              field: SearchSourceField.secretUsername,
              vector: _unitVectorWithCosine(0.90),
            ),
          ],
        ),
      ]);
      final service = _service(repository);

      final results = await service.search(
        activeVaultId: 'vault-1',
        query: 'alice@example.test',
        configuration: SearchConfiguration.defaults(),
        modelRevisionHash: 'a' * 64,
        activeEmbeddingModel: _model,
        secrets: <SecretItem>[_secret('secret-1')],
        notes: const <NoteItem>[],
      );

      expect(results, hasLength(1));
      expect(results.single.evidence, hasLength(3));
      expect(
        results.single.evidence.first.sourceField,
        SearchSourceField.secretTitle,
      );
      expect(results.single.score, closeTo((1.16 + 0.99) / 2, 0.00001));
      expect(results.single.hitSummary, contains('标题'));
      expect(results.single.hitSummary, contains('账号'));
    },
  );

  test('multi-chunk evidence summarizes the exact matched chunk', () async {
    final body = '${'A' * 160}SECOND-MATCH';
    final repository = _CorpusRepository(<EmbeddingIndexSet>[
      _set(
        sourceKey: const SearchSourceKey.note('note-late-chunk'),
        chunks: <({SearchSourceField field, List<double> vector})>[
          (field: SearchSourceField.noteBody, vector: const <double>[0, 1]),
          (field: SearchSourceField.noteBody, vector: const <double>[1, 0]),
        ],
      ),
    ]);
    final service = _service(repository);

    final results = await service.search(
      activeVaultId: 'vault-1',
      query: 'query',
      configuration: SearchConfiguration.defaults().copyWith(
        maxChunkLength: 160,
      ),
      modelRevisionHash: 'a' * 64,
      activeEmbeddingModel: _model,
      secrets: const <SecretItem>[],
      notes: <NoteItem>[_note('note-late-chunk', body: body)],
    );

    expect(results, hasLength(1));
    expect(results.single.evidence.first.fieldChunkIndex, 1);
    expect(results.single.evidence.first.summary, contains('SECOND-MATCH'));
    expect(results.single.evidence.first.summary, isNot(contains('AAAAA')));
    expect(results.single.item.matchSources, const <SearchMatchSource>{
      SearchMatchSource.semantic,
    });
  });

  test(
    'semantic results are deterministically capped at one hundred',
    () async {
      final sets = <EmbeddingIndexSet>[
        for (var index = 0; index < 101; index++)
          _set(
            sourceKey: SearchSourceKey.secret(
              'secret-${index.toString().padLeft(3, '0')}',
            ),
            chunks: <({SearchSourceField field, List<double> vector})>[
              (
                field: SearchSourceField.secretTitle,
                vector: const <double>[1, 0],
              ),
            ],
          ),
      ];
      final repository = _CorpusRepository(sets);
      final service = _service(repository);

      final results = await service.search(
        activeVaultId: 'vault-1',
        query: 'query',
        configuration: SearchConfiguration.defaults(),
        modelRevisionHash: 'a' * 64,
        activeEmbeddingModel: _model,
        secrets: <SecretItem>[
          for (var index = 0; index < 101; index++)
            _secret('secret-${index.toString().padLeft(3, '0')}'),
        ],
        notes: const <NoteItem>[],
      );

      expect(results, hasLength(100));
      expect(results.first.item.id, 'secret-000');
      expect(results.last.item.id, 'secret-099');
    },
  );
}
