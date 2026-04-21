import 'package:note_secret_search/features/ai_models/domain/model_catalog_entry.dart';

abstract interface class ModelCatalogRepository {
  Future<List<ModelCatalogEntry>> loadCatalog();
}
