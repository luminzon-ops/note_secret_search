import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/features/ai_models/domain/model_catalog_entry.dart';
import 'package:note_secret_search/features/ai_models/domain/model_catalog_repository.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/asset_model_catalog_repository.dart';

final modelCatalogRepositoryProvider = Provider<ModelCatalogRepository>((ref) {
  return AssetModelCatalogRepository(assetBundle: rootBundle);
});

final modelCatalogEntriesProvider = FutureProvider<List<ModelCatalogEntry>>((ref) async {
  return ref.watch(modelCatalogRepositoryProvider).loadCatalog();
});
