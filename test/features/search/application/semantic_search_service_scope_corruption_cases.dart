part of 'semantic_search_service_test.dart';

void _runSemanticSearchScopeCorruptionCases() {
  test('corrupt generation is purged without hiding valid results', () async {
    final corrupt = _set(
      sourceKey: const SearchSourceKey.secret('secret-corrupt'),
      chunks: <({SearchSourceField field, List<double> vector})>[
        (field: SearchSourceField.secretTitle, vector: const <double>[1, 0]),
      ],
      overrideBlob: _nanVectorBlob(),
    );
    final valid = _set(
      sourceKey: const SearchSourceKey.secret('secret-valid'),
      chunks: <({SearchSourceField field, List<double> vector})>[
        (field: SearchSourceField.secretTitle, vector: const <double>[1, 0]),
      ],
    );
    final repository = _CorpusRepository(<EmbeddingIndexSet>[corrupt, valid]);
    final service = _service(repository);

    final results = await service.search(
      activeVaultId: 'vault-1',
      query: 'query',
      configuration: SearchConfiguration.defaults(),
      modelRevisionHash: 'a' * 64,
      activeEmbeddingModel: _model,
      secrets: <SecretItem>[_secret('secret-corrupt'), _secret('secret-valid')],
      notes: const <NoteItem>[],
    );

    expect(results.map((result) => result.item.id), const ['secret-valid']);
    expect(repository.purgedIds, contains(corrupt.id));
  });

  test('semantic scope excludes disabled fields', () async {
    final repository = _CorpusRepository(<EmbeddingIndexSet>[
      _set(
        sourceKey: const SearchSourceKey.note('note-1'),
        chunks: <({SearchSourceField field, List<double> vector})>[
          (field: SearchSourceField.noteBody, vector: const <double>[1, 0]),
        ],
      ),
    ]);
    final service = _service(repository);

    final results = await service.search(
      activeVaultId: 'vault-1',
      query: 'query',
      configuration: SearchConfiguration.defaults().copyWith(
        includeNoteBody: false,
      ),
      modelRevisionHash: 'a' * 64,
      activeEmbeddingModel: _model,
      secrets: const <SecretItem>[],
      notes: <NoteItem>[_note('note-1')],
    );

    expect(results, isEmpty);
  });

  test(
    'non-index source timestamp changes keep a compatible generation visible',
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
      final service = _service(repository);
      final source = _secret('secret-1');
      final timestampOnlyUpdate = SecretItem(
        id: source.id,
        vaultId: source.vaultId,
        title: source.title,
        usernameCiphertext: source.usernameCiphertext,
        passwordCiphertext: source.passwordCiphertext,
        websiteUrlCiphertext: source.websiteUrlCiphertext,
        noteCiphertext: source.noteCiphertext,
        tags: source.tags,
        categoryId: 'category-only-change',
        favorite: true,
        createdAt: source.createdAt,
        updatedAt: source.updatedAt.add(const Duration(seconds: 1)),
      );

      final results = await service.search(
        activeVaultId: 'vault-1',
        query: 'query',
        configuration: SearchConfiguration.defaults(),
        modelRevisionHash: 'a' * 64,
        activeEmbeddingModel: _model,
        secrets: <SecretItem>[timestampOnlyUpdate],
        notes: const <NoteItem>[],
      );

      expect(results.map((result) => result.item.id), const ['secret-1']);
      expect(repository.purgedIds, isEmpty);
    },
  );

  test(
    'semantic search rejects deleted and other-vault sources at the service boundary',
    () async {
      final repository = _CorpusRepository(<EmbeddingIndexSet>[
        _set(
          sourceKey: const SearchSourceKey.secret('active'),
          chunks: <({SearchSourceField field, List<double> vector})>[
            (
              field: SearchSourceField.secretTitle,
              vector: const <double>[1, 0],
            ),
          ],
        ),
        _set(
          sourceKey: const SearchSourceKey.secret('other'),
          vaultId: 'vault-2',
          chunks: <({SearchSourceField field, List<double> vector})>[
            (
              field: SearchSourceField.secretTitle,
              vector: const <double>[1, 0],
            ),
          ],
        ),
        _set(
          sourceKey: const SearchSourceKey.secret('deleted'),
          chunks: <({SearchSourceField field, List<double> vector})>[
            (
              field: SearchSourceField.secretTitle,
              vector: const <double>[1, 0],
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
        secrets: <SecretItem>[
          _secret('active'),
          _secret('other', vaultId: 'vault-2'),
          _secret('deleted', deletedAt: DateTime(2026, 7, 20)),
        ],
        notes: const <NoteItem>[],
      );

      expect(results.map((result) => result.item.id), const <String>['active']);
    },
  );
}
