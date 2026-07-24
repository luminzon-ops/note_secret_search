import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/app/di/bootstrap_provider.dart';
import 'package:note_secret_search/core/storage/database/sqlite_model_state_repository.dart';
import 'package:note_secret_search/features/ai_models/domain/model_catalog_entry.dart';
import 'package:note_secret_search/features/ai_models/domain/model_catalog_repository.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/asset_model_catalog_repository.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/model_catalog_trust.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/sqlite_model_catalog_acceptance_store.dart';

final modelCatalogRepositoryProvider = Provider<ModelCatalogRepository>((ref) {
  return AssetModelCatalogRepository(
    assetBundle: rootBundle,
    acceptanceStore: ref.watch(modelCatalogAcceptanceStoreProvider),
  );
});

final modelCatalogAcceptanceStoreProvider =
    Provider<ModelCatalogAcceptanceStore>((ref) {
      return SqliteModelCatalogAcceptanceStore(
        repository: SqliteModelStateRepository(
          database: ref.watch(appDatabaseProvider),
        ),
      );
    });

final modelCatalogEntriesProvider = FutureProvider<List<ModelCatalogEntry>>((
  ref,
) async {
  return ref.watch(modelCatalogRepositoryProvider).loadCatalog();
});
