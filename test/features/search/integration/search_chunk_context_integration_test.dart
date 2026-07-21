import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/app/di/bootstrap_provider.dart';
import 'package:note_secret_search/core/security/crypto_service.dart';
import 'package:note_secret_search/core/security/database_session_keys.dart';
import 'package:note_secret_search/core/security/field_crypto.dart';
import 'package:note_secret_search/features/ai_chat/application/ai_chat_providers.dart';
import 'package:note_secret_search/features/ai_models/application/model_selection_providers.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/sqlite_model_registry_repository.dart';
import 'package:note_secret_search/features/notes/domain/note_item.dart';
import 'package:note_secret_search/features/notes/infrastructure/sqlite_note_repository.dart';
import 'package:note_secret_search/features/search/application/embedding_runtime_providers.dart';
import 'package:note_secret_search/features/search/application/search_index_model_revision_provider.dart';
import 'package:note_secret_search/features/search/application/search_index_settings_providers.dart';
import 'package:note_secret_search/features/search/application/search_providers.dart';
import 'package:note_secret_search/features/search/domain/embedding_engine.dart';
import 'package:note_secret_search/features/search/domain/search_configuration.dart';
import 'package:note_secret_search/features/search/domain/search_result_item.dart';
import 'package:note_secret_search/features/vault/application/vault_providers.dart';
import 'package:note_secret_search/features/vault/domain/vault.dart';

import '../../../support/sqlite_test_database.dart';

const _modelRevision =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'production index returns the exact late chunk through semantic and AI context',
    () async {
      final database = await openTestAppDatabase();
      final keyStore = DatabaseSessionKeyStore()
        ..replace(
          DatabaseSessionKeys(
            databaseKey: Uint8List(32),
            fieldKey: Uint8List.fromList(
              List<int>.generate(32, (index) => index + 1),
            ),
            keyId: 'phase4-key',
            searchIndexFingerprintKey: Uint8List.fromList(
              List<int>.generate(32, (index) => 0x40 + index),
            ),
          ),
        );
      final crypto = AesGcmFieldCrypto(
        sessionKeyStore: keyStore,
        nonceSource: _IncrementingNonceSource(),
      );
      final noteRepository = SqliteNoteRepository(database: database);
      final body = '${'A' * 160}SECOND-MATCH';
      await SqliteModelRegistryRepository(
        database: database,
      ).save(_embeddingModel);
      await noteRepository.save(_note(crypto, body));
      final engine = _LateChunkEmbeddingEngine();

      addTearDown(() async {
        keyStore.clear();
        await database.close();
      });

      final container = ProviderContainer(
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(database),
          databaseSessionKeyStoreProvider.overrideWithValue(keyStore),
          cryptoServiceProvider.overrideWithValue(crypto),
          embeddingEngineProvider.overrideWithValue(engine),
          sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
          defaultVaultProvider.overrideWith((ref) async => _vault),
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
          searchConfigurationProvider.overrideWith(
            (ref) async => SearchConfiguration.defaults().copyWith(
              includeTitle: false,
              includeNoteBody: true,
              includeTags: false,
              maxChunkLength: 160,
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
      final notes = await noteRepository.listByVault(_vault.id);
      final indexService = container.read(searchIndexServiceProvider);
      final status = await indexService.buildStatus(
        secrets: const [],
        notes: notes,
        activeEmbeddingModel: _embeddingModel,
        modelRevisionHash: _modelRevision,
        configuration: configuration,
      );
      await indexService.indexPendingItems(
        items: status.pendingItems,
        activeEmbeddingModel: _embeddingModel,
        modelRevisionHash: _modelRevision,
        configuration: configuration,
      );

      final semantic = await container
          .read(semanticSearchServiceProvider)
          .searchCorpus(
            activeVaultId: _vault.id,
            query: 'late-query',
            configuration: configuration,
            modelRevisionHash: _modelRevision,
            activeEmbeddingModel: _embeddingModel,
            corpus: container.read(searchCorpusReaderProvider),
          );
      final context = await container
          .read(aiChatContextRetrieverProvider)
          .retrieve(query: 'late-query', embeddingModel: _embeddingModel);

      expect(semantic, hasLength(1));
      expect(semantic.single.evidence.first.fieldChunkIndex, 1);
      expect(semantic.single.evidence.first.summary, contains('SECOND-MATCH'));
      expect(semantic.single.evidence.first.summary, isNot(contains('AAAAA')));
      expect(semantic.single.item.matchSources, const <SearchMatchSource>{
        SearchMatchSource.semantic,
      });
      expect(context, hasLength(1));
      expect(context.single.summary, contains('SECOND-MATCH'));
      expect(context.single.summary, isNot(contains('AAAAA')));
      expect(
        engine.indexedTexts,
        containsAll(<String>['A' * 160, 'SECOND-MATCH']),
      );
    },
  );
}

NoteItem _note(CryptoService crypto, String body) {
  final timestamp = DateTime.fromMillisecondsSinceEpoch(1);
  return NoteItem(
    id: 'note-late-chunk',
    vaultId: _vault.id,
    title: 'Late chunk note',
    contentCiphertext: crypto.encryptField(
      body,
      field: EncryptedDatabaseField.noteContent,
      rowId: 'note-late-chunk',
    )!,
    summaryCacheCiphertext: null,
    tags: const <String>[],
    categoryId: null,
    favorite: false,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

class _LateChunkEmbeddingEngine implements EmbeddingEngine {
  final List<String> indexedTexts = <String>[];

  @override
  Future<EmbeddingVector> embed(EmbeddingRequest request) async {
    final text = request.text;
    if (text != 'late-query') {
      indexedTexts.add(text);
    }
    return EmbeddingVector(
      values: text == 'SECOND-MATCH'
          ? const <double>[1, 0]
          : text == 'late-query'
          ? const <double>[1, 0]
          : const <double>[0, 1],
      tokenCount: 1,
    );
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

final Vault _vault = Vault(
  id: 'default',
  name: 'Default',
  description: null,
  isDefault: true,
  encryptionVersion: 1,
  createdAt: DateTime.fromMillisecondsSinceEpoch(1),
  updatedAt: DateTime.fromMillisecondsSinceEpoch(1),
);

const ModelRegistryEntry _embeddingModel = ModelRegistryEntry(
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
