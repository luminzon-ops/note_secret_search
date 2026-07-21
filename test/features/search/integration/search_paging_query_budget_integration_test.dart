import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/security/crypto_service.dart';
import 'package:note_secret_search/core/security/database_session_keys.dart';
import 'package:note_secret_search/core/storage/database/database_schema.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/notes/infrastructure/sqlite_note_repository.dart';
import 'package:note_secret_search/features/search/application/search_index_service.dart';
import 'package:note_secret_search/features/search/application/semantic_search_service.dart';
import 'package:note_secret_search/features/search/domain/embedding_engine.dart';
import 'package:note_secret_search/features/search/domain/search_configuration.dart';
import 'package:note_secret_search/features/search/domain/search_corpus_reader.dart';
import 'package:note_secret_search/features/search/infrastructure/sqlite_embedding_repository.dart';
import 'package:note_secret_search/features/secrets/infrastructure/sqlite_secret_repository.dart';
import 'package:sqflite_common/sqflite_logger.dart';

import '../../../support/sqlite_test_database.dart';

void main() {
  test(
    'real 1001-source index and semantic paths stay paged and bounded',
    () async {
      final events = <SqfliteLoggerSqlEvent<Object?>>[];
      final database = await openTestAppDatabase(
        onDatabaseEvent: (event) {
          if (event is SqfliteLoggerSqlEvent<Object?>) {
            events.add(event);
          }
        },
      );
      final keyStore = DatabaseSessionKeyStore()
        ..replace(
          DatabaseSessionKeys(
            databaseKey: Uint8List(32),
            fieldKey: Uint8List(32),
            keyId: 'key-1',
            searchIndexFingerprintKey: Uint8List(32),
          ),
        );
      addTearDown(() async {
        keyStore.clear();
        await database.close();
      });
      await _seed(database);
      final configuration = SearchConfiguration.defaults().copyWith(
        includeTitle: false,
        includeUsername: false,
        includeUrl: false,
        includeSecretNote: false,
        includeTags: false,
        includeNoteBody: false,
      );
      final corpus = SearchCorpusReader(
        secretRepository: SqliteSecretRepository(database: database),
        noteRepository: SqliteNoteRepository(database: database),
      );
      final repository = SqliteEmbeddingRepository(database: database);
      final service = SearchIndexService(
        repository: repository,
        cryptoService: const _EmptyCryptoService(),
        embeddingEngine: const _ZeroEmbeddingEngine(),
        sessionKeyStore: keyStore,
      );

      events.clear();
      expect(
        await service.indexCorpusPending(
          activeVaultId: 'default',
          corpus: corpus,
          activeEmbeddingModel: _model,
          modelRevisionHash: 'a' * 64,
          configuration: configuration,
        ),
        1001,
      );

      events.clear();
      expect(
        await service.indexCorpusPending(
          activeVaultId: 'default',
          corpus: corpus,
          activeEmbeddingModel: _model,
          modelRevisionHash: 'a' * 64,
          configuration: configuration,
        ),
        0,
      );
      expect(events.where(_isEmbeddingWrite).where(_isNotQuery), isEmpty);
      expect(_sqlContaining(events, 'from secret_items'), hasLength(9));
      expect(_sqlContaining(events, 'from item_tags'), hasLength(8));
      expect(_sqlContaining(events, 'source_id in'), hasLength(8));
      _expectBindBudget(events);

      events.clear();
      final hydrated = await corpus.secretsByIds(
        vaultId: 'default',
        ids: [
          for (var index = 0; index < 1001; index++)
            'secret-${index.toString().padLeft(4, '0')}',
        ],
      );
      expect(hydrated, hasLength(1001));
      expect(_sqlContaining(events, 'from secret_items'), hasLength(6));
      expect(_sqlContaining(events, 'from item_tags'), hasLength(6));
      _expectBindBudget(events);

      events.clear();
      final semantic =
          await SemanticSearchService(
            repository: repository,
            embeddingEngine: const _ZeroEmbeddingEngine(),
            cryptoService: const _EmptyCryptoService(),
            sessionKeyStore: keyStore,
          ).searchCorpus(
            activeVaultId: 'default',
            query: 'query',
            configuration: configuration,
            modelRevisionHash: 'a' * 64,
            activeEmbeddingModel: _model,
            corpus: corpus,
          );
      expect(semantic, isEmpty);
      expect(
        _sqlContaining(events, 'select * from embedding_index_sets'),
        hasLength(11),
      );
      expect(_sqlContaining(events, 'from embedding_chunks'), hasLength(11));
      expect(_sqlContaining(events, 'from secret_items'), hasLength(11));
      expect(_sqlContaining(events, 'from item_tags'), hasLength(11));
      _expectBindBudget(events);
    },
  );
}

