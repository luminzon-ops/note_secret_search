import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/app/di/bootstrap_provider.dart';
import 'package:note_secret_search/core/storage/database/app_database.dart';
import 'package:note_secret_search/features/ai_models/application/model_download_providers.dart';
import 'package:note_secret_search/features/ai_models/domain/model_download_repository.dart';
import 'package:note_secret_search/features/ai_models/domain/model_download_task.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_repository.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/sqlite_model_lifecycle_store.dart';

import '../../../support/fake_app_database.dart';

void main() {
  test('lifecycle provider keeps SQLite as the transaction owner', () {
    final container = ProviderContainer(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(
          FakeAppDatabase(initialStatus: DatabaseLifecycleStatus.open),
        ),
        modelDownloadRepositoryProvider.overrideWithValue(
          const _StubDownloadRepository(),
        ),
        modelRegistryRepositoryProvider.overrideWithValue(
          const _StubRegistryRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(
      container.read(modelLifecycleStoreProvider),
      isA<SqliteModelLifecycleStore>(),
    );
  });
}

class _StubDownloadRepository implements ModelDownloadRepository {
  const _StubDownloadRepository();

  @override
  Future<ModelDownloadTask?> findLatestTaskByModel(String modelId) async =>
      null;

  @override
  Future<ModelDownloadTask?> findLatestTaskByModelAndSource(
    String modelId,
    String sourceId,
  ) async => null;

  @override
  Future<List<ModelDownloadTask>> listTasks() async =>
      const <ModelDownloadTask>[];

  @override
  Future<void> saveTask(ModelDownloadTask task) async {}
}

class _StubRegistryRepository implements ModelRegistryRepository {
  const _StubRegistryRepository();

  @override
  Future<void> deleteById(String id) async {}

  @override
  Future<ModelRegistryEntry?> getById(String id) async => null;

  @override
  Future<List<ModelRegistryEntry>> listInstalledModels() async =>
      const <ModelRegistryEntry>[];

  @override
  Future<void> save(ModelRegistryEntry entry) async {}
}
