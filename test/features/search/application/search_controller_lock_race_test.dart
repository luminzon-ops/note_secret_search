import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/app/di/bootstrap_provider.dart';
import 'package:note_secret_search/core/security/core_security_providers.dart';
import 'package:note_secret_search/core/security/crypto_service.dart';
import 'package:note_secret_search/core/security/lock_session.dart';
import 'package:note_secret_search/features/ai_models/application/model_selection_providers.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/notes/domain/note_repository.dart';
import 'package:note_secret_search/features/search/application/search_index_service.dart';
import 'package:note_secret_search/features/search/application/search_index_model_revision_provider.dart';
import 'package:note_secret_search/features/search/application/search_index_settings_providers.dart';
import 'package:note_secret_search/features/search/application/search_providers.dart';
import 'package:note_secret_search/features/search/application/search_settings_use_case.dart';
import 'package:note_secret_search/features/search/domain/embedding_chunk.dart';
import 'package:note_secret_search/features/search/domain/embedding_engine.dart';
import 'package:note_secret_search/features/search/domain/embedding_index_repository.dart';
import 'package:note_secret_search/features/search/domain/embedding_index_set.dart';
import 'package:note_secret_search/features/search/domain/search_configuration.dart';
import 'package:note_secret_search/features/search/domain/search_corpus_reader.dart';
import 'package:note_secret_search/features/search/domain/search_index_settings.dart';
import 'package:note_secret_search/features/search/domain/search_index_status.dart';
import 'package:note_secret_search/features/search/domain/search_result_item.dart';
import 'package:note_secret_search/features/search/domain/semantic_search_result.dart';
import 'package:note_secret_search/features/secrets/domain/secret_repository.dart';
import 'package:note_secret_search/features/vault/application/vault_providers.dart';
import 'package:note_secret_search/features/vault/domain/vault.dart';

class _FakeCryptoService implements CryptoService {
  const _FakeCryptoService();

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

class _FakeEmbeddingIndexRepository implements EmbeddingIndexRepository {
  @override
  Future<EmbeddingIndexSet?> getIndexSetBySource(
    SearchSourceKey sourceKey,
    String modelId,
  ) async => null;

  @override
  Future<void> removeIndexSetsBySource(SearchSourceKey sourceKey) async {}

  @override
  Future<bool> replaceIndexSet(EmbeddingIndexSet indexSet) async => true;
}

class _FakeEmbeddingEngine implements EmbeddingEngine {
  const _FakeEmbeddingEngine();

  @override
  Future<EmbeddingVector> embed(EmbeddingRequest request) async {
    return const EmbeddingVector(values: <double>[0.1], tokenCount: 1);
  }

  @override
  Future<EmbeddingEngineState> getState(ModelRegistryEntry model) async {
    return const EmbeddingEngineState(
      ready: true,
      reason: 'ready',
      status: EmbeddingRuntimeStatus.ready,
    );
  }
}

class _ControlledSearchIndexService extends SearchIndexService {
  _ControlledSearchIndexService(this._onIndex)
    : super(
        repository: _FakeEmbeddingIndexRepository(),
        cryptoService: const _FakeCryptoService(),
        embeddingEngine: const _FakeEmbeddingEngine(),
      );

  final Future<void> Function() _onIndex;

  @override
  Future<int> indexCorpusPending({
    required String activeVaultId,
    required SearchCorpusReader corpus,
    required ModelRegistryEntry activeEmbeddingModel,
    required String modelRevisionHash,
    required SearchConfiguration configuration,
  }) async {
    await _onIndex();
    return 1;
  }

