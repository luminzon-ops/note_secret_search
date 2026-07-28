import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/app/composition/content_search_composition.dart';
import 'package:note_secret_search/core/security/core_security_providers.dart';
import 'package:note_secret_search/core/security/crypto_service.dart';
import 'package:note_secret_search/core/storage/database/app_database_providers.dart';
import 'package:note_secret_search/features/ai_models/application/model_selection_sensitive_providers.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/shared_preferences_active_model_selection_store.dart';
import 'package:note_secret_search/features/notes/application/note_providers.dart';
import 'package:note_secret_search/features/notes/infrastructure/sqlite_note_repository.dart';
import 'package:note_secret_search/features/search/application/content_mutation_search_coordinator.dart';
import 'package:note_secret_search/features/search/application/embedding_runtime_providers.dart';
import 'package:note_secret_search/features/search/application/search_index_settings_providers.dart';
import 'package:note_secret_search/features/search/application/search_index_write_fence.dart';
import 'package:note_secret_search/features/search/application/search_providers.dart';
import 'package:note_secret_search/features/search/infrastructure/embedding_runtime_bridge.dart';
import 'package:note_secret_search/features/search/infrastructure/onnx_embedding_engine.dart';
import 'package:note_secret_search/features/search/infrastructure/sqlite_embedding_repository.dart';
import 'package:note_secret_search/features/search/infrastructure/sqlite_search_configuration_repository.dart';
import 'package:note_secret_search/features/secrets/application/secret_providers.dart';
import 'package:note_secret_search/features/secrets/infrastructure/sqlite_secret_repository.dart';
import 'package:note_secret_search/features/vault/application/vault_providers.dart';
import 'package:note_secret_search/features/vault/infrastructure/sqlite_vault_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('composition owns concrete content and search adapters', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      SharedPreferencesActiveModelSelectionStore.activeEmbeddingModelIdKey:
          'embedding-1',
    });
    final database = FakeAppDatabase();
    final container = ProviderContainer(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(database),
        cryptoServiceProvider.overrideWithValue(const _NoopCryptoService()),
        ...contentSearchCompositionOverrides,
      ],
    );
    addTearDown(container.dispose);

    expect(
      container.read(vaultRepositoryProvider),
      isA<SqliteVaultRepository>(),
    );
    expect(container.read(noteRepositoryProvider), isA<SqliteNoteRepository>());
    expect(
      container.read(secretRepositoryProvider),
      isA<SqliteSecretRepository>(),
    );
    expect(
      container.read(sqliteEmbeddingRepositoryProvider),
      isA<SqliteEmbeddingRepository>(),
    );
    expect(
      container.read(embeddingRuntimeBridgeProvider),
      isA<MethodChannelEmbeddingRuntimeBridge>(),
    );
    expect(container.read(embeddingEngineProvider), isA<OnnxEmbeddingEngine>());
    expect(
      container.read(contentMutationSearchSynchronizerProvider),
      isA<ContentMutationSearchCoordinator>(),
    );
    expect(
      await container.read(searchConfigurationRepositoryProvider.future),
      isA<SqliteSearchConfigurationRepository>(),
    );

    final selectionStore = await container.read(
      activeModelSelectionStoreProvider.future,
    );
    expect(selectionStore, isA<SharedPreferencesActiveModelSelectionStore>());
    expect(await selectionStore.loadActiveEmbeddingModelId(), 'embedding-1');
    await selectionStore.saveActiveEmbeddingModelId(null);
    expect(await selectionStore.loadActiveEmbeddingModelId(), isNull);
  });

  test('selection effects fence before releasing the previous model', () async {
    const channel = MethodChannel('note_secret_search/embedding_runtime');
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
    });

    final container = ProviderContainer(
      overrides: contentSearchCompositionOverrides,
    );
    addTearDown(container.dispose);
    final writeFence = container.read(searchIndexWriteFenceProvider);

    await container
        .read(activeEmbeddingSelectionEffectsProvider)
        .prepareForPersistence(
          previousModelId: 'embedding-old',
          nextModelId: 'embedding-new',
        );

    expect(writeFence.revision, 1);
    expect(calls, hasLength(1));
    expect(calls.single.method, 'releaseModel');
    expect(calls.single.arguments, <String, Object?>{
      'modelId': 'embedding-old',
    });
  });
}

class _NoopCryptoService implements CryptoService {
  const _NoopCryptoService();

  @override
  String decryptNullable(
    List<int>? ciphertext, {
    required FieldCryptoContext context,
  }) {
    return ciphertext == null ? '' : String.fromCharCodes(ciphertext);
  }

  @override
  Uint8List? encryptNullable(
    String? plaintext, {
    required FieldCryptoContext context,
  }) {
    return plaintext == null ? null : Uint8List.fromList(plaintext.codeUnits);
  }
}
