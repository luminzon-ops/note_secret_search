import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/app/di/bootstrap_provider.dart';
import 'package:note_secret_search/core/security/crypto_service.dart';
import 'package:note_secret_search/core/security/database_session_keys.dart';
import 'package:note_secret_search/core/security/field_crypto.dart';
import 'package:note_secret_search/core/storage/database/database_schema.dart';
import 'package:note_secret_search/features/ai_chat/application/ai_chat_providers.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_context_models.dart';
import 'package:note_secret_search/features/ai_models/application/model_selection_providers.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/sqlite_model_registry_repository.dart';
import 'package:note_secret_search/features/notes/application/note_providers.dart';
import 'package:note_secret_search/features/notes/domain/note_item.dart';
import 'package:note_secret_search/features/notes/infrastructure/sqlite_note_repository.dart';
import 'package:note_secret_search/features/search/application/embedding_runtime_providers.dart';
import 'package:note_secret_search/features/search/application/search_index_model_revision_provider.dart';
import 'package:note_secret_search/features/search/application/search_index_settings_providers.dart';
import 'package:note_secret_search/features/search/application/search_providers.dart';
import 'package:note_secret_search/features/search/domain/embedding_chunk.dart';
import 'package:note_secret_search/features/search/domain/embedding_engine.dart';
import 'package:note_secret_search/features/search/domain/search_configuration.dart';
import 'package:note_secret_search/features/search/domain/search_result_item.dart';
import 'package:note_secret_search/features/secrets/application/secret_providers.dart';
import 'package:note_secret_search/features/secrets/domain/secret_item.dart';
import 'package:note_secret_search/features/secrets/infrastructure/sqlite_secret_repository.dart';
import 'package:note_secret_search/features/settings/application/security_settings_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/sqlite_test_database.dart';