Future<void> _seed(TestAppDatabase database) {
  return database.transaction<void>((executor) async {
    await executor.insert(DatabaseSchema.modelRegistry, <String, Object?>{
      'id': _model.id,
      'type': _model.type,
      'provider': _model.provider,
      'name': _model.name,
      'version': _model.version,
      'quantization': _model.quantization,
      'checksum': _model.checksum,
      'integrity_status': 'valid',
      'enabled': 1,
    });
    final batch = executor.batch();
    for (var index = 0; index < 1001; index++) {
      final suffix = index.toString().padLeft(4, '0');
      batch.insert(DatabaseSchema.secretItems, <String, Object?>{
        'id': 'secret-$suffix',
        'vault_id': 'default',
        'title': 'Secret $suffix',
        'favorite': 0,
        'created_at': 1,
        'updated_at': 1,
      });
    }
    await batch.commit(noResult: true);
  });
}

bool _isEmbeddingWrite(SqfliteLoggerSqlEvent<Object?> event) {
  final sql = event.sql.toLowerCase();
  return sql.contains('embedding_index_sets') ||
      sql.contains('embedding_chunks');
}

bool _isNotQuery(SqfliteLoggerSqlEvent<Object?> event) {
  return !event.name.endsWith('query');
}

Iterable<SqfliteLoggerSqlEvent<Object?>> _sqlContaining(
  Iterable<SqfliteLoggerSqlEvent<Object?>> events,
  String fragment,
) {
  return events.where((event) => event.sql.toLowerCase().contains(fragment));
}

void _expectBindBudget(Iterable<SqfliteLoggerSqlEvent<Object?>> events) {
  expect(
    events
        .map((event) {
          final arguments = event.arguments;
          return arguments is List ? arguments.length : 0;
        })
        .every((count) => count <= 203),
    isTrue,
  );
}

class _ZeroEmbeddingEngine implements EmbeddingEngine {
  const _ZeroEmbeddingEngine();

  @override
  Future<EmbeddingVector> embed(EmbeddingRequest request) async {
    return const EmbeddingVector(values: <double>[1, 0], tokenCount: 0);
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

class _EmptyCryptoService implements CryptoService {
  const _EmptyCryptoService();

  @override
  String decryptNullable(
    List<int>? ciphertext, {
    required FieldCryptoContext context,
  }) {
    return '';
  }

  @override
  Uint8List? encryptNullable(
    String? plaintext, {
    required FieldCryptoContext context,
  }) {
    throw UnimplementedError();
  }
}

const _model = ModelRegistryEntry(
  id: 'model-1',
  type: 'embedding',
  provider: 'local',
  name: 'Embedding',
  version: '1',
  sizeBytes: 1,
  quantization: 'fp32',
  minRamMb: 1,
  recommendedTier: 'test',
  localPath: 'model.onnx',
  checksum: 'checksum',
  enabled: true,
  installedAt: null,
  filePresent: true,
  integrityStatus: ModelIntegrityStatus.valid,
);