  @override
  Future<void> indexPendingItems({
    required List<SearchIndexPendingItem> items,
    required ModelRegistryEntry activeEmbeddingModel,
    required String modelRevisionHash,
    required SearchConfiguration configuration,
  }) {
    return _onIndex();
  }
}

class _UnusedSecretRepository implements SecretRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedNoteRepository implements NoteRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

SearchCorpusReader _emptyCorpusReader() {
  return SearchCorpusReader(
    secretRepository: _UnusedSecretRepository(),
    noteRepository: _UnusedNoteRepository(),
  );
}

Vault _defaultVault() {
  final now = DateTime(2026, 7, 21);
  return Vault(
    id: 'default',
    name: 'Default',
    description: null,
    isDefault: true,
    encryptionVersion: 1,
    createdAt: now,
    updatedAt: now,
  );
}

const _embeddingModel = ModelRegistryEntry(
  id: 'embed-race',
  type: 'embedding',
  provider: 'test',
  name: 'Race model',
  version: '1',
  sizeBytes: 1024,
  quantization: 'Q8',
  minRamMb: 256,
  recommendedTier: 'test',
  localPath: '/models/race.onnx',
  checksum: 'checksum',
  enabled: true,
  installedAt: null,
  filePresent: true,
);

SearchIndexStatus _readyStatus() {
  return SearchIndexStatus(
    engineReady: true,
    engineReason: 'ready',
    hasActiveEmbeddingModel: true,
    pendingItems: [
      SearchIndexPendingItem(
        sourceId: 'secret-race',
        sourceType: SearchSourceType.secret,
        title: 'Sensitive item',
        updatedAt: DateTime(2026, 7, 14),
        plainTextHash: 'hash',
        indexPlainText: 'sensitive index plaintext',
      ),
    ],
  );
}

List<SearchResultItem> _results(String id) {
  return [
    SearchResultItem(
      id: id,
      type: SearchResultType.secret,
      title: 'Title $id',
      preview: 'Preview $id',
      tags: const <String>[],
      favorite: false,
      updatedAt: DateTime(2026, 7, 14),
    ),
  ];
}

ProviderContainer _buildContainer({
  required LockSessionController sessionController,
  required SearchIndexService indexService,
  required Future<List<SearchResultItem>> Function() loadUnifiedResults,
}) {
  return ProviderContainer(
    overrides: [
      lockSessionControllerProvider.overrideWith((ref) => sessionController),
      sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
      defaultVaultProvider.overrideWith((ref) async => _defaultVault()),
      searchCorpusReaderProvider.overrideWith((ref) => _emptyCorpusReader()),
      searchIndexStatusSnapshotProvider.overrideWith(
        (ref) async => _readyStatus(),
      ),
      activeEmbeddingModelProvider.overrideWith((ref) async => _embeddingModel),
      searchIndexSettingsProvider.overrideWith(
        (ref) async => const SearchIndexSettings.defaults(),
      ),
      searchConfigurationProvider.overrideWith(
        (ref) async => SearchConfiguration.defaults(),
      ),
      searchIndexModelRevisionProvider(
        _embeddingModel,
      ).overrideWith((ref) async => 'a' * 64),
      searchIndexServiceProvider.overrideWith((ref) => indexService),
      unifiedSearchResultsProvider.overrideWith((ref) => loadUnifiedResults()),
      semanticSearchResultsProvider.overrideWith(
        (ref) async => const <SemanticSearchResult>[],
      ),
    ],
  );
}

void _lockAndClearSearchState(
  ProviderContainer container,
  LockSessionController sessionController,
) {
  sessionController.lock();
  container.read(sensitiveStateAccessAllowedProvider.notifier).state = false;
  container.read(searchQueryProvider.notifier).state = '';
  container.read(searchRefreshControllerProvider.notifier).resetForLock();
}

void _unlockSensitiveState(
  ProviderContainer container,
  LockSessionController sessionController,
) {
  sessionController.markUnlocked(UnlockMethod.pin);
  container.read(sensitiveStateAccessAllowedProvider.notifier).state = true;
}

void _expectTaskStateCleared(ProviderContainer container) {
  final taskState = container.read(searchIndexTaskStateProvider);
  expect(taskState.running, isFalse);
  expect(taskState.lastCompletedAt, isNull);
  expect(taskState.lastIndexedCount, 0);
  expect(taskState.lastError, isNull);
}

void _expectRefreshStateCleared(ProviderContainer container) {
  final refreshSession = container.read(searchRefreshSessionProvider);
  expect(refreshSession.refreshing, isFalse);
  expect(refreshSession.message, isNull);
  expect(refreshSession.lastCompletedAt, isNull);

  final feedback = container.read(searchRefreshFeedbackProvider);
  expect(feedback.visible, isFalse);
  expect(feedback.headline, isNull);
  expect(feedback.message, isNull);
  expect(feedback.changed, isNull);
  expect(feedback.queryAtRefresh, isNull);
  expect(feedback.completedAt, isNull);

  final handoff = container.read(searchPendingReindexHandoffProvider);
  expect(handoff.visible, isFalse);
  expect(handoff.message, isNull);
}

void main() {
  test('indexPending ignores delayed success after lock', () async {
    final sessionController = LockSessionController()
      ..markUnlocked(UnlockMethod.pin);
    final indexingStarted = Completer<void>();
    final indexingCompletion = Completer<void>();
    final container = _buildContainer(
      sessionController: sessionController,
      indexService: _ControlledSearchIndexService(() {
        indexingStarted.complete();
        return indexingCompletion.future;
      }),
      loadUnifiedResults: () async => const <SearchResultItem>[],
    );
    addTearDown(container.dispose);

    final operation = container
        .read(searchRefreshControllerProvider.notifier)
        .indexPendingOnly();
    await indexingStarted.future;
    expect(container.read(searchIndexTaskStateProvider).running, isTrue);

    _lockAndClearSearchState(container, sessionController);
    indexingCompletion.complete();
    await operation;

    _expectTaskStateCleared(container);
  });

  test('indexPending ignores delayed error after lock', () async {
    final sessionController = LockSessionController()
      ..markUnlocked(UnlockMethod.pin);
    final indexingStarted = Completer<void>();
    final indexingCompletion = Completer<void>();
    final container = _buildContainer(
      sessionController: sessionController,
      indexService: _ControlledSearchIndexService(() {
        indexingStarted.complete();
        return indexingCompletion.future;
      }),
      loadUnifiedResults: () async => const <SearchResultItem>[],
    );
    addTearDown(container.dispose);

    final operation = container
        .read(searchRefreshControllerProvider.notifier)
        .indexPendingOnly();
    await indexingStarted.future;

    _lockAndClearSearchState(container, sessionController);
    indexingCompletion.completeError(StateError('late index failure'));
    try {
      await operation;
    } catch (_) {}

    _expectTaskStateCleared(container);
  });

  test(
    'indexPendingAndRefresh rejects delayed completion after lock and unlock',
    () async {
      final sessionController = LockSessionController()
        ..markUnlocked(UnlockMethod.pin);
      final refreshReadStarted = Completer<void>();
      final refreshResults = Completer<List<SearchResultItem>>();
      var unifiedReadCount = 0;
      final container = _buildContainer(
        sessionController: sessionController,
        indexService: _ControlledSearchIndexService(() => Future<void>.value()),
        loadUnifiedResults: () {
          unifiedReadCount++;
          if (unifiedReadCount == 1) {
            return Future.value(_results('before'));
          }
          refreshReadStarted.complete();
          return refreshResults.future;
        },
      );
      addTearDown(container.dispose);

      container.read(searchQueryProvider.notifier).state =
          'old sensitive query';
      container.read(searchRefreshControllerProvider.notifier)
        ..recordSettingsSaved(
          SearchSettingsSaveResult(
            savedConfiguration: SearchConfiguration.defaults(),
            requiresReindex: true,
          ),
        )
        ..publishHandoff();

      final operation = container
          .read(searchRefreshControllerProvider.notifier)
          .refresh(container.read(searchQueryProvider));
      await refreshReadStarted.future;
      expect(container.read(searchRefreshSessionProvider).refreshing, isTrue);

      _lockAndClearSearchState(container, sessionController);
      _unlockSensitiveState(container, sessionController);
      container.read(searchQueryProvider.notifier).state = 'new query';
      refreshResults.complete(_results('after'));
      await operation;

      expect(container.read(searchQueryProvider), 'new query');
      _expectRefreshStateCleared(container);
    },
  );

  test(
    'indexPendingAndRefresh stale error preserves newer unlocked state',
    () async {
      final sessionController = LockSessionController()
        ..markUnlocked(UnlockMethod.pin);
      final refreshReadStarted = Completer<void>();
      final refreshResults = Completer<List<SearchResultItem>>();
      var unifiedReadCount = 0;
      final container = _buildContainer(
        sessionController: sessionController,
        indexService: _ControlledSearchIndexService(() => Future<void>.value()),
        loadUnifiedResults: () {
          unifiedReadCount++;
          if (unifiedReadCount == 1) {
            return Future.value(_results('before'));
          }
          refreshReadStarted.complete();
          return refreshResults.future;
        },
      );
      addTearDown(container.dispose);

      container.read(searchQueryProvider.notifier).state =
          'old sensitive query';
      final operation = container
          .read(searchRefreshControllerProvider.notifier)
          .refresh(container.read(searchQueryProvider));
      await refreshReadStarted.future;

      _lockAndClearSearchState(container, sessionController);
      _unlockSensitiveState(container, sessionController);
      container.read(searchQueryProvider.notifier).state = 'new query';
      container.read(searchRefreshControllerProvider.notifier)
        ..recordSettingsSaved(
          SearchSettingsSaveResult(
            savedConfiguration: SearchConfiguration.defaults(),
            requiresReindex: true,
          ),
        )
        ..publishHandoff();

      refreshResults.completeError(StateError('late refresh failure'));
      try {
        await operation;
      } catch (_) {}

      final refreshSession = container.read(searchRefreshSessionProvider);
      expect(refreshSession.refreshing, isFalse);
      expect(refreshSession.message, isNull);
      final feedback = container.read(searchRefreshFeedbackProvider);
      expect(feedback.visible, isFalse);
      expect(feedback.headline, isNull);
      expect(feedback.message, isNull);
      expect(feedback.queryAtRefresh, isNull);
      final handoff = container.read(searchPendingReindexHandoffProvider);
      expect(handoff.visible, isTrue);
      expect(handoff.message, isNotNull);
    },
  );
}