const _modelRevision =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _staleModelRevision =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _sharedSourceId = 'shared-source';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'production pipeline preserves field identity scope ranking and typed AI context',
    () async {
      SharedPreferences.setMockInitialValues(const <String, Object>{
        'search.scope.include_password_field': true,
      });
      final database = await openTestAppDatabase();
      final keyStore = DatabaseSessionKeyStore()
        ..replace(
          DatabaseSessionKeys(
            databaseKey: Uint8List.fromList(
              List<int>.generate(32, (index) => 0x20 + index),
            ),
            fieldKey: Uint8List.fromList(
              List<int>.generate(32, (index) => 0x60 + index),
            ),
            keyId: 'phase4-key',
            searchIndexFingerprintKey: Uint8List.fromList(
              List<int>.generate(32, (index) => 0xa0 + index),
            ),
          ),
        );
      final crypto = AesGcmFieldCrypto(
        sessionKeyStore: keyStore,
        nonceSource: _IncrementingNonceSource(),
      );
      final engine = _DeterministicEmbeddingEngine();
      final secretRepository = SqliteSecretRepository(database: database);
      final noteRepository = SqliteNoteRepository(database: database);

      addTearDown(() async {
        keyStore.clear();
        await database.close();
      });

      await SqliteModelRegistryRepository(
        database: database,
      ).save(_embeddingModel);
      await secretRepository.save(_secret(crypto));
      for (final note in _notes(crypto)) {
        await noteRepository.save(note);
      }

      final preferences = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(database),
          databaseSessionKeyStoreProvider.overrideWithValue(keyStore),
          cryptoServiceProvider.overrideWithValue(crypto),
          embeddingEngineProvider.overrideWithValue(engine),
          sharedPreferencesProvider.overrideWith((ref) async => preferences),
          sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
          semanticSearchReadinessProvider.overrideWith(
            (ref) async => const SemanticSearchReadiness(
              ready: true,
              reason: 'ready',
              activeEmbeddingModel: _embeddingModel,
              runtimeStatus: EmbeddingRuntimeStatus.ready,
              runtimeState: EmbeddingEngineState(
                ready: true,
                reason: 'ready',
                status: EmbeddingRuntimeStatus.ready,
                vectorDimension: 2,
              ),
            ),
          ),
          searchIndexModelRevisionProvider(
            _embeddingModel,
          ).overrideWith((ref) async => _modelRevision),
        ],
      );
      addTearDown(container.dispose);

      final configuration = await container.read(
        searchConfigurationProvider.future,
      );
      expect(configuration.includePasswordField, isTrue);
      final secrets = await container.read(secretListProvider.future);
      final notes = await container.read(noteListProvider.future);
      expect(secrets, hasLength(1));
      expect(notes, hasLength(6));

      final indexService = container.read(searchIndexServiceProvider);
      final status = await indexService.buildStatus(
        secrets: secrets,
        notes: notes,
        activeEmbeddingModel: _embeddingModel,
        modelRevisionHash: _modelRevision,
        configuration: configuration,
      );
      expect(status.pendingItems, hasLength(7));

      await indexService.indexPendingItems(
        items: status.pendingItems,
        activeEmbeddingModel: _embeddingModel,
        modelRevisionHash: _modelRevision,
        configuration: configuration,
      );

      final storedChunks = await database.run(
        (db) => db.rawQuery('''
          SELECT index_set.source_type, index_set.source_id,
                 chunk.source_field, chunk.vector_blob
          FROM ${DatabaseSchema.embeddingChunks} chunk
          JOIN ${DatabaseSchema.embeddingIndexSets} index_set
            ON index_set.id = chunk.index_set_id
          ORDER BY index_set.source_type, index_set.source_id,
                   chunk.source_field, chunk.field_chunk_index
          '''),
      );
      expect(
        storedChunks
            .where((row) => row['source_id'] == _sharedSourceId)
            .map((row) => row['source_field']),
        containsAll(<String>[
          'secret.title',
          'secret.username',
          'secret.website_url',
          'secret.note',
          'secret.tags',
          'note.title',
          'note.summary',
          'note.body',
          'note.tags',
        ]),
      );
      expect(
        storedChunks.map((row) => row['source_field']),
        isNot(contains('secret.password')),
      );
      expect(
        storedChunks.every(
          (row) => (row['vector_blob']! as List<int>).length == 8,
        ),
        isTrue,
      );
      expect(engine.indexedTexts, isNot(contains('password-only-value')));

      final freshStatus = await indexService.buildStatus(
        secrets: secrets,
        notes: notes,
        activeEmbeddingModel: _embeddingModel,
        modelRevisionHash: _modelRevision,
        configuration: configuration,
      );
      expect(freshStatus.pendingItems, isEmpty);

      await _insertStaleGenerations(
        database: database,
        configuration: configuration,
      );

      container.read(searchQueryProvider.notifier).state = 'alice@example.test';
      final semantic = await container.read(
        semanticSearchResultsProvider.future,
      );
      final sharedSecret = semantic.singleWhere(
        (result) =>
            result.item.type == SearchResultType.secret &&
            result.item.id == _sharedSourceId,
      );
      final sharedNote = semantic.singleWhere(
        (result) =>
            result.item.type == SearchResultType.note &&
            result.item.id == _sharedSourceId,
      );
      expect(
        sharedSecret.evidence.first.sourceField,
        SearchSourceField.secretUsername,
      );
      expect(sharedSecret.primaryRawSimilarity, closeTo(1, 0.000001));
      expect(sharedSecret.score, closeTo(1.10, 0.000001));
      expect(
        sharedNote.evidence.first.sourceField,
        SearchSourceField.noteSummary,
      );
      expect(sharedNote.primaryRawSimilarity, closeTo(0.98, 0.0001));
      expect(sharedNote.score, closeTo(1.078, 0.0001));

      final staleCount = await database.run(
        (db) => db.rawQuery(
          '''
          SELECT COUNT(*) AS count
          FROM ${DatabaseSchema.embeddingIndexSets}
          WHERE model_revision_hash = ?
          ''',
          <Object>[_staleModelRevision],
        ),
      );
      expect(staleCount.single['count'], 0);

      final unified = await container.read(unifiedSearchResultsProvider.future);
      expect(unified, hasLength(6));
      expect(
        (type: unified.first.type, id: unified.first.id),
        (type: SearchResultType.secret, id: _sharedSourceId),
      );
      expect(unified.first.matchSources, <SearchMatchSource>{
        SearchMatchSource.keyword,
        SearchMatchSource.semantic,
      });
      expect(
        unified
            .where((item) => item.id == _sharedSourceId)
            .map((item) => item.type),
        <SearchResultType>[SearchResultType.secret, SearchResultType.note],
      );

      final context = await container
          .read(aiChatContextRetrieverProvider)
          .retrieve(
            query: 'alice@example.test',
            embeddingModel: _embeddingModel,
          );
      expect(context, hasLength(5));
      expect(
        context
            .where((item) => item.id == _sharedSourceId)
            .map((item) => item.type),
        <ChatContextItemType>[
          ChatContextItemType.secret,
          ChatContextItemType.note,
        ],
      );
      expect(context.map((item) => item.id), isNot(contains('candidate-4')));

      final weakAssistContext = await container
          .read(aiChatContextRetrieverProvider)
          .retrieve(
            query: 'weak-assist-query',
            embeddingModel: _embeddingModel,
          );
      expect(weakAssistContext, isEmpty);

      container.read(searchQueryProvider.notifier).state =
          'password-only-value';
      final passwordResults = await container.read(
        unifiedSearchResultsProvider.future,
      );
      expect(passwordResults, hasLength(1));
      expect(passwordResults.single.type, SearchResultType.secret);
      expect(passwordResults.single.keywordHitFields, <SearchSourceField>[
        SearchSourceField.secretPassword,
      ]);
      expect(passwordResults.single.matchSources, <SearchMatchSource>{
        SearchMatchSource.keyword,
      });
    },
  );
}

