import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/features/ai_models/domain/model_catalog_entry.dart';
import 'package:note_secret_search/features/ai_models/domain/model_catalog_repository.dart';
import 'package:note_secret_search/features/ai_models/domain/model_catalog_trust.dart';

final modelCatalogRepositoryProvider = Provider<ModelCatalogRepository>((ref) {
  throw StateError(
    'modelCatalogRepositoryProvider must be overridden by app composition',
  );
});

final modelCatalogAcceptanceStoreProvider = Provider<ModelCatalogAcceptanceStore>((
  ref,
) {
  throw StateError(
    'modelCatalogAcceptanceStoreProvider must be overridden by app composition',
  );
});

final modelCatalogEntriesProvider = FutureProvider<List<ModelCatalogEntry>>((
  ref,
) async {
  return ref.watch(modelCatalogRepositoryProvider).loadCatalog();
});