SecretItem _secret(CryptoService crypto) {
  final timestamp = DateTime.fromMillisecondsSinceEpoch(1000);
  return SecretItem(
    id: _sharedSourceId,
    vaultId: 'default',
    title: 'Personal mail account',
    usernameCiphertext: crypto.encryptField(
      'alice@example.test',
      field: EncryptedDatabaseField.secretUsername,
      rowId: _sharedSourceId,
    ),
    passwordCiphertext: crypto.encryptField(
      'password-only-value',
      field: EncryptedDatabaseField.secretPassword,
      rowId: _sharedSourceId,
    ),
    websiteUrlCiphertext: crypto.encryptField(
      'https://mail.example.test',
      field: EncryptedDatabaseField.secretWebsiteUrl,
      rowId: _sharedSourceId,
    ),
    noteCiphertext: crypto.encryptField(
      'MFA enabled',
      field: EncryptedDatabaseField.secretNote,
      rowId: _sharedSourceId,
    ),
    tags: const <String>['Mail'],
    categoryId: null,
    favorite: false,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

List<NoteItem> _notes(CryptoService crypto) {
  return <NoteItem>[
    _note(
      crypto,
      id: _sharedSourceId,
      title: 'Recovery plan',
      summary: 'Recovery mailbox instructions',
      body: 'Keep the offline recovery codes nearby.',
      tag: 'Recovery',
      updatedAt: 2000,
    ),
    for (var index = 1; index <= 4; index++)
      _note(
        crypto,
        id: 'candidate-$index',
        title: 'Candidate $index',
        summary: 'Candidate summary $index',
        body: 'Candidate body $index',
        tag: 'Candidate',
        updatedAt: 2000 - index,
      ),
    _note(
      crypto,
      id: 'weak-assist',
      title: 'Weak assist',
      summary: 'No strong semantic evidence',
      body: 'No strong body evidence',
      tag: 'weak-assist-tag',
      updatedAt: 1900,
    ),
  ];
}

NoteItem _note(
  CryptoService crypto, {
  required String id,
  required String title,
  required String summary,
  required String body,
  required String tag,
  required int updatedAt,
}) {
  final created = DateTime.fromMillisecondsSinceEpoch(1000);
  return NoteItem(
    id: id,
    vaultId: 'default',
    title: title,
    contentCiphertext: crypto.encryptField(
      body,
      field: EncryptedDatabaseField.noteContent,
      rowId: id,
    )!,
    summaryCacheCiphertext: crypto.encryptField(
      summary,
      field: EncryptedDatabaseField.noteSummary,
      rowId: id,
    ),
    tags: <String>[tag],
    categoryId: null,
    favorite: false,
    createdAt: created,
    updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAt),
  );
}

Future<void> _insertStaleGenerations({
  required TestAppDatabase database,
  required SearchConfiguration configuration,
}) {
  return database.transaction((db) async {
    for (var index = 0; index < 101; index++) {
      final suffix = index.toString().padLeft(3, '0');
      final sourceId = 'stale-source-$suffix';
      await db.insert(DatabaseSchema.secretItems, <String, Object?>{
        'id': sourceId,
        'vault_id': 'default',
        'title': 'Stale source $suffix',
        'favorite': 0,
        'created_at': 1,
        'updated_at': 1,
      });
      await db.insert(DatabaseSchema.embeddingIndexSets, <String, Object?>{
        'id': 'stale-set-$suffix',
        'source_type': 'secret',
        'source_id': sourceId,
        'vault_id': 'default',
        'model_id': _embeddingModel.id,
        'model_revision_hash': _staleModelRevision,
        'source_updated_at': 1,
        'source_fingerprint': Uint8List(32),
        'fingerprint_key_id': 'phase4-key',
        'fingerprint_version': 1,
        'index_config_version': 1,
        'index_config_epoch': configuration.configurationEpoch,
        'index_config_hash':
            'cccccccccccccccccccccccccccccccc'
            'cccccccccccccccccccccccccccccccc',
        'chunk_schema_version': 1,
        'vector_format_version': 1,
        'vector_dimension': 0,
        'chunk_count': 0,
        'created_at': 1,
      });
    }
  });
}

class _IncrementingNonceSource implements FieldNonceSource {
  int _value = 0;

  @override
  Uint8List nextNonce() {
    final start = _value++;
    return Uint8List.fromList(
      List<int>.generate(12, (index) => (start + index) & 0xff),
    );
  }
}

class _DeterministicEmbeddingEngine implements EmbeddingEngine {
  final List<String> indexedTexts = <String>[];

  @override
  Future<EmbeddingVector> embed(EmbeddingRequest request) async {
    final text = request.text;
    final values = switch (text) {
      'alice@example.test' => const <double>[1, 0],
      'Recovery mailbox instructions' => _vectorFromXAxisCosine(0.98),
      'Candidate summary 1' => _vectorFromXAxisCosine(0.96),
      'Candidate summary 2' => _vectorFromXAxisCosine(0.94),
      'Candidate summary 3' => _vectorFromXAxisCosine(0.92),
      'Candidate summary 4' => _vectorFromXAxisCosine(0.90),
      'weak-assist-query' => const <double>[0, 1],
      'weak-assist-tag' => _vectorFromYAxisCosine(0.91),
      'password-only-value' => const <double>[-1, 0],
      _ => const <double>[0, -1],
    };
    if (text != 'alice@example.test' && text != 'password-only-value') {
      indexedTexts.add(text);
    } else if (text == 'alice@example.test' && !indexedTexts.contains(text)) {
      indexedTexts.add(text);
    }
    return EmbeddingVector(values: values, tokenCount: 1);
  }

  List<double> _vectorFromXAxisCosine(double cosine) {
    return <double>[cosine, math.sqrt((1 - cosine * cosine).abs())];
  }

  List<double> _vectorFromYAxisCosine(double cosine) {
    return <double>[math.sqrt((1 - cosine * cosine).abs()), cosine];
  }

  @override
  Future<EmbeddingEngineState> getState(ModelRegistryEntry model) async {
    return const EmbeddingEngineState(
      ready: true,
      reason: 'ready',
      status: EmbeddingRuntimeStatus.ready,
      vectorDimension: 2,
    );
  }
}

const _embeddingModel = ModelRegistryEntry(
  id: 'embedding-model',
  type: 'embedding',
  provider: 'builtin',
  name: 'Deterministic embedding',
  version: '1',
  sizeBytes: 1,
  quantization: 'fp32',
  minRamMb: 1,
  recommendedTier: 'test',
  localPath: 'E:/models/embedding.onnx',
  checksum: 'verified-checksum',
  enabled: true,
  installedAt: null,
  filePresent: true,
  integrityStatus: ModelIntegrityStatus.valid,
);
